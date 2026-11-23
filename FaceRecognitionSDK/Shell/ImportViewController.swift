import FaceRecognitionKit
import UIKit
import UniformTypeIdentifiers

/// Import photos: each photo becomes one person named after the file.
/// Photos with no face, or more than one, are skipped with the reason.
final class ImportViewController: UIViewController {

    private struct Item {
        let name: String
        let load: (@escaping (UIImage?) -> Void) -> Void
    }

    private let items: [Item]
    private let folder: URL?

    private let summaryLabel = Ui.label(size: 22, weight: .semibold)
    private let rulesLabel = Ui.label(
        "Each photo becomes one person, named after the file. Photos with no face or more than one face are skipped.",
        size: 15, color: .secondaryLabel
    )
    private let progressBar = UIProgressView(progressViewStyle: .default)
    private let progressLabel = Ui.label(size: 15)
    private let metricsRow = UIStackView.metricsRow()
    private let resultsHeader = Ui.stack([], axis: .horizontal, spacing: 8, alignment: .center)
    private let resultsList = Ui.stack([], spacing: 0)
    private let resultLabel = Ui.label(size: 17, weight: .semibold)
    private let actionButton = UIButton(type: .system)
    private let progressSection = Ui.stack([], spacing: 12)

    private var enrolled = 0
    private var skipped = 0
    private var totalMs: Double = 0
    private var started = false
    private var finished = false
    private var cancelled = false

    private var enrolledMetric: MetricTileView?
    private var skippedMetric: MetricTileView?
    private var averageMetric: MetricTileView?
    private var resultsCount = Ui.idTagLabel(0)

    init(providers: [NSItemProvider]) {
        folder = nil
        items = providers.enumerated().map { index, provider in
            let name = provider.suggestedName ?? "photo \(index + 1)"
            return Item(name: name) { done in
                guard provider.canLoadObject(ofClass: UIImage.self) else {
                    done(nil)
                    return
                }
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    done(object as? UIImage)
                }
            }
        }
        super.init(nibName: nil, bundle: nil)
    }

    init(folder: URL) {
        self.folder = folder
        let accessed = folder.startAccessingSecurityScopedResource()
        let extensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "bmp", "webp"]
        let urls = ((try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        )) ?? [])
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
        items = urls.map { url in
            Item(name: url.lastPathComponent) { done in
                done(ImageUtils.load(contentsOf: url))
            }
        }
        if !accessed { /* a folder outside the sandbox may still be readable */ }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        folder?.stopAccessingSecurityScopedResource()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Import photos"
        view.backgroundColor = .systemBackground
        buildLayout()

        if items.isEmpty {
            summaryLabel.text = "No images found"
            finished = true
            actionButton.setTitle("Done", for: .normal)
        } else {
            summaryLabel.text = items.count == 1 ? "Import 1 photo?" : "Import \(items.count) photos?"
        }
        updateMetrics()
    }

    private func buildLayout() {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)

        progressLabel.lineBreakMode = .byTruncatingMiddle
        resultsHeader.addArrangedSubview(Ui.label("Results", size: 17, weight: .semibold))
        resultsHeader.addArrangedSubview(resultsCount)
        resultsHeader.addArrangedSubview(UIView())
        resultsHeader.isHidden = true

        enrolledMetric = metric("Enrolled")
        skippedMetric = metric("Skipped")
        averageMetric = metric("Avg ms / photo")

        resultLabel.isHidden = true
        progressSection.isHidden = true
        [progressBar, progressLabel, metricsRow, resultLabel].forEach { progressSection.addArrangedSubview($0) }

        actionButton.setTitle("Start import", for: .normal)
        actionButton.backgroundColor = .systemIndigo
        actionButton.setTitleColor(.white, for: .normal)
        actionButton.layer.cornerRadius = 10
        actionButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)

        let content = Ui.stack(
            [summaryLabel, rulesLabel, progressSection, resultsHeader, resultsList, actionButton],
            spacing: 16
        )
        scroll.addSubview(content)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32),
        ])
    }

    private func metric(_ caption: String) -> MetricTileView {
        let tile = MetricTileView(caption: caption, value: "0")
        metricsRow.addArrangedSubview(tile)
        return tile
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent { cancelled = true }
    }

    @objc private func actionTapped() {
        if finished {
            navigationController?.popViewController(animated: true)
        } else if !started {
            start()
        }
    }

    private func start() {
        started = true
        actionButton.isEnabled = false
        rulesLabel.isHidden = true
        progressSection.isHidden = false
        progressBar.progress = 0
        importNext(index: 0)
    }

    /// One photo at a time: loading a provider is asynchronous, so this recurses rather than looping.
    private func importNext(index: Int) {
        guard !cancelled, index < items.count else {
            finish()
            return
        }
        let item = items[index]
        progressLabel.text = "\(index + 1) of \(items.count) · \(item.name)"

        item.load { [weak self] image in
            guard let self else { return }
            FaceEngine.shared.worker.async {
                let outcome: EnrollOutcome
                if let image {
                    let prepared = ImageUtils.scaleDown(ImageUtils.upright(image), maxSide: ImageUtils.engineMaxSide)
                    outcome = FaceGallery.shared.enroll(
                        name: ImageUtils.stripExtension(item.name),
                        note: "",
                        photo: prepared,
                        limits: AppSettings.limits
                    )
                } else {
                    outcome = .rejected(reason: "That photo could not be read.", report: nil)
                }
                DispatchQueue.main.async {
                    self.progressBar.setProgress(Float(index + 1) / Float(self.items.count), animated: true)
                    self.addResult(item.name, outcome)
                    self.updateMetrics()
                    self.importNext(index: index + 1)
                }
            }
        }
    }

    private func finish() {
        finished = true
        progressLabel.text = "\(items.count) of \(items.count) · Done"
        resultLabel.isHidden = false
        resultLabel.text = "Enrolled \(enrolled) · skipped \(skipped)"
        actionButton.isEnabled = true
        actionButton.setTitle("Done", for: .normal)
    }

    private func updateMetrics() {
        enrolledMetric?.value = "\(enrolled)"
        skippedMetric?.value = "\(skipped)"
        let n = enrolled + skipped
        averageMetric?.value = n == 0 ? "–" : Ui.ms(totalMs / Double(n))
    }

    /// One row per photo, newest on top. Tap it for the full status card.
    private func addResult(_ fileName: String, _ outcome: EnrollOutcome) {
        var report: CallReport?
        var subtitle = ""
        var tag = ("Skipped", Ui.danger)
        var ok = false
        var duplicates: [Candidate] = []

        switch outcome {
        case let .enrolled(record, enrollReport, dups):
            report = enrollReport
            duplicates = dups
            subtitle = "\(record.name) · \(Ui.idTag(record.id))"
            if !dups.isEmpty {
                // Bulk enroll names every match over the threshold, as Enroll with camera does.
                subtitle += " · Duplicate check: " + dups
                    .map { "\($0.name) \(Ui.idTag($0.id)) \(Ui.score($0.similarity))" }
                    .joined(separator: ", ")
            }
            tag = ("Enrolled", dups.isEmpty ? Ui.statusMatch : Ui.statusNoMatch)
            ok = true
        case let .rejected(reason, rejectedReport):
            report = rejectedReport
            subtitle = reason
        }

        if ok { enrolled += 1 } else { skipped += 1 }
        totalMs += report?.totalMs ?? 0
        _ = duplicates

        resultsHeader.isHidden = false
        resultsCount.text = "\(enrolled + skipped)"

        let name = Ui.label(fileName, size: 16)
        name.lineBreakMode = .byTruncatingMiddle
        let sub = Ui.label(subtitle, size: 13, color: .secondaryLabel)
        let pill = Ui.pill(tag.0, color: tag.1)
        pill.font = .systemFont(ofSize: 11, weight: .bold)
        pill.insets = UIEdgeInsets(top: 2, left: 10, bottom: 2, right: 10)
        pill.layer.cornerRadius = 10
        let time = Ui.label(report.map { "\(Ui.ms($0.totalMs)) ms" } ?? "", size: 12, color: .secondaryLabel)
        let right = Ui.stack([pill, time], spacing: 4, alignment: .trailing)

        let row = Ui.stack([Ui.stack([name, sub], spacing: 2), right], axis: .horizontal, spacing: 12, alignment: .center)
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)

        let holder = Ui.stack([row], spacing: 0)
        if let report {
            let expanded = UIView()
            expanded.isHidden = true
            holder.addArrangedSubview(expanded)
            row.isUserInteractionEnabled = true
            let recognizer = TapRecognizer { [weak self] in
                guard let self else { return }
                if expanded.subviews.isEmpty {
                    let card = StatusCardView(report: report, title: "Enrollment status")
                    card.translatesAutoresizingMaskIntoConstraints = false
                    expanded.addSubview(card)
                    NSLayoutConstraint.activate([
                        card.topAnchor.constraint(equalTo: expanded.topAnchor),
                        card.leadingAnchor.constraint(equalTo: expanded.leadingAnchor),
                        card.trailingAnchor.constraint(equalTo: expanded.trailingAnchor),
                        card.bottomAnchor.constraint(equalTo: expanded.bottomAnchor, constant: -8),
                    ])
                }
                expanded.isHidden.toggle()
            }
            row.addGestureRecognizer(recognizer.gesture)
            objc_setAssociatedObject(row, &ImportViewController.tapKey, recognizer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        resultsList.insertArrangedSubview(holder, at: 0)
    }

    private static var tapKey: UInt8 = 0
}
