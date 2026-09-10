import Foundation
import NaturalLanguage

public enum LanguageDirectionResolver {
    public static func resolve(
        _ text: String,
        nativeLanguage: SupportedLanguage = .vietnamese
    ) -> TranslationDirection? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let words = wordTokens(in: trimmed)
        let markedVietnamese = words.filter(containsVietnameseSpecificCharacters)
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 4)
        let englishScore = hypotheses[.english] ?? 0
        let vietnameseScore = hypotheses[.vietnamese] ?? 0

        if markedVietnamese.isEmpty {
            if recognizer.dominantLanguage == .vietnamese, vietnameseScore >= 0.60 {
                return direction(from: .vietnamese)
            }
            if recognizer.dominantLanguage == .english, englishScore >= 0.10 {
                return direction(from: .english)
            }
            return preferredTargetDirection(nativeLanguage)
        }

        let unmarkedWords = words.filter { !containsVietnameseSpecificCharacters($0) }
        if unmarkedWords.count >= 2 {
            let unmarkedRecognizer = NLLanguageRecognizer()
            unmarkedRecognizer.processString(unmarkedWords.joined(separator: " "))
            let englishFragmentScore = unmarkedRecognizer.languageHypotheses(withMaximum: 3)[.english] ?? 0
            if englishFragmentScore >= 0.75 {
                return preferredTargetDirection(nativeLanguage)
            }
        }

        if recognizer.dominantLanguage == .vietnamese || vietnameseScore >= 0.65 {
            return direction(from: .vietnamese)
        }
        return preferredTargetDirection(nativeLanguage)
    }

    private static func direction(from source: SupportedLanguage) -> TranslationDirection {
        .init(source: source, target: source == .english ? .vietnamese : .english)
    }

    private static func preferredTargetDirection(_ nativeLanguage: SupportedLanguage) -> TranslationDirection {
        direction(from: nativeLanguage == .vietnamese ? .english : .vietnamese)
    }

    private static func wordTokens(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var result: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            result.append(String(text[range]))
            return true
        }
        return result
    }

    private static func containsVietnameseSpecificCharacters(_ text: String) -> Bool {
        let vietnamese = "ăâđêôơưĂÂĐÊÔƠƯáàảãạấầẩẫậắằẳẵặéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵÁÀẢÃẠẤẦẨẪẬẮẰẲẴẶÉÈẺẼẸẾỀỂỄỆÍÌỈĨỊÓÒỎÕỌỐỒỔỖỘỚỜỞỠỢÚÙỦŨỤỨỪỬỮỰÝỲỶỸỴ"
        return text.unicodeScalars.contains { scalar in vietnamese.unicodeScalars.contains(scalar) }
    }
}

public enum LexicalNormalizer {
    public static func normalize(_ text: String) -> String {
        let normalized = text.precomposedStringWithCanonicalMapping.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return normalized.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}


public enum FavoriteCanonicalizer {
    public static func canonicalSource(_ text: String, language: SupportedLanguage) -> String {
        let formatted = formattingNormalized(text)
        guard !formatted.isEmpty else { return "" }

        if language == .english {
            let words = formatted.split(whereSeparator: { $0.isWhitespace })
            if words.count == 1, LexicalClassifier.isCandidate(formatted) {
                if let lemma = englishLemma(formatted) {
                    return LexicalNormalizer.normalize(lemma)
                }
                return LexicalNormalizer.normalize(formatted)
            }
            return formatted
        }

        if LexicalClassifier.isCandidate(formatted) {
            return formatted.lowercased().precomposedStringWithCanonicalMapping
        }
        return formatted
    }

    public static func normalizedIdentity(_ text: String, language: SupportedLanguage) -> String {
        LexicalNormalizer.normalize(canonicalSource(text, language: language))
    }

    private static func formattingNormalized(_ text: String) -> String {
        let composed = text.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return composed.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func englishLemma(_ word: String) -> String? {
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = word
        tagger.setLanguage(.english, range: word.startIndex..<word.endIndex)
        guard let tag = tagger.tag(at: word.startIndex, unit: .word, scheme: .lemma).0 else { return nil }
        let lemma = tag.rawValue.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lemma.isEmpty, !lemma.contains(where: { $0.isWhitespace }) else { return nil }
        return lemma
    }
}

public enum LexicalClassifier {
    public static func isCandidate(_ text: String) -> Bool {
        let value = LexicalNormalizer.normalize(text)
        guard !value.isEmpty, value.count <= 80 else { return false }
        let words = value.split(whereSeparator: { $0.isWhitespace })
        guard (1...6).contains(words.count) else { return false }
        for scalar in value.unicodeScalars {
            if CharacterSet.letters.contains(scalar) || CharacterSet.nonBaseCharacters.contains(scalar) ||
                CharacterSet.whitespaces.contains(scalar) || scalar == "'" || scalar == "’" || scalar == "-" { continue }
            return false
        }
        return true
    }
}

public enum LexicalValidationError: Error, LocalizedError, Equatable {
    case emptyLemma
    case invalidContentVersion
    case incompleteExamples
    case invalidSense
    case invalidCEFR
    public var errorDescription: String? {
        switch self {
        case .emptyLemma: "Lemma must not be empty."
        case .invalidContentVersion: "contentVersion must be positive."
        case .incompleteExamples: "Provide zero or at least two examples."
        case .invalidSense: "Every sense needs an English definition or Vietnamese explanation."
        case .invalidCEFR: "CEFR must be one of A1, A2, B1, B2, C1, C2 when supplied."
        }
    }
}

public enum LexicalValidator {
    public static func validate(_ input: LexemeInput) throws {
        guard !LexicalNormalizer.normalize(input.lemma).isEmpty else { throw LexicalValidationError.emptyLemma }
        guard input.contentVersion > 0 else { throw LexicalValidationError.invalidContentVersion }
        if input.content.examples.count == 1 { throw LexicalValidationError.incompleteExamples }
        if input.content.senses.contains(where: { $0.definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.vietnamese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            throw LexicalValidationError.invalidSense
        }
        if let cefr = input.content.cefrLevel, !["A1", "A2", "B1", "B2", "C1", "C2"].contains(cefr.uppercased()) {
            throw LexicalValidationError.invalidCEFR
        }
    }
}
