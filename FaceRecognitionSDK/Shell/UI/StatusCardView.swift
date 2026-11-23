import FaceRecognitionKit
import UIKit

/// One status UI for every action — identify, enrol, import, attribute.
/// Outcome pill, total time, when it finished, then one row per SDK call with pass or fail,
/// its time and its share of the total.
final class StatusCardView: CardView {

    private let titleLabel = Ui.label(size: 17, weight: .semibold)
    private let pill = Ui.pill()
    private let summaryLabel = Ui.label(size: 13, color: .secondaryLabel)
    private let stepsStack = Ui.stack([], spacing: 0)
    private let detailLabel = Ui.label(size: 15)
    private let detailBox = Ui.card()

    init(report: CallReport, title: String? = nil, showDetail: Bool = true) {
        super.init()
        build()
        bind(report: report, title: title, showDetail: showDetail)
    }

    required init?(coder: NSCoder) { nil }

    private func build() {
        detailBox.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailBox.addSubview(detailLabel)
        NSLayoutConstraint.activate([
            detailLabel.topAnchor.constraint(equalTo: detailBox.topAnchor, constant: 10),
            detailLabel.leadingAnchor.constraint(equalTo: detailBox.leadingAnchor, constant: 10),
            detailLabel.trailingAnchor.constraint(equalTo: detailBox.trailingAnchor, constant: -10),
            detailLabel.bottomAnchor.constraint(equalTo: detailBox.bottomAnchor, constant: -10),
        ])

        let header = Ui.stack([titleLabel, pill], axis: .horizontal, spacing: 8, alignment: .center)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let content = Ui.stack([header, summaryLabel, stepsStack, detailBox], spacing: 8)
        content.setCustomSpacing(4, after: header)
        content.setCustomSpacing(12, after: stepsStack)
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }

    private func bind(report: CallReport, title: String?, showDetail: Bool) {
        titleLabel.text = title ?? "\(StatusCardView.functionName(report.function)) status"
        pill.text = report.success ? "Success" : "Failed"
        pill.backgroundColor = report.success ? Ui.statusMatch : Ui.danger

        let ok = report.steps.filter(\.ok).count
        var parts = ["Total \(Ui.ms(report.totalMs)) ms", "\(ok) of \(report.steps.count) calls OK"]
        if report.finishedAt > 0 {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .medium
            parts.append(formatter.string(from: Date(timeIntervalSince1970: report.finishedAt / 1000)))
        }
        summaryLabel.text = parts.joined(separator: "  ·  ")

        let total = report.totalMs > 0 ? report.totalMs : 1
        if report.steps.isEmpty {
            stepsStack.addArrangedSubview(Ui.label("No SDK call ran.", size: 15, color: .secondaryLabel))
        }
        for step in report.steps {
            stepsStack.addArrangedSubview(StatusCardView.stepRow(step, total: total))
        }

        if showDetail, !report.detail.isEmpty {
            detailLabel.text = report.detail
        } else {
            detailBox.isHidden = true
        }
    }

    private static func stepRow(_ step: CallStep, total: Double) -> UIView {
        let dot = StatusDotView(text: step.ok ? "✓" : "✕", colour: step.ok ? Ui.statusMatch : Ui.danger)

        let name = Ui.label(stepName(step.name), size: 16)
        let time = Ui.label("\(Ui.ms(step.ms)) ms", size: 15, weight: .medium)
        time.setContentHuggingPriority(.required, for: .horizontal)
        time.setContentCompressionResistancePriority(.required, for: .horizontal)
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let titleRow = Ui.stack([name, time], axis: .horizontal, spacing: 8, alignment: .firstBaseline)

        let detail = Ui.label(step.detail, size: 13, color: .secondaryLabel)
        let share = Float(step.ms / total)
        let bar = Ui.bar(step.ms > 0 ? max(share, 0.01) : 0, color: step.ok ? .systemBlue : Ui.danger)

        let column = Ui.stack([titleRow, detail, bar], spacing: 2)
        column.setCustomSpacing(6, after: detail)

        let row = Ui.stack([dot, column], axis: .horizontal, spacing: 12, alignment: .top)
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 8, left: 0, bottom: 4, right: 0)
        return row
    }

    /// Readable names for the step identifiers the library reports.
    static func stepName(_ name: String) -> String {
        switch name {
        case "faceDetection": return "Face detection"
        case "templateExtraction": return "Template extraction"
        case "similarity": return "1:N search"
        case "livenessCheck": return "Liveness check"
        case "duplicateCheck": return "Duplicate check (1:N)"
        case "save": return "Save to gallery"
        default: return name
        }
    }

    static func functionName(_ function: String) -> String {
        switch function {
        case "identify": return "Identity"
        case "enroll": return "Enroll"
        case "attribute": return "Attribute"
        default: return function.prefix(1).uppercased() + function.dropFirst()
        }
    }

    /// An alert for an action that stopped: the reason on top, then the status card.
    static func present(
        on presenter: UIViewController,
        title: String,
        reason: String?,
        report: CallReport?,
        onDone: (() -> Void)? = nil
    ) {
        let controller = StatusDialogViewController(title: title, reason: reason, report: report, onDone: onDone)
        presenter.present(controller, animated: true)
    }
}

/// The sheet `StatusCardView.present` shows.
final class StatusDialogViewController: UIViewController {

    private let dialogTitle: String
    private let reason: String?
    private let report: CallReport?
    private let onDone: (() -> Void)?
    /// Guards against firing twice: once from Done, once from the swipe-to-dismiss path.
    private var didFinish = false

    init(title: String, reason: String?, report: CallReport?, onDone: (() -> Void)?) {
        dialogTitle = title
        self.reason = reason
        self.report = report
        self.onDone = onDone
        super.init(nibName: nil, bundle: nil)
        if let sheet = sheetPresentationController {
            // A status card is a list of calls, so it opens full height rather than making
            // the reader drag it up. The card itself is unchanged.
            sheet.detents = [.large()]
            sheet.selectedDetentIdentifier = .large
            sheet.prefersGrabberVisible = true
        }
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        var views: [UIView] = [Ui.label(dialogTitle, size: 20, weight: .semibold)]
        if let reason, !reason.isEmpty {
            views.append(Ui.label(reason, size: 16))
        }
        if let report {
            views.append(StatusCardView(report: report))
        }
        let done = UIButton(type: .system)
        done.setTitle("Done", for: .normal)
        done.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        done.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        views.append(done)

        let stack = Ui.stack(views, spacing: 16)
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        view.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40),
        ])
    }

    @objc private func doneTapped() {
        dismiss(animated: true) { [weak self] in self?.finish() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        finish()
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        onDone?()
    }
}
