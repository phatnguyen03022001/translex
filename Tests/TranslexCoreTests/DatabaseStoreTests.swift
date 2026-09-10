import Foundation
import Testing
@testable import TranslexCore

private func makeStore() throws -> DatabaseStore {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return try DatabaseStore(path: dir.appendingPathComponent("test.sqlite3").path)
}

private func validLexeme(_ lemma: String = "improve") -> LexemeInput {
    LexemeInput(
        language: .english,
        lemma: lemma,
        partOfSpeech: "verb",
        pronunciation: "/ɪmˈpruːv/",
        content: LexicalContent(
            senses: [.init(definition: "to make something better", vietnamese: "cải thiện", register: "neutral")],
            examples: [
                .init(english: "We need to improve the system.", vietnamese: "Chúng ta cần cải thiện hệ thống."),
                .init(english: "Her results improved quickly.", vietnamese: "Kết quả của cô ấy cải thiện nhanh chóng.")
            ],
            synonyms: ["enhance"], antonyms: ["worsen"], wordFamily: ["improvement"],
            collocations: ["improve performance"], grammarPatterns: ["improve + noun"],
            usageNotes: ["Can be transitive or intransitive."], commonMistakes: [], relatedVocabulary: ["better"]
        ),
        provenance: [.init(source: "unit-test", reference: "fixture")], contentVersion: 1
    )
}

@Test func schemaAndLexemeRoundTrip() throws {
    let store = try makeStore()
    #expect(try store.validateDatabase().isValid)
    try store.upsertLexeme(validLexeme())
    let record = try store.getLexeme(language: .english, normalizedLemma: "improve")
    #expect(record?.lemma == "improve")
    #expect(record?.content.examples.count == 2)
}

@Test func queuePreventsDuplicateActiveItemsAndCompletesAtomically() throws {
    let store = try makeStore()
    let first = try store.enqueue(sourceText: "Improve", language: .english)
    let second = try store.enqueue(sourceText: " improve ", language: .english)
    #expect(first.item.id == second.item.id)
    #expect(first.created)
    #expect(!second.created)
    let claimed = try #require(try store.claimNext(staleAfter: 60))
    #expect(claimed.status == .processing)
    #expect(claimed.attempts == 1)
    try store.completeQueueItem(id: claimed.id, lexeme: validLexeme())
    #expect(try store.getQueueItem(id: claimed.id)?.status == .ready)
    #expect(try store.getLexeme(language: .english, normalizedLemma: "improve") != nil)
}

@Test func staleProcessingIsRecoveredForRetry() throws {
    let store = try makeStore()
    let queued = try store.enqueue(sourceText: "improve", language: .english).item
    _ = try #require(try store.claimNext(staleAfter: 60, now: Date(timeIntervalSince1970: 10)))
    let reclaimed = try #require(try store.claimNext(staleAfter: 60, now: Date(timeIntervalSince1970: 100)))
    #expect(reclaimed.id == queued.id)
    #expect(reclaimed.attempts == 2)
}
