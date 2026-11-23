import AVFoundation
import FaceRecognitionKit
import UIKit

/// The capture coach: an oval guide, live coaching, and a hold-to-capture that only fires on a
/// good frame. Once a still is captured it is checked with every attribute the engine returns and
/// handed to `onCaptureAnalyzed`.
///
/// Subclass it and supply the panel to show after the capture:
///
/// ```swift
/// final class AddPersonViewController: FaceCaptureViewController {
///     private let panel = EnrollPanelView()
///
///     override func resultPanelView() -> UIView { panel }
///     override func limits() -> FaceLimits { AppSettings.limits }
///
///     override func onCaptureAnalyzed(_ face: FaceBox?, faceCount: Int) {
///         panel.show(face, faceCount: faceCount, limits: limits())
///     }
/// }
/// ```
open class FaceCaptureViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: - Views

    public let cameraView = UIView()
    public let overlay = CaptureOverlayView()
    public let warningLabel = UILabel()
    /// Shown once a still has been captured; holds `resultPanelView()` in a scroll view.
    public let resultContainer = UIView()

    private let scrollView = UIScrollView()
    private var faceSpaceHeight: NSLayoutConstraint?
    private var keyboardOverlap: CGFloat = 0
    private var keyboardTokens: [NSObjectProtocol] = []
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.faceplugin.capture.session")
    private let frameQueue = DispatchQueue(label: "com.faceplugin.capture.frames")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var reviewSheet: ReviewSheetViewController?
    private var panelView: UIView?
    private var isActive = false
    /// Drop frames while the previous one is still in the engine.
    private var framePending = false

    // MARK: - Capture state

    private var capturedImage: UIImage?
    private var capturedFace: FaceBox?
    private var holdImage: UIImage?
    private var holdFace: FaceBox?
    private var lastFrameSize: CGSize = CameraFrameUtils.androidPreviewSize

    /// Add one person always uses the front camera, as on Android.
    private let cameraPosition: AVCaptureDevice.Position = .front

    /// Per-frame guide check: box, landmarks and pose only, so each frame stays cheap.
    private let trackingParam = FaceDetectionParam()

    // MARK: - Subclass hooks

    /// The panel to show once a still has been captured and checked — your own review, fields
    /// and buttons. It is placed in a scrolling container under the captured face.
    open func resultPanelView() -> UIView {
        UIView()
    }

    /// The thresholds the guide checks against. Override to use your own settings.
    open func limits() -> FaceLimits {
        .default
    }

    /// Called on the main queue when the still starts its full attribute check.
    open func onCaptureAnalyzing() {}

    /// Called on the main queue with the captured still's largest face (nil when none) and how
    /// many faces the still holds.
    open func onCaptureAnalyzed(_ face: FaceBox?, faceCount: Int) {}

    /// The captured still, or nil before a capture.
    public func capturedPhoto() -> UIImage? { capturedImage }

    public func hasCapture() -> Bool { capturedImage != nil && capturedFace != nil }

    /// Whether the review is presented as a full-height sheet rather than a panel under the
    /// captured face. True by default: the enrollment status that follows is a sheet, and two
    /// different surfaces for two consecutive steps reads as two different screens.
    ///
    /// Override to `false` for the inline panel.
    open func resultPanelInSheet() -> Bool { true }

    /// Shows the review, as a sheet or as the inline panel.
    private func showResultPanel() {
        guard resultPanelInSheet() else {
            resultContainer.isHidden = false
            return
        }
        guard reviewSheet == nil, let panel = panelView else { return }
        let sheetController = ReviewSheetViewController(
            panel: panel,
            onKeyboard: { [weak self] visible in self?.onReviewKeyboardChanged(visible) },
            onDismiss: { [weak self] in
                // Dismissing is a retake, not a silent exit: the capture is not yet enrolled.
                self?.reviewSheet = nil
                self?.retakeCapture()
            })
        reviewSheet = sheetController
        present(sheetController, animated: true)
    }

    /// Hides the review without treating it as a cancel.
    private func hideResultPanel() {
        resultContainer.isHidden = true
        guard let sheetController = reviewSheet else { return }
        reviewSheet = nil
        sheetController.onDismiss = nil
        sheetController.dismiss(animated: true)
    }

    /// Closes the review once the capture has been accepted, e.g. after a successful enroll.
    public func dismissResultPanel() {
        hideResultPanel()
    }

    /// Called when the keyboard opens or closes over the review sheet. Shrink whatever can
    /// give way — on a short screen the fields and buttons have to stay reachable.
    open func onReviewKeyboardChanged(_ visible: Bool) {}

    /// Back to the live guide for a new capture.
    open func retakeCapture() {
        hideResultPanel()
        warningLabel.text = ""
        capturedImage = nil
        capturedFace = nil
        clearHold()
        overlay.setFaceBoxes(nil)
        overlay.setCapturedBitmap(nil)
        overlay.setViewMode(.noFacePrepare)
        startSession()
    }

    // MARK: - Lifecycle

    open override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildLayout()

        overlay.setMirrorX(cameraPosition == .front)
        overlay.onCaptureHoldFinished = { [weak self] in self?.onHoldFinished() }
        overlay.onCaptureAnimationFinished = { [weak self] in self?.analyzeCapturedStill() }
        overlay.setViewMode(.noFacePrepare)
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.isTranslucent = true
        navigationController?.setNavigationBarHidden(false, animated: animated)
        observeKeyboard()
        if overlay.viewMode != .faceCaptureDone { startSession() }
    }

    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopKeyboard()
        stopSession()
        clearHold()
        overlay.setFaceBoxes(nil)
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = cameraView.bounds
        if let connection = previewLayer?.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        applyFaceSpaceHeight()
    }

    // MARK: - Layout

    private func buildLayout() {
        [cameraView, overlay, warningLabel, resultContainer].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        cameraView.backgroundColor = .black
        overlay.backgroundColor = .clear
        overlay.isUserInteractionEnabled = false

        // The host supplies the navigation bar. The camera fills the screen, so the
        // default dark chevron disappears on the preview — use a white back control.
        if title == nil { title = "Face Capture" }
        let bar = UINavigationBarAppearance()
        bar.configureWithTransparentBackground()
        bar.titleTextAttributes = [.foregroundColor: UIColor.white]
        navigationItem.standardAppearance = bar
        navigationItem.scrollEdgeAppearance = bar
        navigationItem.compactAppearance = bar
        navigationController?.navigationBar.tintColor = .white
        navigationItem.hidesBackButton = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: self,
            action: #selector(closeTapped)
        )

        warningLabel.textColor = .systemRed
        warningLabel.font = .systemFont(ofSize: 16)
        warningLabel.textAlignment = .right

        resultContainer.isHidden = true
        resultContainer.backgroundColor = .clear

        // The captured face stays visible above the panel, as on Android.
        let faceSpace = UIView()
        faceSpace.translatesAutoresizingMaskIntoConstraints = false
        faceSpace.backgroundColor = .clear
        resultContainer.addSubview(faceSpace)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .systemBackground
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        resultContainer.addSubview(scrollView)

        let panel = resultPanelView()
        panelView = panel
        panel.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(panel)

        NSLayoutConstraint.activate([
            cameraView.topAnchor.constraint(equalTo: view.topAnchor),
            cameraView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cameraView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cameraView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            warningLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            warningLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            resultContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            resultContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            resultContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            resultContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            faceSpace.topAnchor.constraint(equalTo: resultContainer.topAnchor),
            faceSpace.leadingAnchor.constraint(equalTo: resultContainer.leadingAnchor),
            faceSpace.trailingAnchor.constraint(equalTo: resultContainer.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: faceSpace.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: resultContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: resultContainer.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: resultContainer.bottomAnchor),

            panel.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            panel.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            panel.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
        let faceHeight = faceSpace.heightAnchor.constraint(equalToConstant: 0)
        faceHeight.isActive = true
        faceSpaceHeight = faceHeight
    }

    // MARK: - Keyboard

    private func observeKeyboard() {
        guard keyboardTokens.isEmpty else { return }
        let center = NotificationCenter.default
        keyboardTokens = [
            center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] n in
                self?.applyKeyboard(n)
            },
            center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] n in
                self?.applyKeyboard(n)
            },
        ]
    }

    private func stopKeyboard() {
        keyboardTokens.forEach { NotificationCenter.default.removeObserver($0) }
        keyboardTokens.removeAll()
        keyboardOverlap = 0
        scrollView.contentInset.bottom = 0
        scrollView.verticalScrollIndicatorInsets.bottom = 0
    }

    private func applyKeyboard(_ notification: Notification) {
        let end = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)
            .map { view.convert($0, from: nil) } ?? .zero
        let overlap = max(0, view.bounds.maxY - end.minY)
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        keyboardOverlap = overlap
        scrollView.contentInset.bottom = overlap
        scrollView.verticalScrollIndicatorInsets.bottom = overlap
        applyFaceSpaceHeight()
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
            self.scrollEnrollFieldsIntoView()
        }
    }

    /// Shrink the captured-face square while the keyboard is up so Name / Note / Enroll stay on screen.
    private func applyFaceSpaceHeight() {
        let width = resultContainer.bounds.width
        guard width > 1 else { return }
        if keyboardOverlap > 0 {
            let minPanel: CGFloat = 280
            let available = resultContainer.bounds.height - keyboardOverlap
            faceSpaceHeight?.constant = min(width, max(88, available - minPanel))
        } else {
            faceSpaceHeight?.constant = width
        }
    }

    private func scrollEnrollFieldsIntoView() {
        guard !resultContainer.isHidden, keyboardOverlap > 0 else { return }
        let field = resultContainer.findFirstResponder() ?? scrollView
        let rect = field.convert(field.bounds, to: scrollView).insetBy(dx: 0, dy: -24)
        scrollView.scrollRectToVisible(rect, animated: false)
    }

    @objc private func closeTapped() {
        if let sheet = reviewSheet {
            sheet.onDismiss = nil
            reviewSheet = nil
            sheet.dismiss(animated: false)
        }
        if let navigationController {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    // MARK: - Camera

    private func startSession() {
        isActive = true
        framePending = false
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureSessionIfNeeded()
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    private func stopSession() {
        isActive = false
        framePending = false
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func configureSessionIfNeeded() {
        guard session.inputs.isEmpty else { return }
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: frameQueue)
        if session.canAddOutput(output) {
            session.addOutput(output)
            if let connection = output.connection(with: .video) {
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = false
                }
                // Portrait on the back-camera data output is 180° from the preview.
                // Leave that buffer in sensor landscape; CameraFrameUtils rotates it −90°.
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = cameraPosition == .front ? .portrait : .landscapeRight
                }
            }
        }
        session.commitConfiguration()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let layer = AVCaptureVideoPreviewLayer(session: self.session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = self.cameraView.bounds
            if let connection = layer.connection, connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            self.cameraView.layer.insertSublayer(layer, at: 0)
            self.previewLayer = layer
        }
    }

    /// True while the guide is animating in, already finished, or the engine is not ready.
    private var skipFrame: Bool {
        overlay.viewMode == .noFacePrepare
            || overlay.viewMode == .faceCaptureDone
            || !FaceEngine.shared.isReady
    }

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard isActive, !framePending, !skipFrame else { return }
        guard let frame = CameraFrameUtils.liveEngineImage(from: sampleBuffer, frontCamera: cameraPosition == .front) else {
            return
        }
        framePending = true
        FaceEngine.shared.worker.async { [weak self] in
            guard let self else { return }
            defer { self.framePending = false }
            guard !self.skipFrame else { return }
            let faces = FaceDetector.detect(frame, param: self.trackingParam)
            DispatchQueue.main.async {
                self.applyTracking(faces, frame: frame)
            }
        }
    }

    // MARK: - Tracking and hold

    private func applyTracking(_ faces: [FaceBox], frame: UIImage) {
        guard !skipFrame else { return }
        lastFrameSize = frame.size
        let state = CaptureFaceChecker.checkFace(faces, frameSize: frame.size, limits: limits())

        switch overlay.viewMode {
        case .repeatNoFacePrepare:
            if state > .noFace { overlay.setViewMode(.toFaceCircle) }
        case .faceCircle:
            overlay.setFrameSize(frame.size)
            overlay.setFaceBoxes(faces)
            if state == .noFace {
                cancelHold()
                warningLabel.text = ""
                overlay.setViewMode(.faceCircleToNoFace)
            } else if state == .captureOk, let face = faces.first {
                warningLabel.text = ""
                holdImage = frame
                holdFace = face
                overlay.startCaptureHold()
            } else {
                cancelHold()
                warningLabel.text = CaptureFaceChecker.warning(for: state)
            }
        default:
            break
        }
    }

    /// The held face stayed valid for the hold window. Keep the newest frame from it.
    private func onHoldFinished() {
        guard overlay.viewMode == .faceCircle else { return }
        guard let image = holdImage, let face = holdFace else {
            cancelHold()
            return
        }
        capturedImage = image
        capturedFace = face
        holdImage = nil
        holdFace = nil
        overlay.setCapturedBitmap(image)
        overlay.setViewMode(.faceCapturePrepare)
    }

    private func cancelHold() {
        overlay.cancelCaptureHold()
        clearHold()
    }

    private func clearHold() {
        holdImage = nil
        holdFace = nil
    }

    // MARK: - The captured still

    private func analyzeCapturedStill() {
        guard let image = capturedImage else {
            onCaptureAnalyzed(nil, faceCount: 0)
            return
        }
        stopSession()
        showResultPanel()
        onCaptureAnalyzing()

        let fallback = capturedFace
        FaceEngine.shared.worker.async { [weak self] in
            let faces = FaceDetector.detect(image, param: .allAttributes())
            // detect() returns largest first, so the first face is the one the guide framed.
            let shown = faces.first ?? fallback
            let count = faces.isEmpty ? (fallback == nil ? 0 : 1) : faces.count
            DispatchQueue.main.async {
                guard let self else { return }
                self.capturedFace = shown
                self.onCaptureAnalyzed(shown, faceCount: count)
            }
        }
    }
}

private extension UIView {
    func findFirstResponder() -> UIView? {
        if isFirstResponder { return self }
        for sub in subviews {
            if let found = sub.findFirstResponder() { return found }
        }
        return nil
    }
}


/// Holds the capture review in a full-height sheet — the same surface the enrollment status
/// uses straight after it.
final class ReviewSheetViewController: UIViewController {

    var onDismiss: (() -> Void)?
    private let panel: UIView
    private let onKeyboard: (Bool) -> Void
    private let scroll = UIScrollView()
    private var keyboardTokens: [NSObjectProtocol] = []

    init(panel: UIView, onKeyboard: @escaping (Bool) -> Void, onDismiss: (() -> Void)?) {
        self.panel = panel
        self.onKeyboard = onKeyboard
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
        if let sheet = sheetPresentationController {
            sheet.detents = [.large()]
            sheet.selectedDetentIdentifier = .large
            sheet.prefersGrabberVisible = true
        }
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .interactive
        scroll.alwaysBounceVertical = true
        // A tap that is not on a control dismisses the keyboard. Buttons still receive it.
        let dismiss = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        dismiss.cancelsTouchesInView = false
        scroll.addGestureRecognizer(dismiss)
        view.addSubview(scroll)

        panel.removeFromSuperview()
        panel.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(panel)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            panel.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            panel.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            panel.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        observeKeyboard()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        keyboardTokens.forEach { NotificationCenter.default.removeObserver($0) }
        keyboardTokens = []
        onDismiss?()
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    /// The keyboard overlaps the sheet rather than resizing it, so the scroll view is inset by
    /// however much of it is covered. Without this the Enroll button sits under the keys.
    private func observeKeyboard() {
        guard keyboardTokens.isEmpty else { return }
        let centre = NotificationCenter.default
        let apply: (Notification) -> Void = { [weak self] note in
            guard let self else { return }
            let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                as? NSValue)?.cgRectValue ?? .zero
            let covered = max(0, self.view.bounds.maxY - self.view.convert(frame, from: nil).minY)
            self.scroll.contentInset.bottom = covered
            self.scroll.verticalScrollIndicatorInsets.bottom = covered
            self.onKeyboard(covered > 0)
        }
        keyboardTokens = [
            centre.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification,
                               object: nil, queue: .main, using: apply),
            centre.addObserver(forName: UIResponder.keyboardWillHideNotification,
                               object: nil, queue: .main) { [weak self] _ in
                self?.scroll.contentInset.bottom = 0
                self?.scroll.verticalScrollIndicatorInsets.bottom = 0
                self?.onKeyboard(false)
            },
        ]
    }
}
