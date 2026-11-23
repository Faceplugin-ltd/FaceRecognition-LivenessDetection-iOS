import FaceRecognitionKit
import UIKit

/// One match row: rank, round thumbnail, name, ID tag, similarity bar and score.
final class MatchRowView: UIView {

    private let onTap: (Candidate) -> Void
    private let candidate: Candidate

    init(rank: Int, candidate: Candidate, record: FaceRecord?, onTap: @escaping (Candidate) -> Void) {
        self.candidate = candidate
        self.onTap = onTap
        super.init(frame: .zero)

        let rankLabel = Ui.label("\(rank)", size: 15, weight: .semibold, color: .secondaryLabel)
        rankLabel.widthAnchor.constraint(equalToConstant: 20).isActive = true

        let thumb = UIImageView()
        thumb.contentMode = .scaleAspectFill
        thumb.clipsToBounds = true
        thumb.layer.cornerRadius = 22
        thumb.backgroundColor = .tertiarySystemFill
        thumb.widthAnchor.constraint(equalToConstant: 44).isActive = true
        thumb.heightAnchor.constraint(equalToConstant: 44).isActive = true
        Ui.loadImage(record?.cropPath, into: thumb, maxSide: 132)

        let name = Ui.label(record?.name ?? candidate.name, size: 16)
        let idTag = Ui.idTagLabel(candidate.id)
        let titleRow = Ui.stack([name, idTag, UIView()], axis: .horizontal, spacing: 8, alignment: .center)

        let bar = Ui.bar(candidate.similarity, color: .systemBlue)
        let column = Ui.stack([titleRow, bar], spacing: 6)

        let score = Ui.label(Ui.score(candidate.similarity), size: 15, weight: .medium)
        score.setContentHuggingPriority(.required, for: .horizontal)

        let row = Ui.stack([rankLabel, thumb, column, score], axis: .horizontal, spacing: 12, alignment: .center)
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    required init?(coder: NSCoder) { nil }

    @objc private func tapped() { onTap(candidate) }
}
