import Foundation
import SQLite3
import Testing
@testable import TranslexCore

private func makeFavoriteStore() throws -> DatabaseStore {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return try DatabaseStore(path: dir.appendingPathComponent("test.sqlite3").path)
}

@Test func favoriteInsertIsIdempotentAndListsNewestFirst() throws {
    let store = try makeFavoriteStore()
    let old = try store.saveFavorite(
        sourceText: "Hello", sourceLanguage: .english, translatedText: "Xin chào",
        now: Date(timeIntervalSince1970: 10)
    )
    let duplicate = try store.saveFavorite(
        sourceText: " hello ", sourceLanguage: .english, translatedText: "Xin chào",
        now: Date(timeIntervalSince1970: 20)
    )
    let newest = try store.saveFavorite(
        sourceText: "Good morning", sourceLanguage: .english, translatedText: "Chào buổi sáng",
        now: Date(timeIntervalSince1970: 30)
    )

    #expect(old.id == duplicate.id)
    let favorites = try store.listFavorites()
    #expect(favorites.map(\.id) == [newest.id, old.id])
}

@Test func favoriteCanBeDeleted() throws {
    let store = try makeFavoriteStore()
    let favorite = try store.saveFavorite(
        sourceText: "Thanks", sourceLanguage: .english, translatedText: "Cảm ơn"
    )
    #expect(try store.deleteFavorite(id: favorite.id))
    #expect(try store.listFavorites().isEmpty)
    #expect(!(try store.deleteFavorite(id: favorite.id)))
}

@Test func versionOneDataSurvivesFavoritesMigration() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appendingPathComponent("migration.sqlite3").path
    try createVersionOneDatabase(at: path)

    let store = try DatabaseStore(path: path)
    #expect(try store.validateDatabase().message.contains("schema=2"))
    #expect(try store.getLexeme(language: .english, normalizedLemma: "hello")?.lemma == "hello")
    #expect(try store.listQueue().map(\.sourceText) == ["world"])
    #expect(try store.listFavorites().isEmpty)
}

private func createVersionOneDatabase(at path: String) throws {
    var db: OpaquePointer?
    guard sqlite3_open(path, &db) == SQLITE_OK, let db else { throw NSError(domain: "test", code: 1) }
    defer { sqlite3_close(db) }
    let content = #"{"senses":[],"examples":[],"synonyms":[],"antonyms":[],"wordFamily":[],"inflections":[],"collocations":[],"grammarPatterns":[],"usageNotes":[],"commonMistakes":[],"relatedVocabulary":[]}"#
    let sql = """
    CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);
    CREATE TABLE lexemes (
      id TEXT PRIMARY KEY, language TEXT NOT NULL CHECK(language IN ('en','vi')),
      lemma TEXT NOT NULL, normalized_lemma TEXT NOT NULL, part_of_speech TEXT NOT NULL DEFAULT '', pronunciation TEXT,
      content_json TEXT NOT NULL, provenance_json TEXT NOT NULL, content_version INTEGER NOT NULL CHECK(content_version > 0),
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, UNIQUE(language, normalized_lemma, part_of_speech));
    CREATE TABLE enrichment_queue (
      id TEXT PRIMARY KEY, source_text TEXT NOT NULL, normalized_text TEXT NOT NULL,
      language TEXT NOT NULL CHECK(language IN ('en','vi')), status TEXT NOT NULL CHECK(status IN ('pending','processing','ready','failed')),
      attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, processing_started_at TEXT);
    CREATE UNIQUE INDEX uq_queue_active ON enrichment_queue(language, normalized_text) WHERE status IN ('pending','processing');
    INSERT INTO schema_migrations VALUES(1,'1970-01-01T00:00:00Z');
    INSERT INTO lexemes VALUES('lex-1','en','hello','hello','',NULL,'\(content)','[]',1,'1970-01-01T00:00:00Z','1970-01-01T00:00:00Z');
    INSERT INTO enrichment_queue VALUES('queue-1','world','world','en','pending',0,NULL,'1970-01-01T00:00:00Z','1970-01-01T00:00:00Z',NULL);
    """
    var error: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
        let message = error.map { String(cString: $0) } ?? "sqlite error"
        sqlite3_free(error)
        throw NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
