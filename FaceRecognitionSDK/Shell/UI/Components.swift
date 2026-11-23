import UIKit

/// A label with padding. Set `pill` so it stays a capsule at any text size, instead of a fixed
/// corner radius that breaks when Dynamic Type changes the height.
final class PaddedLabel: UILabel {

    var insets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8) {
        didSet { invalidateIntrinsicContentSize() }
    }

    /// Rounds to a capsule on every layout pass.
    var pill = false {
        didSet { setNeedsLayout() }
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + insets.left + insets.right,
            height: size.height + insets.top + insets.bottom
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if pill { layer.cornerRadius = bounds.height / 2 }
    }
}

/// An outlined card. `CGColor` does not follow light and dark mode on its own, so the border is
/// resolved again whenever the appearance changes.
class CardView: UIView {

    init(background: UIColor = .secondarySystemGroupedBackground) {
        super.init(frame: .zero)
        backgroundColor = background
        layer.cornerRadius = 16
        layer.borderWidth = 1
        applyBorderColour()
    }

    required init?(coder: NSCoder) { nil }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previous) {
            applyBorderColour()
        }
    }

    private func applyBorderColour() {
        layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
    }
}

/// A round status dot that sizes itself, so it never fights a fixed width constraint.
final class StatusDotView: UIView {

    private let label = UILabel()

    init(text: String, colour: UIColor) {
        super.init(frame: .zero)
        backgroundColor = colour
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(equalToConstant: 22),
            heightAnchor.constraint(equalToConstant: 22),
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}

/// A metric tile: a large value over a small caption. Three of these sit in an equal-width row,
/// the counterpart of Android's `view_metric` with `layout_weight="1"`.
final class MetricTileView: CardView {

    private let valueLabel = Ui.label(size: 22, weight: .semibold)
    private let captionLabel = Ui.label(size: 12, color: .secondaryLabel)

    var value: String {
        get { valueLabel.text ?? "" }
        set { valueLabel.text = newValue }
    }

    init(caption: String, value: String = "") {
        super.init()
        valueLabel.text = value
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.6
        valueLabel.numberOfLines = 1
        captionLabel.text = caption
        captionLabel.numberOfLines = 1
        captionLabel.adjustsFontSizeToFitWidth = true
        captionLabel.minimumScaleFactor = 0.7

        let stack = Ui.stack([valueLabel, captionLabel], spacing: 2)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { nil }
}

extension UIStackView {
    /// Three metric tiles share the width evenly, as the Android row does.
    static func metricsRow() -> UIStackView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }
}
