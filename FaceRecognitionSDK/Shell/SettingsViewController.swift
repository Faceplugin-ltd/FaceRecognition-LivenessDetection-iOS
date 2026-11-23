import FaceRecognitionKit
import UIKit

/// Match, liveness and pose thresholds, plus the license status. Reset is in the navigation bar.
final class SettingsViewController: UIViewController {

    private let content = Ui.stack([], spacing: 20)
    private let livenessSwitch = UISwitch()
    private let skipReviewSwitch = UISwitch()
    private let licenseLabel = Ui.label(size: 15, color: .secondaryLabel)
    private let sdkLabel = Ui.label(size: 15, color: .secondaryLabel)
    private let appLabel = Ui.label(size: 15, color: .secondaryLabel)

    private var thresholdRow: SliderRow?
    private var livenessRow: SliderRow?
    private var yawRow: SliderRow?
    private var rollRow: SliderRow?
    private var pitchRow: SliderRow?
    private var engineToken: UUID?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.counterclockwise"),
            style: .plain, target: self, action: #selector(resetTapped)
        )
        buildLayout()
        bind()

        engineToken = FaceEngine.shared.addListener { [weak self] _ in self?.refreshLicense() }
        refreshLicense()
    }

    deinit {
        if let engineToken { FaceEngine.shared.removeListener(engineToken) }
    }

    private func buildLayout() {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(content)

        let threshold = SliderRow(
            title: "Match threshold",
            range: AppSettings.minThreshold...AppSettings.maxThreshold,
            step: 0.01,
            format: { Ui.score($0) }
        ) { AppSettings.threshold = $0 }
        thresholdRow = threshold

        livenessSwitch.addTarget(self, action: #selector(livenessChanged), for: .valueChanged)
        let livenessToggle = Ui.stack(
            [Ui.label("Liveness check", size: 16), UIView(), livenessSwitch],
            axis: .horizontal, spacing: 12, alignment: .center
        )

        skipReviewSwitch.addTarget(self, action: #selector(skipReviewChanged), for: .valueChanged)
        let skipReviewToggle = Ui.stack(
            [Ui.label("Skip the capture review", size: 16), UIView(), skipReviewSwitch],
            axis: .horizontal, spacing: 12, alignment: .center
        )

        let liveness = SliderRow(title: "Liveness threshold", range: 0...1, step: 0.01, format: { Ui.score($0) }) {
            AppSettings.livenessThreshold = $0
        }
        livenessRow = liveness

        let yaw = SliderRow(title: "Yaw", range: 0...90, step: 1, format: { "\(Int($0))°" }) { AppSettings.yaw = $0 }
        let roll = SliderRow(title: "Roll", range: 0...90, step: 1, format: { "\(Int($0))°" }) { AppSettings.roll = $0 }
        let pitch = SliderRow(title: "Pitch", range: 0...90, step: 1, format: { "\(Int($0))°" }) { AppSettings.pitch = $0 }
        yawRow = yaw
        rollRow = roll
        pitchRow = pitch

        let about = Ui.stack([licenseLabel, sdkLabel, appLabel], spacing: 4)
        let aboutCard = Ui.card()
        about.translatesAutoresizingMaskIntoConstraints = false
        aboutCard.addSubview(about)
        NSLayoutConstraint.activate([
            about.topAnchor.constraint(equalTo: aboutCard.topAnchor, constant: 12),
            about.leadingAnchor.constraint(equalTo: aboutCard.leadingAnchor, constant: 12),
            about.trailingAnchor.constraint(equalTo: aboutCard.trailingAnchor, constant: -12),
            about.bottomAnchor.constraint(equalTo: aboutCard.bottomAnchor, constant: -12),
        ])

        // The company mark closes the screen, now that About is no longer a tab.
        let logo = UIImageView(image: UIImage(named: "FacePluginLogo"))
        logo.contentMode = .scaleAspectFit
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.heightAnchor.constraint(equalToConstant: 44).isActive = true

        [threshold, livenessToggle, skipReviewToggle, liveness, yaw, roll, pitch, aboutCard, logo]
            .forEach { content.addArrangedSubview($0) }
        content.setCustomSpacing(28, after: aboutCard)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32),
        ])
    }

    private func bind() {
        thresholdRow?.value = AppSettings.threshold
        livenessRow?.value = AppSettings.livenessThreshold
        yawRow?.value = AppSettings.yaw
        rollRow?.value = AppSettings.roll
        pitchRow?.value = AppSettings.pitch
        livenessSwitch.isOn = AppSettings.livenessOn
        skipReviewSwitch.isOn = AppSettings.skipReview

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        sdkLabel.text = "SDK: FacePlugin Face Recognition"
        appLabel.text = "App version: \(version)"
    }

    private func refreshLicense() {
        FaceEngine.shared.worker.async { [weak self] in
            let status = FaceEngine.shared.licenseStatus()
            DispatchQueue.main.async {
                var parts = [status.label.isEmpty ? (status.licensed ? "Licensed" : "Not licensed") : status.label]
                if status.licensed, !status.levelName.isEmpty, status.levelName.caseInsensitiveCompare("None") != .orderedSame {
                    parts.append(status.levelName)
                }
                if status.recognition { parts.append("Recognition") }
                if status.liveness { parts.append("Liveness") }
                self?.licenseLabel.text = "License: \(parts.joined(separator: " · "))"
            }
        }
    }

    @objc private func skipReviewChanged() {
        AppSettings.skipReview = skipReviewSwitch.isOn
    }

    @objc private func livenessChanged() {
        AppSettings.livenessOn = livenessSwitch.isOn
    }

    @objc private func resetTapped() {
        AppSettings.reset()
        bind()
    }
}

/// A labelled slider with its live value, the counterpart of Android's settings rows.
final class SliderRow: UIView {

    private let slider = UISlider()
    private let valueLabel = Ui.label(size: 16, weight: .medium)
    private let format: (Float) -> String
    private let step: Float
    private let onChange: (Float) -> Void

    var value: Float {
        get { slider.value }
        set {
            slider.value = newValue
            valueLabel.text = format(newValue)
        }
    }

    init(
        title: String,
        range: ClosedRange<Float>,
        step: Float,
        format: @escaping (Float) -> String,
        onChange: @escaping (Float) -> Void
    ) {
        self.format = format
        self.step = step
        self.onChange = onChange
        super.init(frame: .zero)

        slider.minimumValue = range.lowerBound
        slider.maximumValue = range.upperBound
        slider.addTarget(self, action: #selector(changed), for: .valueChanged)

        let header = Ui.stack([Ui.label(title, size: 16), UIView(), valueLabel], axis: .horizontal, spacing: 8, alignment: .center)
        let stack = Ui.stack([header, slider], spacing: 4)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    @objc private func changed() {
        let snapped = (slider.value / step).rounded() * step
        slider.value = snapped
        valueLabel.text = format(snapped)
        onChange(snapped)
    }
}
