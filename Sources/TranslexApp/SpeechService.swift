import AVFoundation
import Foundation

enum SpeechError: Error, LocalizedError {
    case noEnglishVoice

    var errorDescription: String? {
        "No installed English system voice is available."
    }
}

@MainActor
final class SpeechService {
    private let synthesizer = AVSpeechSynthesizer()

    var availableEnglishVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix("en") }
            .sorted { lhs, rhs in
                if lhs.language == rhs.language { return lhs.name < rhs.name }
                return lhs.language < rhs.language
            }
    }

    func resolvedVoice(preferredIdentifier: String?) -> AVSpeechSynthesisVoice? {
        let voices = availableEnglishVoices
        if let preferredIdentifier,
           let preferred = voices.first(where: { $0.identifier == preferredIdentifier }) {
            return preferred
        }
        return voices.first(where: { $0.language == "en-US" }) ?? voices.first
    }

    func speakEnglish(_ text: String, preferredIdentifier: String?) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let voice = resolvedVoice(preferredIdentifier: preferredIdentifier) else {
            throw SpeechError.noEnglishVoice
        }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
}
