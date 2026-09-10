import Foundation

public enum SupportedLanguage: String, Codable, CaseIterable, Sendable {
    case english = "en"
    case vietnamese = "vi"
}

public struct TranslationDirection: Equatable, Sendable {
    public let source: SupportedLanguage
    public let target: SupportedLanguage
    public init(source: SupportedLanguage, target: SupportedLanguage) {
        self.source = source
        self.target = target
    }
}

public struct LexicalSense: Codable, Equatable, Sendable {
    public var definition: String
    public var vietnamese: String
    public var register: String?
    public init(definition: String, vietnamese: String, register: String? = nil) {
        self.definition = definition; self.vietnamese = vietnamese; self.register = register
    }
}

public struct LexicalExample: Codable, Equatable, Sendable {
    public var english: String
    public var vietnamese: String
    public init(english: String, vietnamese: String) { self.english = english; self.vietnamese = vietnamese }
}

public struct Provenance: Codable, Equatable, Sendable {
    public var source: String
    public var reference: String?
    public init(source: String, reference: String? = nil) { self.source = source; self.reference = reference }
}

public struct LexicalContent: Codable, Equatable, Sendable {
    public var senses: [LexicalSense]
    public var examples: [LexicalExample]
    public var synonyms: [String]
    public var antonyms: [String]
    public var wordFamily: [String]
    public var inflections: [String]
    public var collocations: [String]
    public var grammarPatterns: [String]
    public var usageNotes: [String]
    public var commonMistakes: [String]
    public var relatedVocabulary: [String]
    public var cefrLevel: String?
    public var frequency: String?

    public init(
        senses: [LexicalSense] = [], examples: [LexicalExample] = [], synonyms: [String] = [],
        antonyms: [String] = [], wordFamily: [String] = [], inflections: [String] = [],
        collocations: [String] = [], grammarPatterns: [String] = [], usageNotes: [String] = [],
        commonMistakes: [String] = [], relatedVocabulary: [String] = [], cefrLevel: String? = nil,
        frequency: String? = nil
    ) {
        self.senses = senses; self.examples = examples; self.synonyms = synonyms; self.antonyms = antonyms
        self.wordFamily = wordFamily; self.inflections = inflections; self.collocations = collocations
        self.grammarPatterns = grammarPatterns; self.usageNotes = usageNotes; self.commonMistakes = commonMistakes
        self.relatedVocabulary = relatedVocabulary; self.cefrLevel = cefrLevel; self.frequency = frequency
    }
}

public struct LexemeInput: Codable, Equatable, Sendable {
    public var language: SupportedLanguage
    public var lemma: String
    public var partOfSpeech: String?
    public var pronunciation: String?
    public var content: LexicalContent
    public var provenance: [Provenance]
    public var contentVersion: Int
    public init(language: SupportedLanguage, lemma: String, partOfSpeech: String? = nil, pronunciation: String? = nil,
                content: LexicalContent, provenance: [Provenance] = [], contentVersion: Int = 1) {
        self.language = language; self.lemma = lemma; self.partOfSpeech = partOfSpeech; self.pronunciation = pronunciation
        self.content = content; self.provenance = provenance; self.contentVersion = contentVersion
    }
}

public struct LexemeRecord: Codable, Equatable, Sendable {
    public var id: String
    public var language: SupportedLanguage
    public var lemma: String
    public var normalizedLemma: String
    public var partOfSpeech: String?
    public var pronunciation: String?
    public var content: LexicalContent
    public var provenance: [Provenance]
    public var contentVersion: Int
    public var createdAt: Date
    public var updatedAt: Date
}


public struct FavoriteRecord: Codable, Equatable, Sendable {
    public var id: String
    public var sourceText: String
    public var canonicalSource: String
    public var normalizedSource: String
    public var sourceLanguage: SupportedLanguage
    public var translatedText: String
    public var createdAt: Date

    public init(
        id: String, sourceText: String, canonicalSource: String, normalizedSource: String,
        sourceLanguage: SupportedLanguage, translatedText: String, createdAt: Date
    ) {
        self.id = id
        self.sourceText = sourceText
        self.canonicalSource = canonicalSource
        self.normalizedSource = normalizedSource
        self.sourceLanguage = sourceLanguage
        self.translatedText = translatedText
        self.createdAt = createdAt
    }
}

public enum QueueStatus: String, Codable, Sendable { case pending, processing, ready, failed }

public struct QueueItem: Codable, Equatable, Sendable {
    public var id: String
    public var sourceText: String
    public var normalizedText: String
    public var language: SupportedLanguage
    public var status: QueueStatus
    public var attempts: Int
    public var lastError: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var processingStartedAt: Date?
}

public struct EnqueueResult: Codable, Equatable, Sendable {
    public var item: QueueItem
    public var created: Bool
}

public struct DatabaseValidationResult: Codable, Equatable, Sendable {
    public var isValid: Bool
    public var message: String
}
