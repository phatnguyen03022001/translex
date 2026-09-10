import Foundation
import SQLite3
import Testing
@testable import TranslexCore

@Test func versionTwoFavoritesMigrateToCanonicalSourceWithoutDataLoss() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appendingPathComponent("v2.sqlite3").path
    try createVersionTwoFavoriteDatabase(at: path)

    let store = try DatabaseStore(path: path)
    #expect(try store.validateDatabase().message.contains("schema=3"))
    let favorites = try store.listFavorites()
    #expect(favorites.count == 2)
    #expect(favorites[0].sourceText == "Running")
    #expect(favorites[0].canonicalSource == "run")
    #expect(favorites[0].normalizedSource == "run")
    #expect(favorites[1].sourceText == "CẢI THIỆN")
    #expect(favorites[1].canonicalSource == "cải thiện")
}

@Test func favoriteSaveIsIdempotentAcrossCanonicalEnglishForms() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try DatabaseStore(path: dir.appendingPathComponent("favorites.sqlite3").path)
    let first = try store.saveFavorite(sourceText: "Running", sourceLanguage: .english, translatedText: "Chạy")
    let second = try store.saveFavorite(sourceText: "run", sourceLanguage: .english, translatedText: "Chạy")
    #expect(first.id == second.id)
    #expect(try store.listFavorites().count == 1)
}

private func createVersionTwoFavoriteDatabase(at path: String) throws {
    var db: OpaquePointer?
    guard sqlite3_open(path, &db) == SQLITE_OK, let db else { throw NSError(domain: "test", code: 1) }
    defer { sqlite3_close(db) }
    let sql = """
    CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL);
    CREATE TABLE favorites (
      id TEXT PRIMARY KEY, source_text TEXT NOT NULL, normalized_source TEXT NOT NULL,
      source_language TEXT NOT NULL CHECK(source_language IN ('en','vi')),
      translated_text TEXT NOT NULL, created_at TEXT NOT NULL,
      UNIQUE(source_language, normalized_source, translated_text));
    INSERT INTO schema_migrations VALUES(1,'1970-01-01T00:00:00Z');
    INSERT INTO schema_migrations VALUES(2,'1970-01-01T00:00:01Z');
    INSERT INTO favorites VALUES('en-1','Running','running','en','Chạy','1970-01-01T00:00:02Z');
    INSERT INTO favorites VALUES('vi-1','CẢI THIỆN','cải thiện','vi','Improve','1970-01-01T00:00:01Z');
    """
    var error: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
        let message = error.map { String(cString: $0) } ?? "sqlite error"
        sqlite3_free(error)
        throw NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
