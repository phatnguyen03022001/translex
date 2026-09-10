import Foundation
import NaturalLanguage

public enum LanguageDirectionResolver {
    public static func resolve(_ text: String) -> TranslationDirection? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if containsVietnameseSpecificCharacters(trimmed) {
            return .init(source: .vietnamese, target: .english)
        }
        if let language = NLLanguageRecognizer.dominantLanguage(for: trimmed) {
            if language == .vietnamese { return .init(source: .vietnamese, target: .english) }
            if language == .english { return .init(source: .english, target: .vietnamese) }
        }
        let letters = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        if !letters.isEmpty && letters.count == trimmed.unicodeScalars.filter({ !$0.properties.isWhitespace }).count {
            return .init(source: .english, target: .vietnamese)
        }
        return nil
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
