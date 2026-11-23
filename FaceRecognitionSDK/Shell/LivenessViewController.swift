import AVFoundation
import FaceRecognitionKit
import UIKit

/// Face boxes with their liveness score, drawn over the preview.
///
/// The engine works on a frame that is scaled down and, on the front camera, not mirrored,
/// while the preview fills the view and is mirrored. Boxes are mapped with the same
/// fill-centre maths the preview layer uses, so they sit on the face rather than near it.
final class LivenessOverlayView: UIView {

    struct Face {
        let box: CGRect
        let liveness: Float
        let live: Bool
    }

    private var faces: [Face] = []
    private var frameSize: CGSize = .zero
    private var mirrored = true

    func submit(faces: [Face], frameSize: CGSize, mirrored: Bool) {
        self.faces = faces
        self.frameSize = frameSize
        self.mirrored = mirrored
        setNeedsDisplay()
    }

    func clear() {
        submit(faces: [], frameSize: frameSize, mirrored: mirrored)
    }

    override func draw(_ rect: CGRect) {
        guard frameSize.width > 0, frameSize.height > 0, !faces.isEmpty,
              let context = UIGraphicsGetCurrentContext() else { return }

        let scale = max(bounds.width / frameSize.width, bounds.height / frameSize.height)
        let dx = (bounds.width - frameSize.width * scale) / 2
        let dy = (bounds.height - frameSize.height * scale) / 2

        for face in faces {
            var left = face.box.minX * scale + dx
            var right = face.box.maxX * scale + dx
            let top = face.box.minY * scale + dy
            let bottom = face.box.maxY * scale + dy
            if mirrored {
                let mirroredLeft = bounds.width - right
                right = bounds.width - left
                left = mirroredLeft
            }

            let colour: UIColor = face.live
                ? UIColor(red: 0.18, green: 0.90, blue: 0.65, alpha: 1)
                : UIColor(red: 1.00, green: 0.42, blue: 0.42, alpha: 1)
            let box = CGRect(x: left, y: top, width: right - left, height: bottom - top)
            context.setStrokeColor(colour.cgColor)
            context.setLineWidth(3)
            UIBezierPath(roundedRect: box, cornerRadius: 9).stroke()

            let word = face.live ? "Live" : "Fake"
            let text = face.liveness.isFinite
                ? String(format: "%@  %.2f", word, face.liveness)
                : word
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: UIColor.white,
            ]
            let size = (text as NSString).size(withAttributes: attributes)
            let label = CGRect(
                x: left,
                y: max(0, top - size.height - 10),
                width: size.width + 14,
                height: size.height + 6)
            context.setFillColor(colour.cgColor)
            UIBezierPath(roundedRect: label, cornerRadius: 6).fill()
            (text as NSString).draw(
                at: CGPoint(x: label.minX + 7, y: label.minY + 3),
                withAttributes: attributes)
        }
    }
}

/// Liveness on its own: the camera, a box per face and that face's liveness score. There is
/// nothing to press — no shutter, no gallery, no result screen. It is the plainest possible
/// demonstration that the engine tells a live face from a photo of one.
final class LivenessViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    private let cameraView = UIView()
    private let overlay = LivenessOverlayView()
    private let hint = UILabel()
    private let switchButton = UIButton(type: .system)

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.faceplugin.liveness.camera")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var cameraPosition: AVCaptureDevice.Position = .front
    private var framePending = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Liveness"
        view.backgroundColor = .black

        cameraView.translatesAutoresizingMaskIntoConstraints = false
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.backgroundColor = .clear
        overlay.isUserInteractionEnabled = false

        hint.translatesAutoresizingMaskIntoConstraints = false
        hint.textColor = .white
        hint.font = .systemFont(ofSize: 14, weight: .medium)
        hint.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        hint.textAlignment = .center
        hint.layer.cornerRadius = 14
        hint.clipsToBounds = true
        hint.isHidden = true

        switchButton.translatesAutoresizingMaskIntoConstraints = false
        switchButton.setImage(UIImage(systemName: "arrow.triangle.2.circlepath.camera"), for: .normal)
        switchButton.tintColor = .white
        switchButton.addTarget(self, action: #selector(flipCamera), for: .touchUpInside)

        view.addSubview(cameraView)
        view.addSubview(overlay)
        view.addSubview(hint)
        view.addSubview(switchButton)

        NSLayoutConstraint.activate([
            cameraView.topAnchor.constraint(equalTo: view.topAnchor),
            cameraView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cameraView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cameraView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            overlay.topAnchor.constraint(equalTo: cameraView.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: cameraView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: cameraView.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: cameraView.bottomAnchor),

            switchButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            switchButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            switchButton.widthAnchor.constraint(equalToConstant: 44),
            switchButton.heightAnchor.constraint(equalToConstant: 44),

            hint.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hint.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            hint.heightAnchor.constraint(equalToConstant: 28),
            hint.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        start()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stop()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = cameraView.bounds
        if let connection = previewLayer?.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }

    @objc private func flipCamera() {
        cameraPosition = cameraPosition == .front ? .back : .front
        // Swap the lens on the running session. Stopping and starting it again
        // tears the camera down and is what made the flip take several seconds.
        queue.async { [weak self] in
            self?.configure()
        }
    }

    private func show(hintText: String) {
        hint.text = hintText.isEmpty ? nil : "  \(hintText)  "
        hint.isHidden = hintText.isEmpty
    }

    private func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            queue.async { [weak self] in self?.configureAndRun() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.queue.async { self.configureAndRun() }
                } else {
                    DispatchQueue.main.async { self.show(hintText: "Camera permission is needed") }
                }
            }
        default:
            show(hintText: "Camera permission is needed")
        }
    }

    /// Session work stays on `queue`. `startRunning` only happens the first time.
    private func configureAndRun() {
        configure()
        if !session.isRunning { session.startRunning() }
    }

    private func configure() {
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        if session.sessionPreset != .vga640x480 {
            session.sessionPreset = .vga640x480
        }

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: cameraPosition),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input) else {
            session.commitConfiguration()
            DispatchQueue.main.async { [weak self] in self?.show(hintText: "Camera unavailable") }
            return
        }
        session.addInput(input)

        if session.outputs.isEmpty {
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) { session.addOutput(output) }
        }
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
        session.commitConfiguration()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.previewLayer == nil {
                let layer = AVCaptureVideoPreviewLayer(session: self.session)
                layer.videoGravity = .resizeAspectFill
                self.cameraView.layer.insertSublayer(layer, at: 0)
                self.previewLayer = layer
            }
            self.previewLayer?.frame = self.cameraView.bounds
            self.show(hintText: "")
        }
    }

    private func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
        overlay.clear()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !framePending, FaceEngine.shared.isReady else { return }
        guard let frame = CameraFrameUtils.liveEngineImage(
            from: sampleBuffer, frontCamera: cameraPosition == .front) else { return }

        framePending = true
        FaceEngine.shared.worker.async { [weak self] in
            guard let self else { return }
            defer { self.framePending = false }
            // Liveness is the whole point of this screen, so it is the one estimator asked for.
            var param = FaceDetectionParam()
            param.pose = false
            param.landmarks = false
            param.liveness = true
            let faces = FaceDetector.detect(frame, param: param)
            let limits = AppSettings.limits
            let drawn = faces.map {
                LivenessOverlayView.Face(
                    box: $0.box,
                    liveness: Float($0.liveness),
                    live: limits.isLive($0.liveness))
            }
            DispatchQueue.main.async {
                self.overlay.submit(
                    faces: drawn,
                    frameSize: frame.size,
                    mirrored: self.cameraPosition == .front)
                self.show(hintText: drawn.isEmpty ? "No face" : "")
            }
        }
    }
}
