import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum DatabaseError: Error, LocalizedError {
    case open(String)
    case sqlite(String)
    case invalidState(String)

    public var errorDescription: String? {
        switch self {
        case .open(let value), .sqlite(let value), .invalidState(let value): value
        }
    }
}

public final class DatabaseStore: @unchecked Sendable {
    public static var defaultPath: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("com.picmao.translex", isDirectory: true)
            .appendingPathComponent("translex.sqlite3").path
    }

    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let iso = ISO8601DateFormatter()

    public init(path: String = DatabaseStore.defaultPath) throws {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let handle else {
            throw DatabaseError.open("Unable to open SQLite database at \(path)")
        }
        db = handle
        do { try configureAndMigrate() }
        catch { sqlite3_close(handle); db = nil; throw error }
    }

    deinit { if let db { sqlite3_close(db) } }

    private func configureAndMigrate() throws {
        try execute("PRAGMA foreign_keys=ON;")
        try execute("PRAGMA busy_timeout=3000;")
        _ = try scalarText("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA synchronous=NORMAL;")
        try execute("CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);")
        try execute("""
        CREATE TABLE IF NOT EXISTS lexemes (
          id TEXT PRIMARY KEY, language TEXT NOT NULL CHECK(language IN ('en','vi')),
          lemma TEXT NOT NULL, normalized_lemma TEXT NOT NULL,
          part_of_speech TEXT NOT NULL DEFAULT '', pronunciation TEXT,
          content_json TEXT NOT NULL, provenance_json TEXT NOT NULL,
          content_version INTEGER NOT NULL CHECK(content_version > 0),
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
          UNIQUE(language, normalized_lemma, part_of_speech)
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS enrichment_queue (
          id TEXT PRIMARY KEY, source_text TEXT NOT NULL, normalized_text TEXT NOT NULL,
          language TEXT NOT NULL CHECK(language IN ('en','vi')),
          status TEXT NOT NULL CHECK(status IN ('pending','processing','ready','failed')),
          attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT,
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL, processing_started_at TEXT
        );
        """)
        try execute("CREATE UNIQUE INDEX IF NOT EXISTS uq_queue_active ON enrichment_queue(language, normalized_text) WHERE status IN ('pending','processing');")
        try execute("INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES (1, '\(timestamp(Date()))');")
        try execute("""
        CREATE TABLE IF NOT EXISTS favorites (
          id TEXT PRIMARY KEY, source_text TEXT NOT NULL, normalized_source TEXT NOT NULL,
          source_language TEXT NOT NULL CHECK(source_language IN ('en','vi')),
          translated_text TEXT NOT NULL, created_at TEXT NOT NULL,
          UNIQUE(source_language, normalized_source, translated_text)
        );
        """)
        try execute("INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES (2, '\(timestamp(Date()))');")
        if try scalarInt("SELECT COALESCE(MAX(version),0) FROM schema_migrations;") < 3 {
            try migrateFavoritesToVersionThree()
        }
    }

    public func validateDatabase() throws -> DatabaseValidationResult {
        try lock.withLock {
            let result = try scalarText("PRAGMA integrity_check;") ?? "unknown"
            let version = try scalarInt("SELECT COALESCE(MAX(version),0) FROM schema_migrations;")
            return .init(isValid: result == "ok" && version >= 3,
                         message: "integrity=\(result), schema=\(version)")
        }
    }

    public func saveFavorite(
        sourceText: String,
        sourceLanguage: SupportedLanguage,
        translatedText: String,
        now: Date = Date()
    ) throws -> FavoriteRecord {
        try lock.withLock {
            let canonical = FavoriteCanonicalizer.canonicalSource(sourceText, language: sourceLanguage)
            let normalized = LexicalNormalizer.normalize(canonical)
            let translated = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !canonical.isEmpty, !normalized.isEmpty, !translated.isEmpty else {
                throw DatabaseError.invalidState("Cannot favorite empty translation text.")
            }
            let id = UUID().uuidString
            if let existing = try findFavoriteUnlocked(
                sourceLanguage: sourceLanguage,
                canonicalSource: canonical,
                translatedText: translated
            ) {
                return existing
            }
            let stmt = try prepare("INSERT OR IGNORE INTO favorites(id,source_text,normalized_source,source_language,translated_text,created_at,canonical_source) VALUES(?,?,?,?,?,?,?);")
            defer { sqlite3_finalize(stmt) }
            bind(id, at: 1, to: stmt)
            bind(sourceText, at: 2, to: stmt)
            bind(normalized, at: 3, to: stmt)
            bind(sourceLanguage.rawValue, at: 4, to: stmt)
            bind(translated, at: 5, to: stmt)
            bind(timestamp(now), at: 6, to: stmt)
            bind(canonical, at: 7, to: stmt)
            try expectDone(stmt)
            guard let favorite = try findFavoriteUnlocked(
                sourceLanguage: sourceLanguage,
                canonicalSource: canonical,
                translatedText: translated
            ) else {
                throw DatabaseError.invalidState("Favorite insert did not produce a row.")
            }
            return favorite
        }
    }

    public func listFavorites(limit: Int = 500) throws -> [FavoriteRecord] {
        try lock.withLock {
            let stmt = try prepare("SELECT id,source_text,canonical_source,normalized_source,source_language,translated_text,created_at FROM favorites ORDER BY created_at DESC, id DESC LIMIT ?;")
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(max(1, min(limit, 1000))))
            var items: [FavoriteRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW { items.append(try decodeFavorite(stmt)) }
            return items
        }
    }

    @discardableResult
    public func deleteFavorite(id: String) throws -> Bool {
        try lock.withLock {
            let stmt = try prepare("DELETE FROM favorites WHERE id=?;")
            defer { sqlite3_finalize(stmt) }
            bind(id, at: 1, to: stmt)
            try expectDone(stmt)
            return sqlite3_changes(db) == 1
        }
    }

    public func upsertLexeme(_ input: LexemeInput) throws {
        try lock.withLock { try upsertLexemeUnlocked(input) }
    }

    public func getLexeme(language: SupportedLanguage, normalizedLemma: String) throws -> LexemeRecord? {
        try lock.withLock {
            let sql = "SELECT id,language,lemma,normalized_lemma,part_of_speech,pronunciation,content_json,provenance_json,content_version,created_at,updated_at FROM lexemes WHERE language=? AND normalized_lemma=? ORDER BY CASE WHEN part_of_speech='' THEN 0 ELSE 1 END LIMIT 1;"
            let stmt = try prepare(sql)
            defer { sqlite3_finalize(stmt) }
            bind(language.rawValue, at: 1, to: stmt)
            bind(LexicalNormalizer.normalize(normalizedLemma), at: 2, to: stmt)
            return sqlite3_step(stmt) == SQLITE_ROW ? try decodeLexeme(stmt) : nil
        }
    }

    public func enqueue(sourceText: String, language: SupportedLanguage, now: Date = Date()) throws -> EnqueueResult {
        try lock.withLock {
            let normalized = LexicalNormalizer.normalize(sourceText)
            guard !normalized.isEmpty else { throw DatabaseError.invalidState("Cannot queue empty lexical text.") }
            if let active = try findActiveQueue(language: language, normalized: normalized) {
                return .init(item: active, created: false)
            }
            let id = UUID().uuidString
            let ts = timestamp(now)
            let stmt = try prepare("INSERT INTO enrichment_queue(id,source_text,normalized_text,language,status,attempts,created_at,updated_at) VALUES(?,?,?,?, 'pending',0,?,?);")
            defer { sqlite3_finalize(stmt) }
            bind(id, at: 1, to: stmt)
            bind(sourceText, at: 2, to: stmt)
            bind(normalized, at: 3, to: stmt)
            bind(language.rawValue, at: 4, to: stmt)
            bind(ts, at: 5, to: stmt)
            bind(ts, at: 6, to: stmt)
            try expectDone(stmt)
            return .init(item: try getQueueItemUnlocked(id: id)!, created: true)
        }
    }

    public func claimNext(staleAfter: TimeInterval = 900, now: Date = Date()) throws -> QueueItem? {
        try lock.withLock {
            try transaction {
                let cutoff = timestamp(now.addingTimeInterval(-staleAfter))
                let recover = try prepare("UPDATE enrichment_queue SET status='pending', processing_started_at=NULL, updated_at=?, last_error='Recovered stale processing item' WHERE status='processing' AND processing_started_at IS NOT NULL AND processing_started_at < ?;")
                bind(timestamp(now), at: 1, to: recover)
                bind(cutoff, at: 2, to: recover)
                try expectDone(recover)
                sqlite3_finalize(recover)

                let select = try prepare("SELECT id FROM enrichment_queue WHERE status='pending' ORDER BY created_at,id LIMIT 1;")
                defer { sqlite3_finalize(select) }
                guard sqlite3_step(select) == SQLITE_ROW, let id = columnString(select, 0) else { return nil }

                let update = try prepare("UPDATE enrichment_queue SET status='processing', attempts=attempts+1, processing_started_at=?, updated_at=?, last_error=NULL WHERE id=? AND status='pending';")
                bind(timestamp(now), at: 1, to: update)
                bind(timestamp(now), at: 2, to: update)
                bind(id, at: 3, to: update)
                try expectDone(update)
                sqlite3_finalize(update)
                return try getQueueItemUnlocked(id: id)
            }
        }
    }

    public func failQueueItem(id: String, error: String, retry: Bool = false, now: Date = Date()) throws {
        try lock.withLock {
            let status = retry ? "pending" : "failed"
            let stmt = try prepare("UPDATE enrichment_queue SET status=?, last_error=?, processing_started_at=NULL, updated_at=? WHERE id=? AND status='processing';")
            defer { sqlite3_finalize(stmt) }
            bind(status, at: 1, to: stmt)
            bind(String(error.prefix(1000)), at: 2, to: stmt)
            bind(timestamp(now), at: 3, to: stmt)
            bind(id, at: 4, to: stmt)
            try expectDone(stmt)
            guard sqlite3_changes(db) == 1 else {
                throw DatabaseError.invalidState("Queue item is not processing: \(id)")
            }
        }
    }

    public func completeQueueItem(id: String, lexeme: LexemeInput, now: Date = Date()) throws {
        try lock.withLock {
            try transaction {
                try upsertLexemeUnlocked(lexeme, now: now)
                let stmt = try prepare("UPDATE enrichment_queue SET status='ready', processing_started_at=NULL, last_error=NULL, updated_at=? WHERE id=? AND status='processing';")
                bind(timestamp(now), at: 1, to: stmt)
                bind(id, at: 2, to: stmt)
                try expectDone(stmt)
                sqlite3_finalize(stmt)
                guard sqlite3_changes(db) == 1 else {
                    throw DatabaseError.invalidState("Queue item is not processing: \(id)")
                }
            }
        }
    }

    public func getQueueItem(id: String) throws -> QueueItem? {
        try lock.withLock { try getQueueItemUnlocked(id: id) }
    }

    public func listQueue(status: QueueStatus? = nil, limit: Int = 100) throws -> [QueueItem] {
        try lock.withLock {
            let sql: String
            if status == nil {
                sql = "SELECT id,source_text,normalized_text,language,status,attempts,last_error,created_at,updated_at,processing_started_at FROM enrichment_queue ORDER BY created_at LIMIT ?;"
            } else {
                sql = "SELECT id,source_text,normalized_text,language,status,attempts,last_error,created_at,updated_at,processing_started_at FROM enrichment_queue WHERE status=? ORDER BY created_at LIMIT ?;"
            }
            let stmt = try prepare(sql)
            defer { sqlite3_finalize(stmt) }
            var index: Int32 = 1
            if let status {
                bind(status.rawValue, at: index, to: stmt)
                index += 1
            }
            sqlite3_bind_int(stmt, index, Int32(max(1, min(limit, 1000))))
            var items: [QueueItem] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                items.append(try decodeQueue(stmt))
            }
            return items
        }
    }

    private func migrateFavoritesToVersionThree() throws {
        try transaction {
            try execute("ALTER TABLE favorites ADD COLUMN canonical_source TEXT NOT NULL DEFAULT '';")
            let select = try prepare("SELECT id,source_text,source_language,translated_text FROM favorites;")
            var rows: [(String, String, SupportedLanguage, String)] = []
            while sqlite3_step(select) == SQLITE_ROW {
                guard let id = columnString(select, 0),
                      let source = columnString(select, 1),
                      let language = SupportedLanguage(rawValue: columnString(select, 2) ?? ""),
                      let translated = columnString(select, 3) else {
                    sqlite3_finalize(select)
                    throw DatabaseError.sqlite("Invalid favorite row during schema migration")
                }
                rows.append((id, source, language, translated))
            }
            sqlite3_finalize(select)
            for (id, source, language, translated) in rows {
                let canonical = FavoriteCanonicalizer.canonicalSource(source, language: language)
                let normalized = LexicalNormalizer.normalize(canonical)
                let collision = try prepare("SELECT 1 FROM favorites WHERE id<>? AND source_language=? AND normalized_source=? AND translated_text=? LIMIT 1;")
                bind(id, at: 1, to: collision)
                bind(language.rawValue, at: 2, to: collision)
                bind(normalized, at: 3, to: collision)
                bind(translated, at: 4, to: collision)
                let hasCollision = sqlite3_step(collision) == SQLITE_ROW
                sqlite3_finalize(collision)

                let update = try prepare(hasCollision
                    ? "UPDATE favorites SET canonical_source=? WHERE id=?;"
                    : "UPDATE favorites SET canonical_source=?, normalized_source=? WHERE id=?;")
                bind(canonical, at: 1, to: update)
                if hasCollision {
                    bind(id, at: 2, to: update)
                } else {
                    bind(normalized, at: 2, to: update)
                    bind(id, at: 3, to: update)
                }
                try expectDone(update)
                sqlite3_finalize(update)
            }
            try execute("INSERT INTO schema_migrations(version, applied_at) VALUES (3, '\(timestamp(Date()))');")
        }
    }

    private func upsertLexemeUnlocked(_ input: LexemeInput, now: Date = Date()) throws {
        try LexicalValidator.validate(input)
        let content = String(data: try encoder.encode(input.content), encoding: .utf8)!
        let provenance = String(data: try encoder.encode(input.provenance), encoding: .utf8)!
        let normalized = LexicalNormalizer.normalize(input.lemma)
        let pos = input.partOfSpeech?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ts = timestamp(now)
        let sql = """
        INSERT INTO lexemes(id,language,lemma,normalized_lemma,part_of_speech,pronunciation,content_json,provenance_json,content_version,created_at,updated_at)
        VALUES(?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(language,normalized_lemma,part_of_speech) DO UPDATE SET
          lemma=excluded.lemma, pronunciation=excluded.pronunciation,
          content_json=excluded.content_json, provenance_json=excluded.provenance_json,
          content_version=excluded.content_version, updated_at=excluded.updated_at;
        """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bind(UUID().uuidString, at: 1, to: stmt)
        bind(input.language.rawValue, at: 2, to: stmt)
        bind(input.lemma, at: 3, to: stmt)
        bind(normalized, at: 4, to: stmt)
        bind(pos, at: 5, to: stmt)
        bind(input.pronunciation, at: 6, to: stmt)
        bind(content, at: 7, to: stmt)
        bind(provenance, at: 8, to: stmt)
        sqlite3_bind_int(stmt, 9, Int32(input.contentVersion))
        bind(ts, at: 10, to: stmt)
        bind(ts, at: 11, to: stmt)
        try expectDone(stmt)
    }

    private func findFavoriteUnlocked(
        sourceLanguage: SupportedLanguage,
        canonicalSource: String,
        translatedText: String
    ) throws -> FavoriteRecord? {
        let stmt = try prepare("SELECT id,source_text,canonical_source,normalized_source,source_language,translated_text,created_at FROM favorites WHERE source_language=? AND canonical_source=? AND translated_text=? ORDER BY created_at,id LIMIT 1;")
        defer { sqlite3_finalize(stmt) }
        bind(sourceLanguage.rawValue, at: 1, to: stmt)
        bind(canonicalSource, at: 2, to: stmt)
        bind(translatedText, at: 3, to: stmt)
        return sqlite3_step(stmt) == SQLITE_ROW ? try decodeFavorite(stmt) : nil
    }

    private func decodeFavorite(_ stmt: OpaquePointer?) throws -> FavoriteRecord {
        guard let language = SupportedLanguage(rawValue: columnString(stmt, 4) ?? "") else {
            throw DatabaseError.sqlite("Invalid favorite language")
        }
        return .init(
            id: columnString(stmt, 0)!,
            sourceText: columnString(stmt, 1)!,
            canonicalSource: columnString(stmt, 2)!,
            normalizedSource: columnString(stmt, 3)!,
            sourceLanguage: language,
            translatedText: columnString(stmt, 5)!,
            createdAt: date(columnString(stmt, 6)!)
        )
    }

    private func findActiveQueue(language: SupportedLanguage, normalized: String) throws -> QueueItem? {
        let stmt = try prepare("SELECT id,source_text,normalized_text,language,status,attempts,last_error,created_at,updated_at,processing_started_at FROM enrichment_queue WHERE language=? AND normalized_text=? AND status IN ('pending','processing') LIMIT 1;")
        defer { sqlite3_finalize(stmt) }
        bind(language.rawValue, at: 1, to: stmt)
        bind(normalized, at: 2, to: stmt)
        return sqlite3_step(stmt) == SQLITE_ROW ? try decodeQueue(stmt) : nil
    }

    private func getQueueItemUnlocked(id: String) throws -> QueueItem? {
        let stmt = try prepare("SELECT id,source_text,normalized_text,language,status,attempts,last_error,created_at,updated_at,processing_started_at FROM enrichment_queue WHERE id=? LIMIT 1;")
        defer { sqlite3_finalize(stmt) }
        bind(id, at: 1, to: stmt)
        return sqlite3_step(stmt) == SQLITE_ROW ? try decodeQueue(stmt) : nil
    }

    private func decodeLexeme(_ stmt: OpaquePointer?) throws -> LexemeRecord {
        guard let language = SupportedLanguage(rawValue: columnString(stmt, 1) ?? "") else {
            throw DatabaseError.sqlite("Invalid lexeme language")
        }
        let content = try decoder.decode(LexicalContent.self, from: Data((columnString(stmt, 6) ?? "{}").utf8))
        let provenance = try decoder.decode([Provenance].self, from: Data((columnString(stmt, 7) ?? "[]").utf8))
        return .init(
            id: columnString(stmt, 0)!, language: language, lemma: columnString(stmt, 2)!,
            normalizedLemma: columnString(stmt, 3)!, partOfSpeech: nilIfEmpty(columnString(stmt, 4)),
            pronunciation: columnString(stmt, 5), content: content, provenance: provenance,
            contentVersion: Int(sqlite3_column_int(stmt, 8)),
            createdAt: date(columnString(stmt, 9)!), updatedAt: date(columnString(stmt, 10)!)
        )
    }

    private func decodeQueue(_ stmt: OpaquePointer?) throws -> QueueItem {
        guard let language = SupportedLanguage(rawValue: columnString(stmt, 3) ?? ""),
              let status = QueueStatus(rawValue: columnString(stmt, 4) ?? "") else {
            throw DatabaseError.sqlite("Invalid queue row")
        }
        return .init(
            id: columnString(stmt, 0)!, sourceText: columnString(stmt, 1)!,
            normalizedText: columnString(stmt, 2)!, language: language, status: status,
            attempts: Int(sqlite3_column_int(stmt, 5)), lastError: columnString(stmt, 6),
            createdAt: date(columnString(stmt, 7)!), updatedAt: date(columnString(stmt, 8)!),
            processingStartedAt: columnString(stmt, 9).map(date)
        )
    }

    private func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE;")
        do {
            let value = try body()
            try execute("COMMIT;")
            return value
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "SQLite error"
            sqlite3_free(error)
            throw DatabaseError.sqlite(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        return stmt
    }

    private func expectDone(_ stmt: OpaquePointer?) throws {
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func bind(_ value: String?, at index: Int32, to stmt: OpaquePointer?) {
        if let value { sqlite3_bind_text(stmt, index, value, -1, sqliteTransient) }
        else { sqlite3_bind_null(stmt, index) }
    }

    private func columnString(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        sqlite3_column_text(stmt, index).map { String(cString: $0) }
    }

    private func scalarText(_ sql: String) throws -> String? {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? columnString(stmt, 0) : nil
    }

    private func scalarInt(_ sql: String) throws -> Int {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    private func timestamp(_ value: Date) -> String { iso.string(from: value) }
    private func date(_ value: String) -> Date { iso.date(from: value) ?? .distantPast }
    private func nilIfEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

private extension NSRecursiveLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
