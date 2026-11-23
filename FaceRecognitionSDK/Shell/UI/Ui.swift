import FaceRecognitionKit
import UIKit

/// Small shared formatting and styling, the counterpart of Android's `Ui`.
enum Ui {

    // MARK: - Colours

    static let statusMatch = UIColor(red: 0.18, green: 0.49, blue: 0.20, alpha: 1)    // #2E7D32
    static let statusNoMatch = UIColor(red: 0.70, green: 0.42, blue: 0.00, alpha: 1)  // #B26A00
    static let danger = UIColor(red: 0.70, green: 0.15, blue: 0.12, alpha: 1)         // #B3261E
    static let statusInfo = UIColor(red: 0.10, green: 0.46, blue: 0.82, alpha: 1)     // #1976D2
    static let cameraChip = UIColor(white: 0.11, alpha: 0.80)

    // MARK: - Text

    /// Ids are always shown as a pill tag "ID 12", never "#12".
    static func idTag(_ id: Int64) -> String { "ID \(id)" }

    static func score(_ value: Float) -> String { String(format: "%.2f", value) }

    static func ms(_ value: Double) -> String {
        value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    static func facesCount(_ n: Int) -> String { n == 1 ? "1 face" : "\(n) faces" }

    static func matchesCount(_ n: Int) -> String { n == 1 ? "1 match" : "\(n) matches" }

    static func enrolledDate(_ iso: String) -> String {
        guard let date = FaceGallery.parseIso(iso) else { return iso }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func enrolledDateTime(_ iso: String) -> String {
        guard let date = FaceGallery.parseIso(iso) else { return iso }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Views

    /// A rounded status pill, the counterpart of Android's `FaceIdentity.Pill`.
    static func pill(_ text: String = "", color: UIColor = statusMatch) -> PaddedLabel {
        let label = PaddedLabel()
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .bold)
        label.backgroundColor = color
        label.pill = true
        label.layer.masksToBounds = true
        label.insets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }

    /// The light "ID 12" tag.
    static func idTagLabel(_ id: Int64) -> PaddedLabel {
        let label = PaddedLabel()
        label.text = idTag(id)
        label.textColor = .label
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.backgroundColor = .secondarySystemFill
        label.pill = true
        label.layer.masksToBounds = true
        label.insets = UIEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }

    /// An outlined card, the counterpart of Android's `bg_card`.
    static func card() -> CardView { CardView() }

    static func stack(
        _ views: [UIView],
        axis: NSLayoutConstraint.Axis = .vertical,
        spacing: CGFloat = 8,
        alignment: UIStackView.Alignment = .fill
    ) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = axis
        stack.spacing = spacing
        stack.alignment = alignment
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    static func label(
        _ text: String = "",
        size: CGFloat = 16,
        weight: UIFont.Weight = .regular,
        color: UIColor = .label
    ) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    /// A thin 0…1 bar, the counterpart of Android's `LinearProgressIndicator`.
    static func bar(_ value: Float, color: UIColor) -> UIProgressView {
        let bar = UIProgressView(progressViewStyle: .default)
        bar.progress = min(max(value, 0), 1)
        bar.progressTintColor = color
        bar.trackTintColor = .tertiarySystemFill
        bar.layer.cornerRadius = 2
        bar.clipsToBounds = true
        bar.heightAnchor.constraint(equalToConstant: 4).isActive = true
        return bar
    }

    /// Loads a stored crop or original, down-sampled, off the main queue.
    static func loadImage(_ path: String?, into imageView: UIImageView, maxSide: CGFloat = 512, onMissing: (() -> Void)? = nil) {
        guard let path, !path.isEmpty else {
            imageView.image = UIImage(systemName: "person.crop.circle")
            onMissing?()
            return
        }
        let token = UUID()
        imageView.loadToken = token
        DispatchQueue.global(qos: .userInitiated).async {
            let image = ImageUtils.load(contentsOf: URL(fileURLWithPath: path), maxSide: maxSide)
            DispatchQueue.main.async {
                guard imageView.loadToken == token else { return }
                if let image {
                    imageView.image = image
                } else {
                    imageView.image = UIImage(systemName: "person.crop.circle")
                    onMissing?()
                }
            }
        }
    }
}

private var loadTokenKey: UInt8 = 0

extension UIImageView {
    /// Guards against a recycled cell showing the previous row's photo.
    var loadToken: UUID? {
        get { objc_getAssociatedObject(self, &loadTokenKey) as? UUID }
        set { objc_setAssociatedObject(self, &loadTokenKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}
