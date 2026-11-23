import FaceRecognitionKit
import UIKit

/// Every face in the photo with every value the engine returns: liveness, quality, detection
/// score, pose, eyes, expression, age, gender, landmarks, box and the closest enrolled person.
/// Each gated value is checked against the limits in Settings.
final class AttributeResultViewController: UIViewController {

    /// Smile confidence at or above which the face counts as smiling.
    /// Eyes read as open at or above this score. The engine's own label uses a fixed 0.5,
    /// which calls a half-open eye closed.
    private static let eyeOpenThreshold: Float = 0.25
    private static let smileThreshold: Float = 0.5
    /// Inner-lip gap over mouth width at or above which the mouth reads as open or slightly open.
    private static let mouthOpen: Float = 0.25
    private static let mouthSlightlyOpen: Float = 0.10

    private let result: AttributeResult
    private var selected = 0

    private let content = Ui.stack([], spacing: 12)
    private let photoView = UIImageView()
    private let summaryPill = Ui.pill()
    private let summaryLabel = Ui.label(size: 15, color: .secondaryLabel)
    private let metricsRow = UIStackView.metricsRow()
    private let chipsScroll = UIScrollView()
    private let chipsRow = Ui.stack([], axis: .horizontal, spacing: 8)
    private let faceHeader = Ui.stack([], axis: .horizontal, spacing: 12, alignment: .center)
    private let faceCrop = UIImageView()
    private let faceTitle = Ui.label(size: 22, weight: .semibold)
    private let faceSubtitle = Ui.label(size: 15, color: .secondaryLabel)
    private let verdictPill = Ui.pill()
    private let sections = Ui.stack([], spacing: 12)
    private let statusHolder = UIView()

    init(result: AttributeResult) {
        self.result = result
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Attribute Result"
        view.backgroundColor = .systemBackground
        buildLayout()
        bindSummary()
        bindChips()

        let card = StatusCardView(report: result.report)
        card.translatesAutoresizingMaskIntoConstraints = false
        statusHolder.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: statusHolder.topAnchor),
            card.leadingAnchor.constraint(equalTo: statusHolder.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: statusHolder.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: statusHolder.bottomAnchor),
        ])
        render()
    }

    private func buildLayout() {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(content)

        photoView.contentMode = .scaleAspectFit
        photoView.backgroundColor = .secondarySystemFill
        photoView.layer.cornerRadius = 16
        photoView.clipsToBounds = true
        // A fixed height keeps the card the same size whatever the photo's shape, as the
        // Android card does. Without it a tall photo made the whole page jump about.
        photoView.heightAnchor.constraint(equalToConstant: 280).isActive = true
        photoView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let summaryRow = Ui.stack([summaryPill, summaryLabel], axis: .horizontal, spacing: 12, alignment: .center)

        chipsScroll.translatesAutoresizingMaskIntoConstraints = false
        chipsScroll.showsHorizontalScrollIndicator = false
        chipsScroll.addSubview(chipsRow)
        chipsScroll.isHidden = true

        faceCrop.contentMode = .scaleAspectFill
        faceCrop.clipsToBounds = true
        faceCrop.layer.cornerRadius = 16
        faceCrop.backgroundColor = .tertiarySystemFill
        faceCrop.widthAnchor.constraint(equalToConstant: 72).isActive = true
        faceCrop.heightAnchor.constraint(equalToConstant: 72).isActive = true
        let titles = Ui.stack([faceTitle, faceSubtitle], spacing: 2)
        [faceCrop, titles, verdictPill].forEach { faceHeader.addArrangedSubview($0) }

        [photoView, summaryRow, metricsRow, chipsScroll, faceHeader, sections, statusHolder]
            .forEach { content.addArrangedSubview($0) }

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32),

            chipsRow.topAnchor.constraint(equalTo: chipsScroll.contentLayoutGuide.topAnchor),
            chipsRow.leadingAnchor.constraint(equalTo: chipsScroll.contentLayoutGuide.leadingAnchor),
            chipsRow.trailingAnchor.constraint(equalTo: chipsScroll.contentLayoutGuide.trailingAnchor),
            chipsRow.bottomAnchor.constraint(equalTo: chipsScroll.contentLayoutGuide.bottomAnchor),
            chipsRow.heightAnchor.constraint(equalTo: chipsScroll.frameLayoutGuide.heightAnchor),
            chipsScroll.heightAnchor.constraint(equalToConstant: 34),
        ])
    }

    private func bindSummary() {
        let n = result.faces.count
        summaryPill.text = n == 0 ? "No face" : Ui.facesCount(n)
        summaryPill.backgroundColor = n == 0 ? Ui.danger : Ui.statusMatch
        if n == 0 {
            summaryLabel.text = "Use a clear photo with a face in it."
        } else if n > FaceGallery.maxAttributeFaces {
            summaryLabel.text = "Gallery search runs on the \(FaceGallery.maxAttributeFaces) largest faces."
        } else {
            summaryLabel.text = "Checks use the limits in Settings."
        }
        metric("Faces", "\(n)")
        let detect = result.report.steps.first { $0.name == "faceDetection" }?.ms ?? 0
        metric("Detect ms", Ui.ms(detect))
        metric("Total ms", Ui.ms(result.report.totalMs))
    }

    private func metric(_ caption: String, _ value: String) {
        metricsRow.addArrangedSubview(MetricTileView(caption: caption, value: value))
    }

    private func bindChips() {
        guard result.faces.count >= 2 else { return }
        chipsScroll.isHidden = false
        for face in result.faces {
            let chip = UIButton(type: .system)
            chip.setTitle("Face \(face.index + 1)", for: .normal)
            chip.tag = face.index
            chip.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
            chip.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
            chip.layer.cornerRadius = 16
            chip.layer.borderWidth = 1
            chip.layer.borderColor = UIColor.separator.cgColor
            chip.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            chipsRow.addArrangedSubview(chip)
        }
        updateChips()
    }

    @objc private func chipTapped(_ sender: UIButton) {
        guard sender.tag != selected else { return }
        selected = sender.tag
        updateChips()
        render()
    }

    private func updateChips() {
        for case let chip as UIButton in chipsRow.arrangedSubviews {
            let on = chip.tag == selected
            chip.backgroundColor = on ? .systemIndigo : .clear
            chip.setTitleColor(on ? .white : .label, for: .normal)
        }
    }

    // MARK: - Render

    private func render() {
        photoView.image = ImageUtils.upright(result.probe)
        sections.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard let face = result.faces.indices.contains(selected) ? result.faces[selected] : nil else {
            faceHeader.isHidden = true
            let card = SectionCardView(title: "Result")
            card.addRow("Status", "No face", badge: ("Failed", .fail))
            sections.addArrangedSubview(card)
            return
        }
        faceHeader.isHidden = false
        bindHeader(face)
        bindSections(face)
    }

    private func bindHeader(_ face: FaceAttributes) {
        let box = face.box
        faceCrop.image = ImageUtils.cropFace(result.probe, box: box.box) ?? result.probe
        faceTitle.text = "Face \(face.index + 1)"
        var parts: [String] = []
        if box.age > 0 { parts.append("Age \(box.age)") }
        if !genderText(box).isEmpty { parts.append(genderText(box)) }
        if !box.smile.isNaN { parts.append(emotionText(box)) }
        if hasLiveness(box) { parts.append(livenessWord(box)) }
        faceSubtitle.text = parts.isEmpty ? "Not computed" : parts.joined(separator: " · ")

        let failed = gates(box).filter { !$0 }.count
        verdictPill.text = failed == 0 ? "All checks pass" : (failed == 1 ? "1 check failed" : "\(failed) checks failed")
        verdictPill.backgroundColor = failed == 0 ? Ui.statusMatch : Ui.statusNoMatch
    }

    /// Pass or fail of each gated value the engine computed.
    private func gates(_ box: FaceBox) -> [Bool] {
        let limits = AppSettings.limits
        var out: [Bool] = []
        if hasLiveness(box) { out.append(limits.isLive(box.liveness)) }
        out.append(limits.poseOk(yaw: box.yaw, roll: box.roll, pitch: box.pitch))
        return out
    }

    private func bindSections(_ face: FaceAttributes) {
        let box = face.box
        let limits = AppSettings.limits

        let authenticity = SectionCardView(title: "Authenticity")
        if hasLiveness(box) {
            let live = limits.isLive(box.liveness)
            authenticity.addRow(
                "Liveness check",
                "\(livenessWord(box)) · \(Ui.score(box.liveness))  (≥ \(Ui.score(limits.liveness)))",
                badge: (live ? "Pass" : "Fail", live ? .pass : .fail),
                score: box.liveness
            )
        } else {
            authenticity.addRow("Liveness check", "Not computed")
        }
        sections.addArrangedSubview(authenticity)

        let person = SectionCardView(title: "Person")
        person.addRow("Age", box.age > 0 ? "\(box.age)" : "Not computed")
        person.addRow("Gender", genderText(box).isEmpty ? "Not computed" : genderText(box))
        sections.addArrangedSubview(person)

        let quality = SectionCardView(title: "Quality")
        let q = box.faceQuality
        let qualityBadge: (String, SectionCardView.Badge) = q < 0.5 ? ("Low", .fail) : (q < 0.75 ? ("Medium", .warn) : ("High", .pass))
        quality.addRow("Face quality", Ui.score(q), badge: qualityBadge, score: q)
        if !box.score.isNaN, box.score > 0 {
            quality.addRow("Detection score", Ui.score(box.score), score: box.score)
        }
        sections.addArrangedSubview(quality)

        let pose = SectionCardView(title: "Head pose")
        poseRow(pose, "Yaw", box.yaw, limits.yaw)
        poseRow(pose, "Roll", box.roll, limits.roll)
        poseRow(pose, "Pitch", box.pitch, limits.pitch)
        sections.addArrangedSubview(pose)

        // Eyes-open score from the engine, read against eyeOpenThreshold.
        let eyes = SectionCardView(title: "Eyes")
        let open = box.source.eyesOpen
        if open.isNaN {
            eyes.addRow("Eyes", "Not computed")
        } else {
            let isOpen = open >= AttributeResultViewController.eyeOpenThreshold
            let word = isOpen ? "Open" : "Closed"
            eyes.addRow(
                "Eyes",
                "\(word) · \(Ui.score(open))  (>= \(Ui.score(AttributeResultViewController.eyeOpenThreshold)))",
                badge: (word, isOpen ? .pass : .warn),
                score: open
            )
        }
        sections.addArrangedSubview(eyes)

        let expression = SectionCardView(title: "Expression")
        if box.smile.isNaN {
            expression.addRow("Emotion", "Not computed")
        } else {
            let smiling = box.smile >= AttributeResultViewController.smileThreshold
            expression.addRow(
                "Emotion",
                "\(emotionText(box)) · smile \(Ui.score(box.smile))",
                badge: (emotionText(box), smiling ? .pass : .info),
                score: box.smile
            )
        }
        if box.mouthOpened.isNaN {
            expression.addRow("Mouth openness", "Not computed")
        } else {
            let m = box.mouthOpened
            let word: (String, SectionCardView.Badge)
            if m >= AttributeResultViewController.mouthOpen {
                word = ("Open", .warn)
            } else if m >= AttributeResultViewController.mouthSlightlyOpen {
                word = ("Slightly open", .info)
            } else {
                word = ("Closed", .pass)
            }
            expression.addRow("Mouth openness", "\(word.0) · \(Ui.score(m))", badge: word, score: m)
        }
        sections.addArrangedSubview(expression)

        let gallery = SectionCardView(title: "Gallery")
        if result.gallerySize == 0 {
            gallery.addRow("Closest person", "Gallery is empty")
        } else if face.templateBytes == 0 {
            gallery.addRow("Closest person", "No template")
        } else if let closest = face.closest {
            let matched = closest.similarity >= result.threshold
            gallery.addRow(
                "Closest person",
                "\(closest.name) · \(Ui.idTag(closest.id))\n\(Ui.score(closest.similarity))  (≥ \(Ui.score(result.threshold)))",
                badge: (matched ? "Match" : "No match", matched ? .pass : .warn),
                score: closest.similarity
            ) { [weak self] in
                self?.present(
                    FaceDetailSheetViewController(id: closest.id, similarity: closest.similarity),
                    animated: true
                )
            }
        } else {
            gallery.addRow("Closest person", "Gallery is empty")
        }
        gallery.addRow("Template", face.templateBytes > 0 ? "\(face.templateBytes) bytes" : "No template")
        sections.addArrangedSubview(gallery)

        let geometry = SectionCardView(title: "Geometry")
        let r = box.box
        geometry.addRow("Box", "\(Int(r.minX)), \(Int(r.minY)) → \(Int(r.maxX)), \(Int(r.maxY))")
        geometry.addRow("Size", "\(Int(r.width)) × \(Int(r.height)) px")
        geometry.addRow("Landmarks", box.landmarkCount > 0 ? "\(box.landmarkCount) points" : "Not computed")
        sections.addArrangedSubview(geometry)

        // Anything else the engine reported, so nothing is hidden from the user.
        let named: Set<String> = [
            "Liveness2D", "liveness", "FaceQuality", "ExpressionLevel", "Age", "Gender",
            "Emotion", "Smile", "MouthOpened", "EyesLeft", "EyesRight", "Score", "score",
        ]
        let extra = box.attributes.filter { !named.contains($0.key) && !$0.value.value.isEmpty }
        if !extra.isEmpty {
            let more = SectionCardView(title: "More from engine")
            for key in extra.keys.sorted() {
                more.addRow(key, extra[key]?.value ?? "")
            }
            sections.addArrangedSubview(more)
        }
    }

    private func poseRow(_ card: SectionCardView, _ label: String, _ value: Float, _ limit: Float) {
        let ok = abs(value) <= limit
        card.addRow(
            label,
            String(format: "%.1f°  (±%.1f°)", value, limit),
            badge: (ok ? "Pass" : "Over", ok ? .pass : .fail)
        )
    }

    // MARK: - Values

    private func hasLiveness(_ box: FaceBox) -> Bool { !box.livenessLabel.isEmpty || box.liveness > 0 }

    private func livenessWord(_ box: FaceBox) -> String {
        AppSettings.limits.isLive(box.liveness) ? "Live" : "Spoof"
    }

    private func emotionText(_ box: FaceBox) -> String {
        box.smile >= AttributeResultViewController.smileThreshold ? "Smiling" : "Neutral"
    }

    private func genderText(_ box: FaceBox) -> String { box.genderLabel }
}
