import Foundation

public struct ShortcutModifiers: OptionSet, Codable, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let command = ShortcutModifiers(rawValue: 1)
    public static let option = ShortcutModifiers(rawValue: 2)
    public static let control = ShortcutModifiers(rawValue: 4)
    public static let shift = ShortcutModifiers(rawValue: 8)
}

public struct Shortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var modifiers: ShortcutModifiers
    public var isModifierOnly: Bool

    public init(keyCode: UInt16, modifiers: ShortcutModifiers, isModifierOnly: Bool = false) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isModifierOnly = isModifierOnly
    }

    public static let leftOption = Shortcut(keyCode: 58, modifiers: .option, isModifierOnly: true)

    public var displayName: String {
        if isModifierOnly {
            return Self.modifierNames[keyCode] ?? "Клавиша \(keyCode)"
        }
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols + (Self.keyNames[keyCode] ?? "Клавиша \(keyCode)")
    }

    private static let modifierNames: [UInt16: String] = [
        54: "Правый Command", 55: "Левый Command", 56: "Левый Shift", 58: "Левый Option",
        59: "Левый Control", 60: "Правый Shift", 61: "Правый Option", 62: "Правый Control", 63: "Fn"
    ]

    private static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "−", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
        47: ".", 48: "⇥", 49: "Пробел", 50: "`", 51: "⌫", 53: "⎋", 65: ".", 67: "*",
        69: "+", 71: "Clear", 75: "/", 76: "⌤", 78: "−", 81: "=", 82: "0", 83: "1", 84: "2",
        85: "3", 86: "4", 87: "5", 88: "6", 89: "7", 91: "8", 92: "9", 96: "F5", 97: "F6",
        98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 109: "F10", 111: "F12",
        114: "Help", 115: "↖", 116: "⇞", 117: "⌦", 118: "F4", 119: "↘", 120: "F2",
        121: "⇟", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
}
