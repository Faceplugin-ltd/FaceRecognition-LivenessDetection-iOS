import Foundation
import SQLite3

/// One enrolled face. Images live as JPEG files in the app's Application Support directory.
public struct FaceRecord: Equatable {
    public let id: Int64
    public let name: String
    public let note: String
    /// ISO-8601 UTC.
    public let createdAt: String
    public let cropPath: String
    public let originalPath: String
    /// JSON of the `CallReport` from enrolment; empty for faces enrolled before it was stored.
    public let enrollReport: String
}

/// SQLite gallery. `id INTEGER PRIMARY KEY AUTOINCREMENT`, so ids are never reused, even after
/// Delete all. Every method is called on `FaceGallery`'s serial queue.
final class GalleryStore {

    private var db: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String) {
        if sqlite3_open(path, &db) != SQLITE_OK {
            db = nil
            return
        }
        exec("""
            CREATE TABLE IF NOT EXISTS faces (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                note TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                feature BLOB NOT NULL,
                crop_path TEXT NOT NULL DEFAULT '',
                original_path TEXT NOT NULL DEFAULT '',
                enroll_report TEXT NOT NULL DEFAULT ''
            )
            """)
        exec("CREATE INDEX IF NOT EXISTS idx_faces_name ON faces(name)")
    }

    deinit {
        if db != nil { sqlite3_close(db) }
    }

    private func exec(_ sql: String) {
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        guard let db else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            sqlite3_finalize(statement)
            return nil
        }
        return statement
    }

    private func bindText(_ statement: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(statement, index, value, -1, GalleryStore.transient)
    }

    // MARK: - Read

    private static let columns = "id, name, note, created_at, crop_path, original_path, enroll_report"

    /// Matches name or note, with LIKE wildcards escaped.
    private func filter(_ query: String) -> (String, String?) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return ("", nil) }
        let escaped = trimmed
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return (" WHERE name LIKE ?1 ESCAPE '\\' OR note LIKE ?1 ESCAPE '\\'", "%\(escaped)%")
    }

    func count(query: String = "") -> Int {
        let (where_, like) = filter(query)
        guard let statement = prepare("SELECT COUNT(*) FROM faces\(where_)") else { return 0 }
        defer { sqlite3_finalize(statement) }
        if let like { bindText(statement, 1, like) }
        return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int(statement, 0)) : 0
    }

    func get(_ id: Int64) -> FaceRecord? {
        guard let statement = prepare("SELECT \(GalleryStore.columns) FROM faces WHERE id = ?1") else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        return sqlite3_step(statement) == SQLITE_ROW ? record(statement) : nil
    }

    /// Newest first.
    func page(query: String, limit: Int, offset: Int) -> [FaceRecord] {
        let (where_, like) = filter(query)
        let sql = "SELECT \(GalleryStore.columns) FROM faces\(where_) ORDER BY id DESC LIMIT \(limit) OFFSET \(offset)"
        guard let statement = prepare(sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        if let like { bindText(statement, 1, like) }
        var out: [FaceRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            out.append(record(statement))
        }
        return out
    }

    struct Template {
        let id: Int64
        let name: String
        let note: String
        let feature: Data
    }

    func allTemplates() -> [Template] {
        guard let statement = prepare("SELECT id, name, note, feature FROM faces") else { return [] }
        defer { sqlite3_finalize(statement) }
        var out: [Template] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            out.append(Template(
                id: sqlite3_column_int64(statement, 0),
                name: text(statement, 1),
                note: text(statement, 2),
                feature: blob(statement, 3)
            ))
        }
        return out
    }

    func allPaths() -> [String] {
        guard let statement = prepare("SELECT crop_path, original_path FROM faces") else { return [] }
        defer { sqlite3_finalize(statement) }
        var out: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            out.append(text(statement, 0))
            out.append(text(statement, 1))
        }
        return out.filter { !$0.isEmpty }
    }

    // MARK: - Write

    func insert(name: String, note: String, createdAt: String, feature: Data) -> Int64 {
        guard let db,
              let statement = prepare("INSERT INTO faces (name, note, created_at, feature) VALUES (?, ?, ?, ?)")
        else { return -1 }
        defer { sqlite3_finalize(statement) }
        bindText(statement, 1, name)
        bindText(statement, 2, note)
        bindText(statement, 3, createdAt)
        _ = feature.withUnsafeBytes { raw in
            sqlite3_bind_blob(statement, 4, raw.baseAddress, Int32(feature.count), GalleryStore.transient)
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { return -1 }
        return sqlite3_last_insert_rowid(db)
    }

    func setPaths(_ id: Int64, crop: String, original: String) {
        guard let statement = prepare("UPDATE faces SET crop_path = ?, original_path = ? WHERE id = ?") else { return }
        defer { sqlite3_finalize(statement) }
        bindText(statement, 1, crop)
        bindText(statement, 2, original)
        sqlite3_bind_int64(statement, 3, id)
        sqlite3_step(statement)
    }

    func setReport(_ id: Int64, json: String) {
        guard let statement = prepare("UPDATE faces SET enroll_report = ? WHERE id = ?") else { return }
        defer { sqlite3_finalize(statement) }
        bindText(statement, 1, json)
        sqlite3_bind_int64(statement, 2, id)
        sqlite3_step(statement)
    }

    func update(_ id: Int64, name: String, note: String) -> Bool {
        guard let db, let statement = prepare("UPDATE faces SET name = ?, note = ? WHERE id = ?") else { return false }
        defer { sqlite3_finalize(statement) }
        bindText(statement, 1, name)
        bindText(statement, 2, note)
        sqlite3_bind_int64(statement, 3, id)
        return sqlite3_step(statement) == SQLITE_DONE && sqlite3_changes(db) > 0
    }

    func delete(_ id: Int64) -> Bool {
        guard let db, let statement = prepare("DELETE FROM faces WHERE id = ?") else { return false }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        return sqlite3_step(statement) == SQLITE_DONE && sqlite3_changes(db) > 0
    }

    /// DELETE, not DROP, so sqlite_sequence survives and new ids continue after the old maximum.
    /// Empties the gallery and restarts ids at 1. Clearing `sqlite_sequence` is what resets
    /// AUTOINCREMENT; without it the next person carries on from the old maximum, which makes
    /// a freshly cleared demo gallery look like it still remembers the last one.
    func deleteAll() -> Int {
        guard let db, let statement = prepare("DELETE FROM faces") else { return 0 }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { return 0 }
        let removed = Int(sqlite3_changes(db))
        if let reset = prepare("DELETE FROM sqlite_sequence WHERE name='faces'") {
            sqlite3_step(reset)
            sqlite3_finalize(reset)
        }
        return removed
    }

    // MARK: - Columns

    private func text(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let raw = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: raw)
    }

    private func blob(_ statement: OpaquePointer?, _ index: Int32) -> Data {
        guard let raw = sqlite3_column_blob(statement, index) else { return Data() }
        return Data(bytes: raw, count: Int(sqlite3_column_bytes(statement, index)))
    }

    private func record(_ statement: OpaquePointer?) -> FaceRecord {
        FaceRecord(
            id: sqlite3_column_int64(statement, 0),
            name: text(statement, 1),
            note: text(statement, 2),
            createdAt: text(statement, 3),
            cropPath: text(statement, 4),
            originalPath: text(statement, 5),
            enrollReport: text(statement, 6)
        )
    }
}
