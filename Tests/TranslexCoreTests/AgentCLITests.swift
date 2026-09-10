import Foundation
import Testing
@testable import TranslexCore

private func cliStore() throws -> DatabaseStore {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return try DatabaseStore(path: dir.appendingPathComponent("cli.sqlite3").path)
}

@Test func cliRejectsMalformedLexemeJSON() throws {
    let cli = AgentCLI(store: try cliStore())
    #expect(throws: AgentCLIError.self) {
        _ = try cli.execute(arguments: ["lexeme", "upsert"], stdin: Data("{bad".utf8))
    }
}

@Test func cliCanClaimAndFailQueuedItem() throws {
    let store = try cliStore()
    let queued = try store.enqueue(sourceText: "improve", language: .english).item
    let cli = AgentCLI(store: store)
    let claim = try cli.execute(arguments: ["queue", "claim"], stdin: nil)
    #expect(claim.exitCode == 0)
    #expect(claim.stdout.contains(queued.id))
    let failure = try cli.execute(
        arguments: ["queue", "fail", queued.id, "temporary failure"],
        stdin: nil
    )
    #expect(failure.exitCode == 0)
    #expect(try store.getQueueItem(id: queued.id)?.status == .failed)
}
