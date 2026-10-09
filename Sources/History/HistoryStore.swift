import Core
import Foundation
import SQLite3

/// One saved dictation.
public struct HistoryEntry: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let date: Date
    public let text: String
    /// The app that was in front, if known.
    public let app: String?
    public let language: Language
    /// False when the text couldn't be put into the app (it's kept here so it isn't lost).
    public let inserted: Bool
    /// The recording, when audio retention was on.
    public let audio: URL?
}

/// Transcripts kept on this Mac only: an SQLite file plus, if the user opts in, each dictation's audio as a
/// WAV file next to it. Deleting an entry deletes its audio; clearing deletes everything. The folder is
/// left out of Time Machine backups and deleted text is overwritten, so a deletion really is one.
@MainActor
public final class HistoryStore {
    public struct Failure: LocalizedError {
        public let message: String
        public init(message: String) { self.message = message }
        public var errorDescription: String? { "History: \(message)" }
    }

    /// The app's history folder in Application Support.
    public static var defaultFolder: URL {
        URL.applicationSupportDirectory.appending(path: "open-voice-flow/history", directoryHint: .isDirectory)
    }

    /// Bumped (with a migration in `migrate()`) whenever the table changes.
    static let schemaVersion: Int32 = 1
    /// The window shows this many of the newest entries; search covers the whole history.
    public static let pageSize = 500

    private let database: OpaquePointer
    private let audioFolder: URL

    public init(folder: URL = HistoryStore.defaultFolder) throws {
        audioFolder = folder.appending(path: "audio", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: audioFolder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var excluded = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)

        var handle: OpaquePointer?
        let opened = sqlite3_open(folder.appending(path: "history.sqlite").path, &handle)
        guard opened == SQLITE_OK, let handle else {
            sqlite3_close(handle)
            throw Failure(message: "couldn't open the database (code \(opened))")
        }
        database = handle
        try execute("PRAGMA secure_delete = ON")  // deleted text is zeroed, not left in free pages
        try migrate()
    }

    private func migrate() throws {
        let statement = try prepare("PRAGMA user_version")
        defer { sqlite3_finalize(statement) }
        let version = sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int(statement, 0) : 0
        guard version < Self.schemaVersion else { return }
        try execute("""
            CREATE TABLE IF NOT EXISTS entries (
                id INTEGER PRIMARY KEY,
                date REAL NOT NULL,
                text TEXT NOT NULL,
                app TEXT,
                language TEXT NOT NULL,
                inserted INTEGER NOT NULL,
                audio TEXT
            )
            """)
        try execute("PRAGMA user_version = \(Self.schemaVersion)")
    }

    isolated deinit {
        sqlite3_close(database)
    }

    /// Saves the text, and the recording too when `keepAudio` is on. The text matters most: if the recording
    /// can't be written the entry is saved without it, and a recording is never left without its entry.
    @discardableResult
    public func save(_ transcript: SessionTranscript, at date: Date, keepAudio: Bool) throws -> HistoryEntry {
        var audioName: String?
        if keepAudio, !transcript.clip.isEmpty {
            let name = "\(UUID().uuidString).wav"
            if (try? WAVFile.data(for: transcript.clip).write(to: audioFolder.appending(path: name))) != nil {
                audioName = name
            }
        }
        do {
            let statement = try prepare("INSERT INTO entries (date, text, app, language, inserted, audio) VALUES (?, ?, ?, ?, ?, ?)")
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
            bind(transcript.text, to: statement, at: 2)
            bind(transcript.app, to: statement, at: 3)
            bind(transcript.language.rawValue, to: statement, at: 4)
            sqlite3_bind_int(statement, 5, transcript.inserted ? 1 : 0)
            bind(audioName, to: statement, at: 6)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw failure("couldn't save") }
        } catch {
            if let audioName { try? FileManager.default.removeItem(at: audioFolder.appending(path: audioName)) }
            throw error
        }
        return HistoryEntry(id: sqlite3_last_insert_rowid(database), date: date, text: transcript.text, app: transcript.app,
                            language: transcript.language, inserted: transcript.inserted,
                            audio: audioName.map { audioFolder.appending(path: $0) })
    }

    /// Newest first; `query` matches any part of the text, ignoring case.
    public func entries(matching query: String = "", limit: Int = HistoryStore.pageSize) throws -> [HistoryEntry] {
        let statement = try prepare("""
            SELECT id, date, text, app, language, inserted, audio FROM entries
            WHERE text LIKE ? ESCAPE '\\' ORDER BY date DESC, id DESC LIMIT ?
            """)
        defer { sqlite3_finalize(statement) }
        let escaped = query.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
        bind("%\(escaped)%", to: statement, at: 1)
        sqlite3_bind_int64(statement, 2, Int64(limit))
        var entries: [HistoryEntry] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw failure("couldn't read") }
            entries.append(HistoryEntry(
                id: sqlite3_column_int64(statement, 0),
                date: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                text: string(statement, 2) ?? "",
                app: string(statement, 3),
                language: Language(rawValue: string(statement, 4) ?? "") ?? .hinglish,
                inserted: sqlite3_column_int(statement, 5) != 0,
                audio: string(statement, 6).map { audioFolder.appending(path: $0) }
            ))
        }
        return entries
    }

    public func delete(_ entry: HistoryEntry) throws {
        let statement = try prepare("DELETE FROM entries WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, entry.id)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure("couldn't delete") }
        if let audio = entry.audio { try? FileManager.default.removeItem(at: audio) }
    }

    /// Deletes every recording, then every transcript. Keeps going past a file that won't delete, and
    /// throws afterwards if anything is left.
    public func clear() throws {
        var stuck = 0
        for file in (try? FileManager.default.contentsOfDirectory(at: audioFolder, includingPropertiesForKeys: nil)) ?? [] {
            if (try? FileManager.default.removeItem(at: file)) == nil { stuck += 1 }
        }
        try execute("DELETE FROM entries")
        try? execute("VACUUM")  // shrinks the file; secure_delete has already zeroed the text
        if stuck > 0 { throw Failure(message: "\(stuck) recording(s) couldn't be deleted") }
    }

    // MARK: SQLite

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw failure("query failed") }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw failure("couldn't prepare a query")
        }
        return statement
    }

    private func bind(_ value: String?, to statement: OpaquePointer, at index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        // SQLITE_TRANSIENT: SQLite copies the string.
        sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private func string(_ statement: OpaquePointer, _ column: Int32) -> String? {
        sqlite3_column_text(statement, column).map { String(cString: $0) }
    }

    private func failure(_ message: String) -> Failure {
        Failure(message: "\(message) (\(String(cString: sqlite3_errmsg(database))))")
    }
}
