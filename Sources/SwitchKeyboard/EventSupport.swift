import CoreGraphics
import SwitchKeyboardCore

enum EventSupport {
    // Собственная метка не позволяет повторно обрабатывать сгенерированный ввод.
    static let marker: Int64 = 0x53574B455942

    static func modifiers(_ flags: CGEventFlags) -> ShortcutModifiers {
        var result: ShortcutModifiers = []
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        return result
    }

    static func modifier(for keyCode: UInt16) -> ShortcutModifiers? {
        switch keyCode {
        case 54, 55: return .command
        case 56, 60: return .shift
        case 58, 61: return .option
        case 59, 62: return .control
        default: return nil
        }
    }

    static func isModifierPressed(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        // Младшие биты NX_DEVICE… отличают левую и правую клавиши.
        let mask: UInt64
        switch keyCode {
        case 54: mask = 0x10
        case 55: mask = 0x08
        case 56: mask = 0x02
        case 60: mask = 0x04
        case 58: mask = 0x20
        case 61: mask = 0x40
        case 59: mask = 0x01
        case 62: mask = 0x2000
        default: return false
        }
        return flags.rawValue & mask != 0
    }

    static func text(from event: CGEvent) -> String {
        var count = 0
        event.keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &count, unicodeString: nil)
        guard count > 0, count <= 256 else { return "" }
        var units = [UniChar](repeating: 0, count: count)
        event.keyboardGetUnicodeString(maxStringLength: count, actualStringLength: &count, unicodeString: &units)
        return String(utf16CodeUnits: units, count: count)
    }
}
