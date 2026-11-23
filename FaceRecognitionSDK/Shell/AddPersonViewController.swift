import FaceRecognitionKit
import UIKit

/// Enroll with camera: the capture guide, then a review of the captured still.
/// The review lists each check with its value and the Settings limit; name, note, Retake and
/// Enroll appear right away. Enroll is blocked while a required check fails: one face, liveness
/// (when on in Settings) and head pose. Low quality only warns.
final class AddPersonViewController: FaceCaptureViewController, UITextFieldDelegate {

    private let panel = UIView()
    /// The captured still. It lives in the panel rather than behind it, because the review is
    /// a sheet and the camera preview is no longer visible underneath.
    private let faceImage = UIImageView()
    private var faceHeight: NSLayoutConstraint?
    private let verdictPill = Ui.pill("Checking the face", color: Ui.statusInfo)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let checks = Ui.stack([], spacing: 12)
    private let reasonLabel = Ui.label(size: 15)
    private let nameField = UITextField()
    private let noteField = UITextField()
    private let errorLabel = Ui.label(size: 14, color: Ui.danger)
    private let statusHolder = UIView()
    private let retakeButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)

    private var analyzed = false
    private var saving = false
    /// Why the capture cannot be enrolled; nil when it can.
    private var blockReason: String?

    // MARK: - Capture hooks

    override func resultPanelView() -> UIView {
        buildPanel()
        return panel
    }

    override func limits() -> FaceLimits { AppSettings.limits }

    /// The still at rest, and while typing: the fields and buttons come first on a short screen.
    private static let faceHeightFull: CGFloat = 220
    private static let faceHeightTyping: CGFloat = 96

    override func onReviewKeyboardChanged(_ visible: Bool) {
        // keyboardWillChangeFrame fires repeatedly; only a real change is worth animating.
        let wanted = visible ? Self.faceHeightTyping : Self.faceHeightFull
        guard faceHeight?.constant != wanted else { return }
        faceHeight?.constant = wanted
        UIView.animate(withDuration: 0.15) { self.panel.layoutIfNeeded() }
    }

    override func onCaptureAnalyzing() {
        analyzed = false
        blockReason = nil
        faceImage.image = capturedPhoto()
        spinner.startAnimating()
        verdictPill.text = "Checking the face"
        verdictPill.backgroundColor = Ui.statusInfo
        checks.arrangedSubviews.forEach { $0.removeFromSuperview() }
        reasonLabel.isHidden = true
        errorLabel.isHidden = true
        statusHolder.isHidden = true
        refreshSave()
    }

    override func onCaptureAnalyzed(_ face: FaceBox?, faceCount: Int) {
        analyzed = true
        spinner.stopAnimating()
        checks.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let limits = limits()
        let card = SectionCardView(title: "Checks")
        var reasons: [String] = []

        // Exactly one face in the still.
        let oneFace = faceCount == 1 && face != nil
        card.addRow("Faces", "\(faceCount)", badge: (oneFace ? "Pass" : "Fail", oneFace ? .pass : .fail))
        if !oneFace { reasons.append("Use a capture with exactly one face.") }

        if let face {
            // Liveness: the Settings threshold decides. When Liveness is off it is shown, not enforced.
            if !face.livenessLabel.isEmpty || face.liveness > 0 {
                let live = limits.isLive(face.liveness)
                let value = "\(live ? "Live" : "Spoof") · \(Ui.score(face.liveness))  (≥ \(Ui.score(limits.liveness)))"
                if AppSettings.livenessOn {
                    card.addRow("Liveness check", value, badge: (live ? "Pass" : "Fail", live ? .pass : .fail), score: face.liveness)
                    if !live {
                        reasons.append("Liveness check failed. Use a live face, not a photo or screen.")
                    }
                } else {
                    card.addRow("Liveness check", "\(value) · check off in Settings", score: face.liveness)
                }
            }

            // Quality warns only.
            let q = face.faceQuality
            let badge: (String, SectionCardView.Badge) = q < 0.5 ? ("Low", .fail) : (q < 0.75 ? ("Medium", .warn) : ("High", .pass))
            card.addRow("Face quality", Ui.score(q), badge: badge, score: q)

            // Head pose against the Settings limits.
            let poseOk = limits.poseOk(yaw: face.yaw, roll: face.roll, pitch: face.pitch)
            let widest = max(limits.yaw, max(limits.roll, limits.pitch))
            card.addRow(
                "Head pose",
                String(format: "yaw %.1f° · roll %.1f° · pitch %.1f°  (±%.1f°)", face.yaw, face.roll, face.pitch, widest),
                badge: (poseOk ? "Pass" : "Over", poseOk ? .pass : .fail)
            )
            if !poseOk { reasons.append("Face the camera straight on.") }

            if reasons.isEmpty && q < 0.5 {
                showReason("Face quality is low. Enrolling works, but matches may be weaker.", colour: Ui.statusNoMatch)
            }
        }

        checks.addArrangedSubview(card)
        blockReason = reasons.isEmpty ? nil : reasons.joined(separator: "\n")
        if let blockReason { showReason(blockReason, colour: Ui.danger) }

        verdictPill.text = blockReason == nil ? "Ready to enroll" : "Retake needed"
        verdictPill.backgroundColor = blockReason == nil ? Ui.statusMatch : Ui.danger
        refreshSave()
        if blockReason == nil, AppSettings.skipReview {
            // Nothing to report, and the tester asked not to be stopped: enroll straight away.
            enrollTapped()
            return
        }
    }

    override func retakeCapture() {
        analyzed = false
        blockReason = nil
        super.retakeCapture()
    }

    // MARK: - Panel

    private func buildPanel() {
        guard panel.subviews.isEmpty else { return }

        let header = Ui.stack(
            [Ui.label("Captured face", size: 22, weight: .semibold), spinner, UIView(), verdictPill],
            axis: .horizontal, spacing: 8, alignment: .center
        )
        spinner.hidesWhenStopped = true

        reasonLabel.isHidden = true
        errorLabel.isHidden = true
        statusHolder.isHidden = true

        [nameField, noteField].forEach {
            $0.borderStyle = .roundedRect
            $0.font = .systemFont(ofSize: 16)
            $0.heightAnchor.constraint(equalToConstant: 44).isActive = true
        }
        nameField.placeholder = "Name (optional) — saved as Person N if left blank"
        nameField.autocapitalizationType = .words
        nameField.returnKeyType = .next
        nameField.delegate = self
        nameField.addTarget(self, action: #selector(nameChanged), for: .editingChanged)
        noteField.placeholder = "Note (optional)"
        noteField.returnKeyType = .done
        noteField.delegate = self

        retakeButton.setTitle("Retake", for: .normal)
        retakeButton.layer.borderWidth = 1
        retakeButton.layer.borderColor = UIColor.separator.cgColor
        retakeButton.layer.cornerRadius = 10
        retakeButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        retakeButton.addTarget(self, action: #selector(retakeTapped), for: .touchUpInside)

        saveButton.setTitle("Enroll", for: .normal)
        saveButton.backgroundColor = .systemIndigo
        saveButton.setTitleColor(.white, for: .normal)
        saveButton.setTitleColor(UIColor.white.withAlphaComponent(0.5), for: .disabled)
        saveButton.layer.cornerRadius = 10
        saveButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        saveButton.addTarget(self, action: #selector(enrollTapped), for: .touchUpInside)

        let buttons = Ui.stack([retakeButton, saveButton], axis: .horizontal, spacing: 12)
        saveButton.widthAnchor.constraint(equalTo: retakeButton.widthAnchor, multiplier: 2).isActive = true

        faceImage.contentMode = .scaleAspectFill
        faceImage.clipsToBounds = true
        faceImage.layer.cornerRadius = 16
        faceImage.backgroundColor = .secondarySystemBackground
        faceHeight = faceImage.heightAnchor.constraint(equalToConstant: Self.faceHeightFull)
        faceHeight?.isActive = true

        let stack = Ui.stack(
            [faceImage, header, checks, reasonLabel, nameField, noteField, errorLabel, statusHolder, buttons],
            spacing: 12
        )
        panel.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -24),
        ])
        refreshSave()
    }

    private func showReason(_ text: String, colour: UIColor) {
        reasonLabel.isHidden = false
        reasonLabel.text = text
        reasonLabel.textColor = colour
    }

    /// Enroll turns on only after the checks ran, nothing blocks, and a name is entered.
    /// Enroll turns on once the checks have run and nothing blocks. The name is optional: a
    /// blank one is saved as Person N, so testing is capture then Enroll with no typing.
    private func refreshSave() {
        saveButton.isEnabled = !saving && analyzed && blockReason == nil && hasCapture()
        saveButton.alpha = saveButton.isEnabled ? 1 : 0.5
        saveButton.setTitle(saving ? "Saving" : "Enroll", for: .normal)
    }

    @objc private func nameChanged() { refreshSave() }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === nameField {
            noteField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
        }
        return true
    }

    @objc private func retakeTapped() {
        guard !saving else { return }
        view.endEditing(true)
        retakeCapture()
    }

    @objc private func enrollTapped() {
        guard !saving, blockReason == nil, let photo = capturedPhoto() else { return }
        view.endEditing(true)
        let name = (nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let note = noteField.text ?? ""

        errorLabel.isHidden = true
        saving = true
        refreshSave()

        FaceEngine.shared.worker.async { [weak self] in
            let outcome = FaceGallery.shared.enroll(name: name, note: note, photo: photo, limits: AppSettings.limits)
            DispatchQueue.main.async {
                guard let self else { return }
                self.saving = false
                self.refreshSave()
                switch outcome {
                case let .enrolled(record, report, duplicates):
                    self.statusHolder.isHidden = true
                    // Every person over the threshold is named, not just the closest.
                    let warning: String? = duplicates.isEmpty ? nil :
                        "Looks like " + duplicates
                            .map { "\($0.name) (ID \($0.id), similarity \(Ui.score($0.similarity)))" }
                            .joined(separator: ", ")
                        + ". All are kept. Delete one in People if it is the same person."
                    // The review closes first, so the status sheet replaces it rather than
                    // presenting on top of a sheet that is already up.
                    self.dismissResultPanel()
                    StatusCardView.present(
                        on: self,
                        title: "\(record.name) enrolled as ID \(record.id)",
                        reason: warning,
                        report: report
                    ) { [weak self] in
                        self?.navigationController?.popViewController(animated: true)
                    }
                case let .rejected(reason, report):
                    self.errorLabel.isHidden = false
                    self.errorLabel.text = reason
                    self.statusHolder.subviews.forEach { $0.removeFromSuperview() }
                    guard let report else {
                        self.statusHolder.isHidden = true
                        return
                    }
                    self.statusHolder.isHidden = false
                    let card = StatusCardView(report: report, title: "Enrollment status")
                    card.translatesAutoresizingMaskIntoConstraints = false
                    self.statusHolder.addSubview(card)
                    NSLayoutConstraint.activate([
                        card.topAnchor.constraint(equalTo: self.statusHolder.topAnchor),
                        card.leadingAnchor.constraint(equalTo: self.statusHolder.leadingAnchor),
                        card.trailingAnchor.constraint(equalTo: self.statusHolder.trailingAnchor),
                        card.bottomAnchor.constraint(equalTo: self.statusHolder.bottomAnchor),
                    ])
                }
            }
        }
    }
}
