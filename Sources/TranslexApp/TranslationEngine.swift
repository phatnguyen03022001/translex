import AppKit
import Combine
import Foundation
import SwiftUI
@preconcurrency import Translation
import TranslexCore

struct TranslationResult: Sendable {
    let sourceText: String
    let translatedText: String
    let direction: TranslationDirection
}

enum TranslationEngineError: Error, LocalizedError {
    case undeterminedLanguage
    case unsupportedPair
    case translationCancelled
    case translationInProgress
    case translationFailed(String)

    var errorDescription: String? {
        switch self {
        case .undeterminedLanguage:
            "Could not determine whether the selection is English or Vietnamese."
        case .unsupportedPair:
            "This English/Vietnamese translation pair is unavailable on this Mac."
        case .translationCancelled:
            "Translation download was cancelled."
        case .translationInProgress:
            "A translation is already being prepared."
        case .translationFailed(let message):
            "Translation failed: \(message)"
        }
    }
}

enum TranslationAvailabilityRoute: Equatable {
    case installed
    case downloadCapable
    case unsupported
}

enum TranslationAvailabilityPolicy {
    static func route(_ status: LanguageAvailability.Status) -> TranslationAvailabilityRoute {
        switch status {
        case .installed: .installed
        case .supported: .downloadCapable
        case .unsupported: .unsupported
        @unknown default: .unsupported
        }
    }
}

@MainActor
final class AppleTranslationEngine {
    private let downloadHost = TranslationDownloadSessionHost()

    func translate(_ text: String) async throws -> TranslationResult {
        guard let direction = LanguageDirectionResolver.resolve(text) else {
            throw TranslationEngineError.undeterminedLanguage
        }
        let source = Locale.Language(identifier: direction.source.rawValue)
        let target = Locale.Language(identifier: direction.target.rawValue)
        let availability = LanguageAvailability(preferredStrategy: .lowLatency)

        let translatedText: String
        switch TranslationAvailabilityPolicy.route(await availability.status(from: source, to: target)) {
        case .installed:
            translatedText = try await translateInstalled(text, source: source, target: target)
        case .downloadCapable:
            translatedText = try await downloadHost.translate(text, source: source, target: target)
        case .unsupported:
            throw TranslationEngineError.unsupportedPair
        }

        return .init(sourceText: text, translatedText: translatedText, direction: direction)
    }

    private func translateInstalled(
        _ text: String,
        source: Locale.Language,
        target: Locale.Language
    ) async throws -> String {
        do {
            let session = TranslationSession(
                installedSource: source,
                target: target,
                preferredStrategy: .lowLatency
            )
            defer { session.cancel() }
            return try await session.translate(text).targetText
        } catch {
            throw mapTranslationError(error)
        }
    }
}

@MainActor
private final class TranslationDownloadSessionHost {
    private let state: TranslationTaskState

    init() {
        let state = TranslationTaskState()
        self.state = state
        state.setOnFinished { [weak self] in
            Task { @MainActor in
                await Task.yield()
                self?.state.configuration = nil
                self?.window.orderOut(nil)
            }
        }
    }
    private lazy var hostingController = NSHostingController(
        rootView: TranslationDownloadHostView(state: state)
    )
    private lazy var window: NSWindow = {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 84),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Translex"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.contentViewController = hostingController
        return window
    }()

    func translate(
        _ text: String,
        source: Locale.Language,
        target: Locale.Language
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            guard state.begin(text: text, continuation: continuation) else {
                continuation.resume(throwing: TranslationEngineError.translationInProgress)
                return
            }
            state.configuration = TranslationSession.Configuration(
                source: source,
                target: target,
                preferredStrategy: .lowLatency
            )
            window.center()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }
}

private final class TranslationTaskState: ObservableObject, @unchecked Sendable {
    @Published var configuration: TranslationSession.Configuration?

    private let lock = NSLock()
    private var onFinished: (@Sendable () -> Void)?
    private var pendingText: String?
    private var continuation: CheckedContinuation<String, any Error>?

    func setOnFinished(_ callback: @escaping @Sendable () -> Void) {
        lock.lock()
        onFinished = callback
        lock.unlock()
    }

    func begin(
        text: String,
        continuation: CheckedContinuation<String, any Error>
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard self.continuation == nil else { return false }
        pendingText = text
        self.continuation = continuation
        return true
    }

    func currentText() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return pendingText
    }

    func complete(_ result: Result<String, any Error>) {
        lock.lock()
        let continuation = continuation
        let onFinished = onFinished
        self.continuation = nil
        pendingText = nil
        lock.unlock()
        continuation?.resume(with: result)
        onFinished?()
    }
}

private struct TranslationDownloadHostView: View {
    @ObservedObject var state: TranslationTaskState

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Preparing translation…")
                .font(.system(size: 13))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
        .translationTask(state.configuration) { session in
            guard let text = state.currentText() else { return }
            do {
                try await session.prepareTranslation()
                let response = try await session.translate(text)
                state.complete(.success(response.targetText))
            } catch {
                state.complete(.failure(mapTranslationError(error)))
            }
        }
    }
}

private func mapTranslationError(_ error: Error) -> Error {
    if error is CancellationError || TranslationError.alreadyCancelled ~= error {
        return TranslationEngineError.translationCancelled
    }
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain && nsError.code == CocoaError.userCancelled.rawValue {
        return TranslationEngineError.translationCancelled
    }
    if error.localizedDescription.localizedCaseInsensitiveContains("cancel") {
        return TranslationEngineError.translationCancelled
    }
    return TranslationEngineError.translationFailed(error.localizedDescription)
}
