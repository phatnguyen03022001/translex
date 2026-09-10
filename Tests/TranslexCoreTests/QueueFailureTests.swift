import Foundation
import Testing
@testable import TranslexCore

@Test func failingClaimedQueueItemPersistsFailureState() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = try DatabaseStore(path: dir.appendingPathComponent("test.sqlite3").path)
    let queued = try store.enqueue(sourceText: "improve", language: .english).item
    let claimed = try #require(try store.claimNext())
    #expect(claimed.id == queued.id)
    try store.failQueueItem(id: claimed.id, error: "source unavailable")
    let failed = try #require(try store.getQueueItem(id: claimed.id))
    #expect(failed.status == .failed)
    #expect(failed.lastError == "source unavailable")
}
