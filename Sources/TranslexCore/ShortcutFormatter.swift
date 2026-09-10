public enum ShortcutKeyCatalog {
    public static let names: [UInt32: String] = [
        0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V",
        11:"B", 12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 18:"1", 19:"2", 20:"3",
        21:"4", 22:"6", 23:"5", 24:"=", 25:"9", 26:"7", 27:"-", 28:"8", 29:"0", 30:"]",
        31:"O", 32:"U", 33:"[", 34:"I", 35:"P", 37:"L", 38:"J", 39:"'", 40:"K", 41:";",
        42:"\\", 43:",", 44:"/", 45:"N", 46:"M", 47:".", 48:"Tab", 49:"Space", 50:"`", 51:"Delete", 53:"Esc",
        96:"F5", 97:"F6", 98:"F7", 99:"F3", 100:"F8", 101:"F9", 103:"F11", 109:"F10",
        111:"F12", 115:"Home", 116:"Page Up", 117:"Forward Delete", 118:"F4", 119:"End", 120:"F2",
        121:"Page Down", 122:"F1", 123:"←", 124:"→", 125:"↓", 126:"↑"
    ]

    public static func isSupported(_ keyCode: UInt32) -> Bool { names[keyCode] != nil }
    public static func name(for keyCode: UInt32) -> String? { names[keyCode] }
}

public enum ShortcutFormatter {
    public static func display(_ shortcut: ShortcutDefinition) -> String {
        var result = ""
        if shortcut.modifiers.contains(.control) { result += "⌃" }
        if shortcut.modifiers.contains(.option) { result += "⌥" }
        if shortcut.modifiers.contains(.shift) { result += "⇧" }
        if shortcut.modifiers.contains(.command) { result += "⌘" }
        result += ShortcutKeyCatalog.name(for: shortcut.keyCode) ?? "Key\(shortcut.keyCode)"
        return result
    }
}
