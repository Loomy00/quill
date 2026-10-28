import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct Transcript: Identifiable, Hashable {
    let id: Int64
    let createdAt: Date
    let rawText: String
    let cleanedText: String
    let durationSeconds: Double
    let appName: String?
    let model: String
    let cleanupProvider: String

    var finalText: String { cleanedText.isEmpty ? rawText : cleanedText }
}

enum DatabaseError: LocalizedError {
    case open(String), prepare(String), step(String)
    var errorDescription: String? {
        switch self {
        case .open(let m): return "Could not open database: \(m)"
        case .prepare(let m): return "SQL prepare failed: \(m)"
        case .step(let m): return "SQL step failed: \(m)"
        }
    }
}

/// Thin wrapper over the system SQLite library. All access is serialized on one queue.
final class Database {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "dictate.sqlite")

    static func defaultURL() -> URL {
        AppPaths.supportDirectory.appendingPathComponent("dictate.sqlite")
    }

    init(url: URL = Database.defaultURL()) throws {
        if sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            throw DatabaseError.open(String(cString: sqlite3_errmsg(db)))
        }
        try exec("PRAGMA journal_mode=WAL;")
        try exec("""
            CREATE TABLE IF NOT EXISTS transcripts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                created_at REAL NOT NULL,
                raw_text TEXT NOT NULL,
                cleaned_text TEXT NOT NULL DEFAULT '',
                duration REAL NOT NULL DEFAULT 0,
                app_name TEXT,
                model TEXT NOT NULL DEFAULT '',
                cleanup_provider TEXT NOT NULL DEFAULT ''
            );
            CREATE INDEX IF NOT EXISTS idx_transcripts_created ON transcripts(created_at DESC);
            CREATE TABLE IF NOT EXISTS dictionary (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                term TEXT NOT NULL,
                sounds_like TEXT NOT NULL DEFAULT ''
            );
            CREATE TABLE IF NOT EXISTS snippets (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                trigger TEXT NOT NULL,
                expansion TEXT NOT NULL
            );
            """)
        migrate()
    }

    deinit { sqlite3_close(db) }

    /// Adds columns introduced after the first release; errors mean the column already exists.
    private func migrate() {
        try? exec("ALTER TABLE transcripts ADD COLUMN outcome TEXT NOT NULL DEFAULT ''")
    }

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw DatabaseError.step(msg)
        }
    }

    @discardableResult
    func insert(rawText: String, cleanedText: String, duration: Double, appName: String?, model: String, cleanupProvider: String, outcome: String = "") throws -> Int64 {
        try queue.sync {
            var stmt: OpaquePointer?
            let sql = "INSERT INTO transcripts (created_at, raw_text, cleaned_text, duration, app_name, model, cleanup_provider, outcome) VALUES (?,?,?,?,?,?,?,?)"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepare(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
            sqlite3_bind_text(stmt, 2, rawText, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, cleanedText, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 4, duration)
            if let appName { sqlite3_bind_text(stmt, 5, appName, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, 5) }
            sqlite3_bind_text(stmt, 6, model, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 7, cleanupProvider, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 8, outcome, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.step(String(cString: sqlite3_errmsg(db)))
            }
            return sqlite3_last_insert_rowid(db)
        }
    }

    func fetch(search: String = "", limit: Int = 500) -> [Transcript] {
        queue.sync {
            var stmt: OpaquePointer?
            let filtered = !search.isEmpty
            let sql = "SELECT id, created_at, raw_text, cleaned_text, duration, app_name, model, cleanup_provider FROM transcripts "
                + (filtered ? "WHERE raw_text LIKE ?1 OR cleaned_text LIKE ?1 " : "")
                + "ORDER BY created_at DESC LIMIT \(limit)"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            if filtered { sqlite3_bind_text(stmt, 1, "%\(search)%", -1, SQLITE_TRANSIENT) }
            var rows: [Transcript] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                func text(_ i: Int32) -> String? { sqlite3_column_text(stmt, i).map { String(cString: $0) } }
                rows.append(Transcript(
                    id: sqlite3_column_int64(stmt, 0),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                    rawText: text(2) ?? "",
                    cleanedText: text(3) ?? "",
                    durationSeconds: sqlite3_column_double(stmt, 4),
                    appName: text(5),
                    model: text(6) ?? "",
                    cleanupProvider: text(7) ?? ""))
            }
            return rows
        }
    }

    func delete(id: Int64) {
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM transcripts WHERE id = ?", -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, id)
            sqlite3_step(stmt)
        }
    }

    func deleteAll() {
        queue.sync { try? exec("DELETE FROM transcripts;") }
    }

    struct Stats {
        var dictations = 0
        var words = 0
        var seconds = 0.0
        var streakDays = 0
        var wordsPerMinute: Int { seconds > 1 ? Int(Double(words) / (seconds / 60)) : 0 }
        /// Minutes saved versus typing at 40 wpm.
        var minutesSaved: Double { max(0, Double(words) / 40 - seconds / 60) }
    }

    func stats() -> Stats {
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT created_at, cleaned_text, raw_text, duration FROM transcripts", -1, &stmt, nil) == SQLITE_OK else { return Stats() }
            defer { sqlite3_finalize(stmt) }
            var st = Stats()
            var days = Set<Date>()
            let cal = Calendar.current
            while sqlite3_step(stmt) == SQLITE_ROW {
                let date = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0))
                let cleaned = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                let raw = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
                st.dictations += 1
                st.words += (cleaned.isEmpty ? raw : cleaned).split(whereSeparator: { $0.isWhitespace }).count
                st.seconds += sqlite3_column_double(stmt, 3)
                days.insert(cal.startOfDay(for: date))
            }
            var day = cal.startOfDay(for: Date())
            if !days.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
            while days.contains(day) {
                st.streakDays += 1
                day = cal.date(byAdding: .day, value: -1, to: day)!
            }
            return st
        }
    }

    // MARK: Dictionary & snippets

    func dictionary() -> [DictionaryEntry] {
        rows("SELECT id, term, sounds_like FROM dictionary ORDER BY term COLLATE NOCASE") {
            DictionaryEntry(id: sqlite3_column_int64($0, 0), term: Self.text($0, 1), soundsLike: Self.text($0, 2))
        }
    }

    func snippets() -> [Snippet] {
        rows("SELECT id, trigger, expansion FROM snippets ORDER BY trigger COLLATE NOCASE") {
            Snippet(id: sqlite3_column_int64($0, 0), trigger: Self.text($0, 1), expansion: Self.text($0, 2))
        }
    }

    func addDictionary(term: String, soundsLike: String) { run("INSERT INTO dictionary (term, sounds_like) VALUES (?, ?)", [term, soundsLike]) }
    func deleteDictionary(id: Int64) { run("DELETE FROM dictionary WHERE id = ?", [String(id)]) }
    func addSnippet(trigger: String, expansion: String) { run("INSERT INTO snippets (trigger, expansion) VALUES (?, ?)", [trigger, expansion]) }
    func deleteSnippet(id: Int64) { run("DELETE FROM snippets WHERE id = ?", [String(id)]) }

    private static func text(_ stmt: OpaquePointer?, _ i: Int32) -> String {
        sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
    }

    private func rows<T>(_ sql: String, _ map: (OpaquePointer?) -> T) -> [T] {
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            var out: [T] = []
            while sqlite3_step(stmt) == SQLITE_ROW { out.append(map(stmt)) }
            return out
        }
    }

    private func run(_ sql: String, _ params: [String]) {
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            for (i, p) in params.enumerated() { sqlite3_bind_text(stmt, Int32(i + 1), p, -1, SQLITE_TRANSIENT) }
            sqlite3_step(stmt)
        }
    }
}

struct DictionaryEntry: Identifiable, Hashable {
    let id: Int64
    let term: String
    let soundsLike: String
}

struct Snippet: Identifiable, Hashable {
    let id: Int64
    let trigger: String
    let expansion: String
}
