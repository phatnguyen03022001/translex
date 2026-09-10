import Testing
@testable import TranslexCore

@Test func rejectsSingleExampleEnrichment() throws {
    let payload = LexemeInput(
        language: .english,
        lemma: "improve",
        partOfSpeech: "verb",
        pronunciation: nil,
        content: LexicalContent(
            senses: [.init(definition: "to make something better", vietnamese: "cải thiện", register: "neutral")],
            examples: [.init(english: "We need to improve the system.", vietnamese: "Chúng ta cần cải thiện hệ thống.")]
        ),
        provenance: [.init(source: "test", reference: nil)],
        contentVersion: 1
    )
    #expect(throws: LexicalValidationError.self) {
        try LexicalValidator.validate(payload)
    }
}
