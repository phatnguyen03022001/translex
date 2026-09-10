import TranslexCore

struct ShortcutPair: Equatable, Sendable {
    let translate: ShortcutDefinition
    let speak: ShortcutDefinition
}

@MainActor
struct ShortcutApplyCoordinator {
    let current: () -> ShortcutPair
    let register: (ShortcutPair) throws -> Void
    let persist: (ShortcutPair) throws -> Void
    var onRollbackFailure: ((Error) -> Void)? = nil

    func apply(_ pair: ShortcutPair) throws {
        try ShortcutValidator.validatePair(translate: pair.translate, speak: pair.speak)
        let previous = current()
        do {
            try register(pair)
        } catch {
            let original = error
            do { try register(previous) } catch { onRollbackFailure?(error) }
            throw original
        }
        do {
            try persist(pair)
        } catch {
            let original = error
            do { try register(previous) } catch { onRollbackFailure?(error) }
            throw original
        }
    }
}
