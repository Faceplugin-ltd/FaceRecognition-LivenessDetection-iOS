import AVFoundation
import FaceRecognitionKit
import PhotosUI
import UIKit

/// Live camera identify with a status chip, shutter, Gallery and Auto.
/// The Attribute tab is the same screen in `.attribute` mode, as on Android.
final class IdentifyViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    enum Mode { case identify, attribute }

    private enum Status {
        case ok, noFace, moveCloser, many

        var text: String {
            switch self {
            case .ok: return "Face found"
            case .noFace: return "No face"
            case .moveCloser: return "Move closer"
            case .many: return "More than one face"
            }
        }

        var good: Bool { self == .ok }
    }

    /// Auto fires once one good face has stayed in place this long.
    private static let autoStableSeconds: CFTimeInterval = 0.3

    private let mode: Mode

    private let cameraView = UIView()
    private let freezeView = UIImageView()
    private let statusChip = Ui.pill("No face", color: Ui.cameraChip)
    private let thresholdChip = Ui.pill("", color: Ui.cameraChip)
    private let countChip = Ui.pill("", color: Ui.cameraChip)
    private let messageBox = Ui.card()
    private let messageLabel = Ui.label(size: 15)
    private let messageButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .large)
    private let shutter = UIButton(type: .custom)
    private let autoSwitch = UISwitch()

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.faceplugin.identify.session")
    private let frameQueue = DispatchQueue(label: "com.faceplugin.identify.frames")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var cameraPosition: AVCaptureDevice.Position = .front

    private var busy = false
    private var framePending = false
    private var lastFrame: UIImage?
    private var lastStatus: Status = .noFace
    private var stableSince: CFTimeInterval = 0
    private var lastCentre: CGPoint?
    private var engineToken: UUID?

    init(mode: Mode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = mode == .attribute ? "Attribute" : "Identity"
        view.backgroundColor = .systemBackground
        buildLayout()

        engineToken = FaceEngine.shared.addListener { [weak self] _ in self?.refreshEngineState() }
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshCount),
            name: FaceGallery.didChange, object: nil
        )
    }

    deinit {
        if let engineToken { FaceEngine.shared.removeListener(engineToken) }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        busy = false
        setBusy(false)
        thresholdChip.text = "Threshold \(Ui.score(AppSettings.threshold))"
        autoSwitch.isOn = AppSettings.autoCapture
        refreshCount()
        refreshEngineState()
        startCameraIfAllowed()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = cameraView.bounds
    }

    // MARK: - Layout

    private func buildLayout() {
        [cameraView, freezeView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        cameraView.backgroundColor = .black
        freezeView.contentMode = .scaleAspectFill
        freezeView.clipsToBounds = true
        freezeView.isHidden = true

        let chips = Ui.stack([UIView(), statusChip, UIView()], axis: .horizontal, spacing: 8, alignment: .center)
        let bottomChips = Ui.stack([thresholdChip, UIView(), countChip], axis: .horizontal, spacing: 8, alignment: .center)

        messageLabel.textColor = .label
        messageButton.setTitle("Allow camera", for: .normal)
        messageButton.addTarget(self, action: #selector(messageActionTapped), for: .touchUpInside)
        let messageStack = Ui.stack([messageLabel, messageButton], spacing: 8)
        messageBox.translatesAutoresizingMaskIntoConstraints = false
        messageBox.addSubview(messageStack)
        NSLayoutConstraint.activate([
            messageStack.topAnchor.constraint(equalTo: messageBox.topAnchor, constant: 12),
            messageStack.leadingAnchor.constraint(equalTo: messageBox.leadingAnchor, constant: 12),
            messageStack.trailingAnchor.constraint(equalTo: messageBox.trailingAnchor, constant: -12),
            messageStack.bottomAnchor.constraint(equalTo: messageBox.bottomAnchor, constant: -12),
        ])
        messageBox.isHidden = true

        shutter.backgroundColor = .white
        shutter.layer.cornerRadius = 36
        shutter.layer.borderWidth = 4
        shutter.layer.borderColor = UIColor.black.withAlphaComponent(0.2).cgColor
        shutter.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
        shutter.widthAnchor.constraint(equalToConstant: 72).isActive = true
        shutter.heightAnchor.constraint(equalToConstant: 72).isActive = true

        let gallery = UIButton(type: .system)
        gallery.setImage(UIImage(systemName: "photo.on.rectangle"), for: .normal)
        gallery.setTitle(" Gallery", for: .normal)
        gallery.tintColor = .white
        gallery.addTarget(self, action: #selector(galleryTapped), for: .touchUpInside)

        autoSwitch.addTarget(self, action: #selector(autoChanged), for: .valueChanged)
        let autoLabel = Ui.label("Auto", size: 13, color: .white)
        let autoStack = Ui.stack([autoSwitch, autoLabel], spacing: 2, alignment: .center)

        let switchCamera = UIButton(type: .system)
        switchCamera.setImage(UIImage(systemName: "arrow.triangle.2.circlepath.camera"), for: .normal)
        switchCamera.tintColor = .white
        switchCamera.addTarget(self, action: #selector(switchCameraTapped), for: .touchUpInside)

        let leftSlot = Ui.stack([gallery], axis: .horizontal, spacing: 0, alignment: .center)
        let rightSlot = Ui.stack([autoStack], axis: .horizontal, spacing: 0, alignment: .center)
        let bar = Ui.stack([leftSlot, shutter, rightSlot], axis: .horizontal, spacing: 12, alignment: .center)
        bar.distribution = .equalCentering
        leftSlot.widthAnchor.constraint(equalTo: rightSlot.widthAnchor).isActive = true
        let barBackground = UIView()
        barBackground.backgroundColor = .black
        barBackground.translatesAutoresizingMaskIntoConstraints = false
        barBackground.addSubview(bar)

        spinner.hidesWhenStopped = true
        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false

        [chips, bottomChips, messageBox, barBackground, spinner, switchCamera].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            cameraView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            cameraView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cameraView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cameraView.bottomAnchor.constraint(equalTo: barBackground.topAnchor),

            freezeView.topAnchor.constraint(equalTo: cameraView.topAnchor),
            freezeView.leadingAnchor.constraint(equalTo: cameraView.leadingAnchor),
            freezeView.trailingAnchor.constraint(equalTo: cameraView.trailingAnchor),
            freezeView.bottomAnchor.constraint(equalTo: cameraView.bottomAnchor),

            chips.topAnchor.constraint(equalTo: cameraView.topAnchor, constant: 12),
            chips.leadingAnchor.constraint(equalTo: cameraView.leadingAnchor, constant: 16),
            chips.trailingAnchor.constraint(equalTo: cameraView.trailingAnchor, constant: -16),

            switchCamera.topAnchor.constraint(equalTo: chips.bottomAnchor, constant: 12),
            switchCamera.trailingAnchor.constraint(equalTo: cameraView.trailingAnchor, constant: -16),

            bottomChips.leadingAnchor.constraint(equalTo: cameraView.leadingAnchor, constant: 16),
            bottomChips.trailingAnchor.constraint(equalTo: cameraView.trailingAnchor, constant: -16),
            bottomChips.bottomAnchor.constraint(equalTo: cameraView.bottomAnchor, constant: -16),

            messageBox.leadingAnchor.constraint(equalTo: cameraView.leadingAnchor, constant: 16),
            messageBox.trailingAnchor.constraint(equalTo: cameraView.trailingAnchor, constant: -16),
            messageBox.centerYAnchor.constraint(equalTo: cameraView.centerYAnchor),

            spinner.centerXAnchor.constraint(equalTo: cameraView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: cameraView.centerYAnchor),

            barBackground.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            barBackground.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            barBackground.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            bar.topAnchor.constraint(equalTo: barBackground.topAnchor, constant: 12),
            bar.leadingAnchor.constraint(equalTo: barBackground.leadingAnchor, constant: 24),
            bar.trailingAnchor.constraint(equalTo: barBackground.trailingAnchor, constant: -24),
            bar.bottomAnchor.constraint(equalTo: barBackground.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
    }

    // MARK: - State

    @objc private func refreshCount() {
        FaceEngine.shared.worker.async {
            let n = FaceGallery.shared.count()
            DispatchQueue.main.async { self.countChip.text = Ui.facesCount(n) }
        }
    }

    private func refreshEngineState() {
        let authorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if !authorized {
            showMessage("Camera access is needed to identify a face.", action: "Allow camera")
        } else if !FaceEngine.shared.isReady {
            showMessage(FaceEngine.shared.stateMessage(), action: nil)
        } else {
            messageBox.isHidden = true
        }
        shutter.isEnabled = FaceEngine.shared.isReady && !busy
        shutter.alpha = shutter.isEnabled ? 1 : 0.4
    }

    private func showMessage(_ text: String, action: String?) {
        messageBox.isHidden = false
        messageLabel.text = text
        messageButton.isHidden = action == nil
        if let action { messageButton.setTitle(action, for: .normal) }
    }

    @objc private func messageActionTapped() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if granted { self.startCameraIfAllowed() }
                self.refreshEngineState()
            }
        }
    }

    private func setBusy(_ on: Bool) {
        busy = on
        if on {
            spinner.startAnimating()
            statusChip.text = mode == .attribute ? "Reading attributes" : "Identifying"
        } else {
            spinner.stopAnimating()
        }
        shutter.isEnabled = !on && FaceEngine.shared.isReady
        shutter.alpha = shutter.isEnabled ? 1 : 0.4
    }

    private func setStatus(_ status: Status) {
        statusChip.text = status.text
        statusChip.backgroundColor = status.good ? Ui.statusMatch : Ui.cameraChip
    }

    // MARK: - Camera

    private func startCameraIfAllowed() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        framePending = false
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureSession()
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    private func stopCamera() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
        if let frame = lastFrame {
            freezeView.image = frame
            freezeView.isHidden = false
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.sessionPreset = .hd1280x720
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        if session.outputs.isEmpty {
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: frameQueue)
            if session.canAddOutput(output) { session.addOutput(output) }
        }
        if let connection = session.outputs.first?.connection(with: .video) {
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
            // Portrait on the back-camera data output is 180° from the preview.
            // Leave that buffer in sensor landscape; CameraFrameUtils rotates it −90°,
            // the same turn as the front camera.
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = cameraPosition == .front ? .portrait : .landscapeRight
            }
        }
        session.commitConfiguration()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.previewLayer == nil {
                let layer = AVCaptureVideoPreviewLayer(session: self.session)
                layer.videoGravity = .resizeAspectFill
                layer.frame = self.cameraView.bounds
                layer.connection?.videoOrientation = .portrait
                self.cameraView.layer.insertSublayer(layer, at: 0)
                self.previewLayer = layer
            }
        }
    }

    @objc private func switchCameraTapped() {
        cameraPosition = cameraPosition == .front ? .back : .front
        sessionQueue.async { [weak self] in self?.configureSession() }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // The coach keeps reading frames while a search runs. Dropping them until the
        // engine came back froze the boxes and the status chip on whatever the last frame
        // had said, which is what made the camera look stopped. The engine queue already
        // serialises the calls, so this only ever waits its turn.
        guard !framePending, FaceEngine.shared.isReady else { return }
        guard let frame = CameraFrameUtils.liveEngineImage(from: sampleBuffer, frontCamera: cameraPosition == .front) else {
            return
        }
        framePending = true
        FaceEngine.shared.worker.async { [weak self] in
            guard let self else { return }
            defer { self.framePending = false }
            // The guide only needs the box: no pose, no eyes, no liveness, so each frame stays cheap.
            var param = FaceDetectionParam()
            param.pose = false
            param.landmarks = false
            let faces = FaceDetector.detect(frame, param: param)
            DispatchQueue.main.async { self.handle(faces: faces, frame: frame) }
        }
    }

    private func handle(faces: [FaceBox], frame: UIImage) {
        let status: Status
        if faces.isEmpty {
            status = .noFace
        } else if faces.count > 1 {
            status = .many
        } else if faces[0].box.width < frame.size.width * 0.28 {
            status = .moveCloser
        } else {
            status = .ok
        }

        lastFrame = frame
        let now = CACurrentMediaTime()
        if status == .ok {
            let centre = CGPoint(x: faces[0].box.midX, y: faces[0].box.midY)
            let moved = lastCentre.map {
                abs($0.x - centre.x) > frame.size.width * 0.06 || abs($0.y - centre.y) > frame.size.height * 0.06
            } ?? true
            if moved || stableSince == 0 { stableSince = now }
            lastCentre = centre
        } else {
            stableSince = 0
            lastCentre = nil
        }
        lastStatus = status

        freezeView.isHidden = true
        // While a search is running the chip says so; everything else keeps moving.
        if !busy { setStatus(status) }

        let autoFire = status == .ok && autoSwitch.isOn && stableSince != 0
            && now - stableSince >= IdentifyViewController.autoStableSeconds
        if autoFire && !busy {
            stableSince = 0
            run(on: frame)
        }
    }

    // MARK: - Actions

    @objc private func autoChanged() {
        AppSettings.autoCapture = autoSwitch.isOn
        stableSince = 0
    }

    @objc private func shutterTapped() {
        guard !busy else { return }
        guard let frame = lastFrame, lastStatus != .noFace else {
            present(message: FaceGallery.noFace)
            return
        }
        run(on: frame)
    }

    @objc private func galleryTapped() {
        guard !busy else { return }
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func run(on probe: UIImage) {
        setBusy(true)
        FaceEngine.shared.worker.async { [weak self] in
            guard let self else { return }
            if self.mode == .attribute {
                let result = FaceGallery.shared.attributes(probe, limits: AppSettings.limits)
                DispatchQueue.main.async {
                    ResultStore.attribute = result
                    self.setBusy(false)
                    self.navigationController?.pushViewController(
                        AttributeResultViewController(result: result), animated: true
                    )
                }
                return
            }
            let outcome = FaceGallery.shared.identify(probe, limits: AppSettings.limits, livenessOn: AppSettings.livenessOn)
            DispatchQueue.main.async {
                switch outcome {
                case let .done(result):
                    ResultStore.identify = result
                    self.setBusy(false)
                    self.navigationController?.pushViewController(
                        ResultViewController(result: result), animated: true
                    )
                case let .rejected(reason, report):
                    guard let report else {
                        self.setBusy(false)
                        self.present(message: reason)
                        return
                    }
                    // Stay busy while the status is open so Auto does not fire again behind it.
                    StatusCardView.present(on: self, title: "Identify stopped", reason: reason, report: report) {
                        self.stableSince = 0
                        self.setBusy(false)
                    }
                }
            }
        }
    }

    private func present(message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension IdentifyViewController: PHPickerViewControllerDelegate {

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
        setBusy(true)
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let self else { return }
            guard let image = object as? UIImage else {
                DispatchQueue.main.async {
                    self.setBusy(false)
                    self.present(message: "That photo could not be read.")
                }
                return
            }
            let prepared = ImageUtils.scaleDown(ImageUtils.upright(image), maxSide: ImageUtils.engineMaxSide)
            DispatchQueue.main.async { self.run(on: prepared) }
        }
    }
}
