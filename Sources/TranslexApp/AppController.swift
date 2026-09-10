import AppKit
import TranslexCore

enum SelectionFeedbackKind: Equatable {
    case noSelectionToast
    case accessibilityPermission
    case error
}

enum SelectionFeedbackPolicy {
    static func kind(for error: SelectionError) -> SelectionFeedbackKind {
        switch error {
        case .noSelection, .copyFailed: .noSelectionToast
        case .accessibilityRequired: .accessibilityPermission
        }
    }
}

@MainActor
final class AppController {
    let settings: SettingsStore
    let selection = SelectionProvider()
    let speech = SpeechService()
    let popup = PopupController()
    let database: DatabaseStore
    private let translator = AppleTranslationEngine()

    init(settings: SettingsStore = SettingsStore()) throws {
        self.settings = settings
        self.database = try DatabaseStore()
    }

    func translateSelection() {
        let selected: SelectedText
        do {
            selected = try selection.selectedText()
        } catch {
            showError(error)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await translator.translate(selected.text)
                let detail = try lexicalDetail(for: result)
                popup.show(
                    source: result.sourceText,
                    primary: result.translatedText,
                    detail: detail,
                    anchor: selected.anchor,
                    duration: settings.popupDuration,
                    favoriteAction: { [weak self] in
                        guard let self else { return }
                        _ = try self.database.saveFavorite(
                            sourceText: result.sourceText,
                            sourceLanguage: result.direction.source,
                            translatedText: result.translatedText
                        )
                    }
                )
            } catch {
                showError(error, anchor: selected.anchor)
            }
        }
    }

    func speakSelection() {
        let selected: SelectedText
        do {
            selected = try selection.selectedText()
        } catch {
            showError(error)
            return
        }
        guard LanguageDirectionResolver.resolve(selected.text)?.source == .english else {
            popup.show(
                source: selected.text,
                primary: "Select English text to speak.",
                anchor: selected.anchor,
                duration: settings.popupDuration
            )
            return
        }
        do {
            try speech.speakEnglish(
                selected.text,
                preferredIdentifier: settings.englishVoiceIdentifier
            )
        } catch {
            showError(error, anchor: selected.anchor)
        }
    }

    private func lexicalDetail(for result: TranslationResult) throws -> String? {
        guard LexicalClassifier.isCandidate(result.sourceText) else { return nil }
        let normalized = LexicalNormalizer.normalize(result.sourceText)
        if let record = try database.getLexeme(
            language: result.direction.source,
            normalizedLemma: normalized
        ) {
            var parts: [String] = []
            if let pronunciation = record.pronunciation { parts.append(pronunciation) }
            if let sense = record.content.senses.first {
                let value = result.direction.source == .english ? sense.definition : sense.vietnamese
                if !value.isEmpty { parts.append(value) }
            }
            return parts.isEmpty ? "Lexicon entry available" : parts.joined(separator: " · ")
        }
        let enqueue = try database.enqueue(
            sourceText: result.sourceText,
            language: result.direction.source
        )
        return enqueue.created ? "Added to enrichment queue" : "Enrichment already pending"
    }

    private func showError(_ error: Error, anchor: NSPoint = NSEvent.mouseLocation) {
        if let selectionError = error as? SelectionError {
            switch SelectionFeedbackPolicy.kind(for: selectionError) {
            case .noSelectionToast:
                popup.showToast("No text selected", anchor: anchor)
                return
            case .accessibilityPermission:
                showAccessibilityPermissionAlert(selectionError)
                return
            case .error:
                break
            }
        }
        popup.show(
            source: nil,
            primary: error.localizedDescription,
            anchor: anchor,
            duration: settings.popupDuration
        )
    }

    private func showAccessibilityPermissionAlert(_ error: SelectionError) {
        popup.dismiss()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = [error.errorDescription, error.recoverySuggestion]
            .compactMap { $0 }
            .joined(separator: "\n\n")
        alert.addButton(withTitle: "Request Access")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            _ = selection.requestAccessibilityPermission()
        }
    }
}
