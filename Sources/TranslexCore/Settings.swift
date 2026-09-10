import Foundation

public struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let command = ShortcutModifiers(rawValue: 1 << 0)
    public static let option = ShortcutModifiers(rawValue: 1 << 1)
    public static let control = ShortcutModifiers(rawValue: 1 << 2)
    public static let shift = ShortcutModifiers(rawValue: 1 << 3)
}

public struct ShortcutDefinition: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: ShortcutModifiers
    public init(keyCode: UInt32, modifiers: ShortcutModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum ShortcutValidationError: Error, LocalizedError, Equatable {
    case missingPrimaryModifier
    case invalidKeyCode
    case duplicateActions
    case reservedSystemShortcut

    public var errorDescription: String? {
        switch self {
        case .missingPrimaryModifier: "Shortcut needs Command, Option, or Control."
        case .invalidKeyCode: "Shortcut key code is invalid."
        case .duplicateActions: "Translate and Speak shortcuts must differ."
        case .reservedSystemShortcut: "This shortcut is reserved by macOS and cannot be used by Translex."
        }
    }
}
public enum ShortcutReservedPolicy {
    public static func isReserved(_ shortcut: ShortcutDefinition) -> Bool {
        let commandSpace = ShortcutDefinition(keyCode: 49, modifiers: [.command])
        let commandTab = ShortcutDefinition(keyCode: 48, modifiers: [.command])
        let forceQuit = ShortcutDefinition(keyCode: 53, modifiers: [.command, .option])
        return shortcut == commandSpace || shortcut == commandTab || shortcut == forceQuit
    }
}

public enum ShortcutValidator {
    public static func validate(_ shortcut: ShortcutDefinition) throws {
        guard ShortcutKeyCatalog.isSupported(shortcut.keyCode) else { throw ShortcutValidationError.invalidKeyCode }
        let primary: ShortcutModifiers = [.command, .option, .control]
        guard !shortcut.modifiers.intersection(primary).isEmpty else {
            throw ShortcutValidationError.missingPrimaryModifier
        }
        guard !ShortcutReservedPolicy.isReserved(shortcut) else {
            throw ShortcutValidationError.reservedSystemShortcut
        }
    }

    public static func validatePair(translate: ShortcutDefinition, speak: ShortcutDefinition) throws {
        try validate(translate)
        try validate(speak)
        guard translate != speak else { throw ShortcutValidationError.duplicateActions }
    }
}

public final class SettingsStore: @unchecked Sendable {
    private enum Key {
        static let translateShortcut = "translateShortcut"
        static let speakShortcut = "speakShortcut"
        static let popupDuration = "popupDuration"
        static let voiceIdentifier = "englishVoiceIdentifier"
        static let nativeLanguage = "nativeLanguage"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var translateShortcut: ShortcutDefinition {
        get { readShortcut(Key.translateShortcut) ?? .init(keyCode: 18, modifiers: [.command]) }
        set { try? setTranslateShortcut(newValue) }
    }
    public var speakShortcut: ShortcutDefinition {
        get { readShortcut(Key.speakShortcut) ?? .init(keyCode: 19, modifiers: [.command]) }
        set { try? setSpeakShortcut(newValue) }
    }

    public func setTranslateShortcut(_ value: ShortcutDefinition) throws {
        try ShortcutValidator.validate(value)
        try writeShortcut(value, key: Key.translateShortcut)
    }

    public func setSpeakShortcut(_ value: ShortcutDefinition) throws {
        try ShortcutValidator.validate(value)
        try writeShortcut(value, key: Key.speakShortcut)
    }

    public var popupDuration: Double {
        get { defaults.object(forKey: Key.popupDuration) == nil ? 4.0 : defaults.double(forKey: Key.popupDuration) }
        set { defaults.set(min(max(newValue, 2.0), 15.0), forKey: Key.popupDuration) }
    }

    public var englishVoiceIdentifier: String? {
        get { defaults.string(forKey: Key.voiceIdentifier) }
        set { defaults.set(newValue, forKey: Key.voiceIdentifier) }
    }

    public var nativeLanguage: SupportedLanguage {
        get {
            guard let raw = defaults.string(forKey: Key.nativeLanguage),
                  let value = SupportedLanguage(rawValue: raw) else { return .vietnamese }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: Key.nativeLanguage) }
    }

    private func readShortcut(_ key: String) -> ShortcutDefinition? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(ShortcutDefinition.self, from: data)
    }
    private func writeShortcut(_ value: ShortcutDefinition, key: String) throws {
        defaults.set(try encoder.encode(value), forKey: key)
    }
}
