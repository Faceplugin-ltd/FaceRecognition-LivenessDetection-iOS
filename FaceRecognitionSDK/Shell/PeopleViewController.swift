import FaceRecognitionKit
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// People: count tag, Add, delete all, search, and a paged list.
final class PeopleViewController: UIViewController {

    private static let pageSize = 30

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchController = UISearchController(searchResultsController: nil)
    /// The "N faces" tag beside the title, as on Android.
    private let countTag = Ui.idTagLabel(0)
    private let emptyLabel = Ui.label(size: 17, color: .secondaryLabel)

    private var items: [FaceRecord] = []
    private var query = ""
    private var total = 0
    private var loading = false
    private var endReached = false
    private var generation = 0
    private var searchWork: DispatchWorkItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "People"
        view.backgroundColor = .systemBackground

        // Title and count sit together, the way the Android header reads "People  (4)".
        countTag.text = "0"
        navigationItem.titleView = Ui.stack(
            [Ui.label("People", size: 17, weight: .semibold), countTag],
            axis: .horizontal, spacing: 8, alignment: .center
        )
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "trash"), style: .plain, target: self, action: #selector(deleteAllTapped)),
            UIBarButtonItem(image: UIImage(systemName: "person.badge.plus"), style: .plain, target: self, action: #selector(addTapped)),
        ]

        // A search controller keeps its own layout on rotation and Dynamic Type, which a
        // hand-framed search bar in the table header did not.
        searchController.searchBar.placeholder = "Search by name or note"
        searchController.searchBar.delegate = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.hidesNavigationBarDuringPresentation = false
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(PersonCell.self, forCellReuseIdentifier: PersonCell.reuseId)
        tableView.rowHeight = 72
        tableView.keyboardDismissMode = .onDrag

        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true

        [tableView, emptyLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: FaceGallery.didChange, object: nil)
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    // MARK: - Add

    @objc private func addTapped() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Enroll with camera", style: .default) { [weak self] _ in
            guard let self else { return }
            self.navigationController?.pushViewController(AddPersonViewController(), animated: true)
        })
        sheet.addAction(UIAlertAction(title: "Bulk enroll from photos", style: .default) { [weak self] _ in
            self?.chooseMultipleSource()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.last
        present(sheet, animated: true)
    }

    /// Bulk enroll from photos: pick several photos, or a folder whose photos are all imported.
    private func chooseMultipleSource() {
        let sheet = UIAlertController(title: "Bulk enroll from photos", message: nil, preferredStyle: .alert)
        sheet.addAction(UIAlertAction(title: "Select photos", style: .default) { [weak self] _ in
            guard let self else { return }
            var config = PHPickerConfiguration()
            config.filter = .images
            config.selectionLimit = 0
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = self
            self.present(picker, animated: true)
        })
        sheet.addAction(UIAlertAction(title: "Select a folder", style: .default) { [weak self] _ in
            guard let self else { return }
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
            picker.delegate = self
            self.present(picker, animated: true)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    @objc private func deleteAllTapped() {
        FaceEngine.shared.worker.async { [weak self] in
            let n = FaceGallery.shared.count()
            DispatchQueue.main.async {
                guard let self else { return }
                guard n > 0 else {
                    let alert = UIAlertController(title: nil, message: "Nothing to delete.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                    return
                }
                let alert = UIAlertController(
                    title: "Delete all faces",
                    message: "Delete all \(n) enrolled faces and their photos? This can't be undone.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                alert.addAction(UIAlertAction(title: "Delete all", style: .destructive) { _ in
                    FaceEngine.shared.worker.async { FaceGallery.shared.deleteAll() }
                })
                self.present(alert, animated: true)
            }
        }
    }

    // MARK: - Paging

    @objc private func reload() {
        generation += 1
        items = []
        endReached = false
        loading = false
        tableView.reloadData()

        let generation = self.generation
        let query = self.query
        FaceEngine.shared.worker.async { [weak self] in
            let all = FaceGallery.shared.count()
            let filtered = query.isEmpty ? all : FaceGallery.shared.count(query: query)
            DispatchQueue.main.async {
                guard let self, generation == self.generation else { return }
                self.total = filtered
                self.countTag.text = "\(all)"
                self.updateEmpty(all: all)
                self.loadMore()
            }
        }
    }

    private func loadMore() {
        guard !loading, !endReached else { return }
        loading = true
        let generation = self.generation
        let query = self.query
        let offset = items.count
        FaceEngine.shared.worker.async { [weak self] in
            let page = FaceGallery.shared.page(query: query, limit: PeopleViewController.pageSize, offset: offset)
            DispatchQueue.main.async {
                guard let self, generation == self.generation else { return }
                self.loading = false
                if page.count < PeopleViewController.pageSize { self.endReached = true }
                let start = self.items.count
                self.items.append(contentsOf: page)
                let paths = (start..<self.items.count).map { IndexPath(row: $0, section: 0) }
                self.tableView.insertRows(at: paths, with: .none)
                self.updateEmpty(all: nil)
            }
        }
    }

    private func updateEmpty(all: Int?) {
        let galleryEmpty = (all ?? -1) == 0
        emptyLabel.isHidden = !(items.isEmpty && !loading && (galleryEmpty || total == 0))
        emptyLabel.text = query.isEmpty
            ? "No one enrolled yet.\nAdd a person with the button above."
            : "No results"
    }
}

// MARK: - Table

extension PeopleViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: PersonCell.reuseId, for: indexPath)
        (cell as? PersonCell)?.bind(items[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        present(FaceDetailSheetViewController(id: items[indexPath.row].id), animated: true)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if indexPath.row >= items.count - 8 { loadMore() }
    }
}

// MARK: - Search

extension PeopleViewController: UISearchBarDelegate {

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        searchWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        searchWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - Importing

extension PeopleViewController: PHPickerViewControllerDelegate, UIDocumentPickerDelegate {

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else { return }
        let providers = results.map(\.itemProvider)
        navigationController?.pushViewController(ImportViewController(providers: providers), animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let folder = urls.first else { return }
        navigationController?.pushViewController(ImportViewController(folder: folder), animated: true)
    }
}

/// One person row: round crop, name, note and date, ID tag.
final class PersonCell: UITableViewCell {

    static let reuseId = "PersonCell"

    private let thumb = UIImageView()
    private let name = Ui.label(size: 17)
    private let subline = Ui.label(size: 13, color: .secondaryLabel)
    private let idTag = Ui.idTagLabel(0)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator

        thumb.contentMode = .scaleAspectFill
        thumb.clipsToBounds = true
        thumb.layer.cornerRadius = 24
        thumb.backgroundColor = .tertiarySystemFill
        thumb.widthAnchor.constraint(equalToConstant: 48).isActive = true
        thumb.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let titles = Ui.stack([name, subline], spacing: 2)
        let row = Ui.stack([thumb, titles, idTag], axis: .horizontal, spacing: 12, alignment: .center)
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func bind(_ record: FaceRecord) {
        name.text = record.name
        let date = Ui.enrolledDate(record.createdAt)
        subline.text = record.note.isEmpty ? date : "\(record.note) · \(date)"
        idTag.text = Ui.idTag(record.id)
        Ui.loadImage(record.cropPath, into: thumb, maxSide: 144)
    }
}
