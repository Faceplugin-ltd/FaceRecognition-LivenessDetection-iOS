import FaceRecognitionKit
import UIKit

/// Pushed from Identity: Match / No match, Probe against Rank 1, the metrics, the status card,
/// and every match at or above the threshold.
final class ResultViewController: UIViewController {

    private let result: IdentifyResult
    private var records: [Int64: FaceRecord?] = [:]

    private let content = Ui.stack([], spacing: 16)
    private let statusPill = Ui.pill()
    private let probeImage = UIImageView()
    private let rank1Image = UIImageView()
    private let rank1Caption = Ui.label("Rank 1", size: 13, color: .secondaryLabel)
    private let headline = Ui.label(size: 22, weight: .semibold)
    private let headlineTag = Ui.idTagLabel(0)
    private let subline = Ui.label(size: 15, color: .secondaryLabel)
    private let metricsRow = UIStackView.metricsRow()
    private let statusHolder = UIView()
    private let facesSection = Ui.stack([], spacing: 4)
    private let matchesCount = Ui.idTagLabel(0)
    private let matchesList = Ui.stack([], spacing: 0)
    private let moreButton = UIButton(type: .system)
    private let noMatches = Ui.label(size: 15, color: .secondaryLabel)

    init(result: IdentifyResult) {
        self.result = result
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Result"
        view.backgroundColor = .systemBackground
        buildLayout()

        probeImage.image = ImageUtils.squareAround(result.probe, box: result.primary.box)
        metric("Extract ms", Ui.ms(result.extractMs))
        metric("Search ms", Ui.ms(result.searchMs))
        metric("Gallery size", "\(result.gallerySize)")

        let card = StatusCardView(report: result.report)
        card.translatesAutoresizingMaskIntoConstraints = false
        statusHolder.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: statusHolder.topAnchor),
            card.leadingAnchor.constraint(equalTo: statusHolder.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: statusHolder.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: statusHolder.bottomAnchor),
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(loadRecords), name: FaceGallery.didChange, object: nil)
        render()
        loadRecords()
    }

    private func buildLayout() {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(content)

        [probeImage, rank1Image].forEach {
            $0.contentMode = .scaleAspectFill
            $0.clipsToBounds = true
            $0.layer.cornerRadius = 16
            $0.backgroundColor = .tertiarySystemFill
        }
        let probeColumn = Ui.stack([probeImage, Ui.label("Probe", size: 13, color: .secondaryLabel)], spacing: 6)
        let rankColumn = Ui.stack([rank1Image, rank1Caption], spacing: 6)
        let tiles = Ui.stack([probeColumn, rankColumn], axis: .horizontal, spacing: 12)
        tiles.distribution = .fillEqually
        probeImage.heightAnchor.constraint(equalTo: probeImage.widthAnchor).isActive = true
        rank1Image.heightAnchor.constraint(equalTo: rank1Image.widthAnchor).isActive = true
        probeColumn.widthAnchor.constraint(equalTo: rankColumn.widthAnchor).isActive = true

        let headlineRow = Ui.stack([headline, headlineTag, UIView()], axis: .horizontal, spacing: 8, alignment: .center)

        moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
        let matchesHeader = Ui.stack(
            [Ui.label("Matches", size: 17, weight: .semibold), matchesCount, UIView(), moreButton],
            axis: .horizontal, spacing: 8, alignment: .center
        )

        [statusPill, tiles, headlineRow, subline, metricsRow, statusHolder, facesSection, matchesHeader, matchesList, noMatches]
            .forEach { content.addArrangedSubview($0) }
        content.setCustomSpacing(4, after: headlineRow)
        content.setCustomSpacing(8, after: matchesHeader)

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

    private func metric(_ caption: String, _ value: String) {
        metricsRow.addArrangedSubview(MetricTileView(caption: caption, value: value))
    }

    /// Fetches the stored records (thumbnails, originals, current names) for every shown face.
    @objc private func loadRecords() {
        let ids = Set(result.faces.compactMap { $0.best?.id } + result.matches.map(\.id))
        FaceEngine.shared.worker.async { [weak self] in
            var map: [Int64: FaceRecord?] = [:]
            for id in ids { map[id] = FaceGallery.shared.get(id) }
            DispatchQueue.main.async {
                self?.records = map
                self?.render()
            }
        }
    }

    /// Records not yet loaded count as present; deleted ones drop off the screen.
    private func exists(_ id: Int64) -> Bool {
        guard let entry = records[id] else { return true }
        return entry != nil
    }

    private func render() {
        let threshold = result.threshold
        let best = result.primary.best.flatMap { exists($0.id) ? $0 : nil }
        let matched = (best?.similarity ?? -1) >= threshold
        let matches = result.matches.filter { exists($0.id) }

        statusPill.text = matched ? "Match" : "No match"
        statusPill.backgroundColor = matched ? Ui.statusMatch : Ui.statusNoMatch
        rank1Caption.text = matched ? "Rank 1" : "Closest"

        let record = best.flatMap { records[$0.id] ?? nil }
        // Rank 1 shows the stored original, falling back to the crop.
        Ui.loadImage(record?.originalPath, into: rank1Image) { [weak self] in
            guard let self else { return }
            Ui.loadImage(record?.cropPath, into: self.rank1Image)
        }

        if let best {
            headline.text = record?.name ?? best.name
            headlineTag.isHidden = false
            headlineTag.text = Ui.idTag(best.id)
            subline.text = matched
                ? "Similarity \(Ui.score(best.similarity)) · above \(Ui.score(threshold))"
                : "No gallery face reaches the threshold \(Ui.score(threshold))"
        } else {
            headline.text = "Gallery is empty"
            headlineTag.isHidden = true
            subline.text = "No gallery face reaches the threshold \(Ui.score(threshold))"
        }

        renderFaces()

        matchesCount.text = Ui.matchesCount(matches.count)
        matchesList.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, candidate) in matches.prefix(ResultViewController.maxRows).enumerated() {
            matchesList.addArrangedSubview(MatchRowView(
                rank: index + 1,
                candidate: candidate,
                record: records[candidate.id] ?? nil
            ) { [weak self] in self?.openFace($0) })
        }
        moreButton.isHidden = matches.count <= ResultViewController.maxRows
        moreButton.setTitle("\(matches.count - ResultViewController.maxRows) more ›", for: .normal)
        noMatches.isHidden = !matches.isEmpty
        noMatches.text = "No gallery face reaches the threshold \(Ui.score(threshold))"
    }

    /// When the probe has two or more faces, one line per face.
    private func renderFaces() {
        facesSection.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard result.faces.count >= 2 else {
            facesSection.isHidden = true
            return
        }
        facesSection.isHidden = false
        facesSection.addArrangedSubview(Ui.label("Probe faces", size: 15, weight: .semibold))
        for face in result.faces {
            let best = face.best.flatMap { exists($0.id) ? $0 : nil }
            let text: String
            if let best {
                text = best.similarity >= result.threshold
                    ? "Face \(face.index + 1) · \(records[best.id].flatMap { $0?.name } ?? best.name) · \(Ui.idTag(best.id)) · \(Ui.score(best.similarity))"
                    : "Face \(face.index + 1) · No match · closest \(Ui.score(best.similarity))"
            } else {
                text = "Face \(face.index + 1) · no gallery faces"
            }
            facesSection.addArrangedSubview(Ui.label(text, size: 15))
        }
    }

    private func openFace(_ candidate: Candidate) {
        present(FaceDetailSheetViewController(id: candidate.id, similarity: candidate.similarity), animated: true)
    }

    @objc private func moreTapped() {
        navigationController?.pushViewController(MatchesViewController(result: result), animated: true)
    }

    static let maxRows = 3
}

/// The "N more" target: every match at or above the threshold.
final class MatchesViewController: UIViewController {

    private let result: IdentifyResult
    private let list = Ui.stack([], spacing: 0)

    init(result: IdentifyResult) {
        self.result = result
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let matches = result.matches
        title = "Matches"
        navigationItem.prompt = Ui.matchesCount(matches.count)

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(list)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            list.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 8),
            list.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            list.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            list.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            list.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32),
        ])

        FaceEngine.shared.worker.async { [weak self] in
            guard let self else { return }
            let records = Dictionary(uniqueKeysWithValues: matches.map { ($0.id, FaceGallery.shared.get($0.id)) })
            DispatchQueue.main.async {
                for (index, candidate) in matches.enumerated() {
                    guard let record = records[candidate.id], record != nil else { continue }
                    self.list.addArrangedSubview(MatchRowView(
                        rank: index + 1,
                        candidate: candidate,
                        record: record
                    ) { [weak self] in
                        self?.present(FaceDetailSheetViewController(id: $0.id, similarity: $0.similarity), animated: true)
                    })
                }
            }
        }
    }
}
