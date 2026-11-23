import UIKit

/// A titled card of label / value rows, with an optional badge pill and a 0…1 bar.
/// The counterpart of Android's `Sections`.
final class SectionCardView: CardView {

    enum Badge {
        case pass, fail, warn, info

        var color: UIColor {
            switch self {
            case .pass: return Ui.statusMatch
            case .fail: return Ui.danger
            case .warn: return Ui.statusNoMatch
            case .info: return Ui.statusInfo
            }
        }
    }

    private let rows = Ui.stack([], spacing: 0)

    init(title: String) {
        super.init()
        let titleLabel = Ui.label(title.uppercased(), size: 13, weight: .semibold, color: tintColor)
        titleLabel.textColor = .systemIndigo

        let content = Ui.stack([titleLabel, rows], spacing: 4)
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { nil }

    /// Adds one row. `score` in 0…1 draws a bar under it.
    @discardableResult
    func addRow(
        _ label: String,
        _ value: String,
        badge: (String, Badge)? = nil,
        score: Float? = nil,
        onTap: (() -> Void)? = nil
    ) -> UIView {
        let name = Ui.label(label, size: 15, color: .secondaryLabel)
        name.widthAnchor.constraint(equalToConstant: 112).isActive = true
        name.setContentHuggingPriority(.required, for: .horizontal)

        let valueLabel = Ui.label(value, size: 16)
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let top = Ui.stack([name, valueLabel], axis: .horizontal, spacing: 8, alignment: .top)

        if let badge {
            let pill = Ui.pill(badge.0, color: badge.1.color)
            pill.font = .systemFont(ofSize: 11, weight: .bold)
            pill.insets = UIEdgeInsets(top: 2, left: 10, bottom: 2, right: 10)
            top.addArrangedSubview(pill)
        }

        var column: [UIView] = [top]
        if let score, !score.isNaN {
            let bar = Ui.bar(score, color: badge?.1.color ?? .systemBlue)
            let spacer = UIView()
            spacer.widthAnchor.constraint(equalToConstant: 112).isActive = true
            column.append(Ui.stack([spacer, bar], axis: .horizontal, spacing: 0, alignment: .center))
        }

        let row = Ui.stack(column, spacing: 6)
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 8, left: 0, bottom: 4, right: 0)

        if let onTap {
            row.isUserInteractionEnabled = true
            let recognizer = TapRecognizer(action: onTap)
            row.addGestureRecognizer(recognizer.gesture)
            objc_setAssociatedObject(row, &SectionCardView.tapKey, recognizer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }

        rows.addArrangedSubview(row)
        return row
    }

    private static var tapKey: UInt8 = 0
}

/// Keeps a tap closure alive alongside the view it belongs to.
final class TapRecognizer: NSObject {
    private let action: () -> Void
    lazy var gesture: UITapGestureRecognizer = {
        UITapGestureRecognizer(target: self, action: #selector(fire))
    }()

    init(action: @escaping () -> Void) {
        self.action = action
        super.init()
    }

    @objc private func fire() { action() }
}
