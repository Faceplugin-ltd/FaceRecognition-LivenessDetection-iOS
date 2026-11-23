import FaceRecognitionKit
import UIKit

/// The person sheet, opened from a result, the matches list or the People list.
final class FaceDetailSheetViewController: UIViewController {

    private let id: Int64
    private let similarity: Float
    private var record: FaceRecord?

    private let content = Ui.stack([], spacing: 16)
    private let titleLabel = Ui.label(size: 22, weight: .semibold)
    private let idTag = Ui.idTagLabel(0)
    private let cropView = UIImageView()
    private let originalView = UIImageView()
    private let missingLabel = Ui.label("Original photo missing", size: 13, color: .secondaryLabel)
    private let similarityRow = Ui.stack([], axis: .horizontal, spacing: 12, alignment: .center)
    private let noteLabel = Ui.label(size: 16)
    private let enrolledLabel = Ui.label(size: 16)
    private let statusHolder = UIView()

    /// `similarity` below zero hides the Similarity row, as in the People list.
    init(id: Int64, similarity: Float = -1) {
        self.id = id
        self.similarity = similarity
        super.init(nibName: nil, bundle: nil)
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        buildLayout()
        load()
    }

    private func buildLayout() {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(content)

        let header = Ui.stack([titleLabel, idTag, UIView()], axis: .horizontal, spacing: 8, alignment: .center)

        [cropView, originalView].forEach {
            $0.contentMode = .scaleAspectFill
            $0.clipsToBounds = true
            $0.layer.cornerRadius = 16
            $0.backgroundColor = .tertiarySystemFill
            $0.heightAnchor.constraint(equalTo: $0.widthAnchor).isActive = true
        }
        let photos = Ui.stack([cropView, originalView], axis: .horizontal, spacing: 12)
        cropView.widthAnchor.constraint(equalTo: originalView.widthAnchor).isActive = true
        missingLabel.isHidden = true

        if similarity >= 0 {
            similarityRow.addArrangedSubview(Ui.label("Similarity", size: 15, color: .secondaryLabel))
            similarityRow.addArrangedSubview(Ui.bar(similarity, color: .systemBlue))
            similarityRow.addArrangedSubview(Ui.label(Ui.score(similarity), size: 16, weight: .medium))
        } else {
            similarityRow.isHidden = true
        }

        let delete = UIButton(type: .system)
        delete.setTitle("Delete", for: .normal)
        delete.setTitleColor(Ui.danger, for: .normal)
        delete.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        let edit = UIButton(type: .system)
        edit.setTitle("Edit", for: .normal)
        edit.addTarget(self, action: #selector(editTapped), for: .touchUpInside)
        let buttons = Ui.stack([delete, edit], axis: .horizontal, spacing: 12)

        [header, photos, missingLabel, similarityRow,
         labelled("Note", noteLabel), labelled("Enrolled", enrolledLabel),
         statusHolder, buttons].forEach { content.addArrangedSubview($0) }

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40),
        ])
    }

    private func labelled(_ title: String, _ value: UILabel) -> UIView {
        let name = Ui.label(title, size: 15, color: .secondaryLabel)
        name.widthAnchor.constraint(equalToConstant: 96).isActive = true
        return Ui.stack([name, value], axis: .horizontal, spacing: 8, alignment: .top)
    }

    private func load() {
        FaceEngine.shared.worker.async { [weak self] in
            guard let self else { return }
            let found = FaceGallery.shared.get(self.id)
            DispatchQueue.main.async {
                guard let found else {
                    self.dismiss(animated: true)
                    return
                }
                self.record = found
                self.bind(found)
            }
        }
    }

    private func bind(_ record: FaceRecord) {
        titleLabel.text = record.name
        idTag.text = Ui.idTag(record.id)
        noteLabel.text = record.note.isEmpty ? "No note" : record.note
        enrolledLabel.text = Ui.enrolledDateTime(record.createdAt)
        Ui.loadImage(record.cropPath, into: cropView)
        Ui.loadImage(record.originalPath, into: originalView) { [weak self] in
            self?.missingLabel.isHidden = false
        }

        statusHolder.subviews.forEach { $0.removeFromSuperview() }
        let view: UIView
        if let report = CallReport.fromJson(record.enrollReport) {
            view = StatusCardView(report: report, title: "Enrollment status")
        } else {
            view = Ui.label("Enrolled before status tracking was added.", size: 13, color: .secondaryLabel)
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        statusHolder.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: statusHolder.topAnchor),
            view.leadingAnchor.constraint(equalTo: statusHolder.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: statusHolder.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: statusHolder.bottomAnchor),
        ])
    }

    @objc private func deleteTapped() {
        guard let record else { return }
        let alert = UIAlertController(
            title: nil,
            message: "Delete \(record.name) and their photos? This can't be undone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            FaceEngine.shared.worker.async { FaceGallery.shared.delete(record.id) }
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }

    @objc private func editTapped() {
        guard let record else { return }
        let alert = UIAlertController(title: "Edit person", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = record.name; $0.placeholder = "Name" }
        alert.addTextField { $0.text = record.note; $0.placeholder = "Note (optional)" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self else { return }
            let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { return }
            let note = alert.textFields?.last?.text ?? ""
            FaceEngine.shared.worker.async {
                FaceGallery.shared.update(record.id, name: name, note: note)
                DispatchQueue.main.async { self.load() }
            }
        })
        present(alert, animated: true)
    }
}
