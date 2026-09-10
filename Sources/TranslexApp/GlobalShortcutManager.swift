import Carbon
import Foundation
import TranslexCore

private let translexHotKeySignature: OSType = 0x54584C58

enum ShortcutAction: UInt32 {
    case translate = 1
    case speak = 2
}

enum ShortcutRegistrationError: Error, LocalizedError {
    case eventHandlerInstallationFailed(OSStatus)
    case registrationFailed(ShortcutAction, OSStatus)

    var errorDescription: String? {
        switch self {
        case .eventHandlerInstallationFailed(let status):
            "Could not install the global shortcut handler (OSStatus \(status))."
        case .registrationFailed(let action, let status):
            "Could not register \(action == .translate ? "Translate" : "Speak") shortcut (OSStatus \(status)). It may conflict with another global shortcut."
        }
    }
}

@MainActor
final class GlobalShortcutManager {
    private var refs: [ShortcutAction: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private var callbacks: [ShortcutAction: () -> Void] = [:]
    var isSuppressed = false

    init() throws {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard result == noErr,
                      hotKeyID.signature == translexHotKeySignature,
                      let action = ShortcutAction(rawValue: hotKeyID.id)
                else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<GlobalShortcutManager>
                    .fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in manager.fire(action) }
                return noErr
            },
            1,
            &spec,
            context,
            &eventHandler
        )
        guard status == noErr else {
            throw ShortcutRegistrationError.eventHandlerInstallationFailed(status)
        }
    }

    func shutdown() {
        unregisterAll()
        callbacks.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    func register(
        translate: ShortcutDefinition,
        speak: ShortcutDefinition,
        onTranslate: @escaping () -> Void,
        onSpeak: @escaping () -> Void
    ) throws {
        try ShortcutValidator.validatePair(translate: translate, speak: speak)
        unregisterAll()
        callbacks = [.translate: onTranslate, .speak: onSpeak]
        do {
            try registerOne(.translate, definition: translate)
            try registerOne(.speak, definition: speak)
        } catch {
            unregisterAll()
            callbacks.removeAll()
            throw error
        }
    }

    func unregisterAll() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
    }

    private func registerOne(
        _ action: ShortcutAction,
        definition: ShortcutDefinition
    ) throws {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: translexHotKeySignature, id: action.rawValue)
        let status = RegisterEventHotKey(
            definition.keyCode,
            carbonModifiers(definition.modifiers),
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            throw ShortcutRegistrationError.registrationFailed(action, status)
        }
        refs[action] = ref
    }

    private func fire(_ action: ShortcutAction) {
        guard !isSuppressed else { return }
        callbacks[action]?()
    }

    private func carbonModifiers(_ modifiers: ShortcutModifiers) -> UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }
}
