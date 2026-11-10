import AppKit
import Carbon
import SwitchKeyboardCore

struct InputSourceSelection {
    var layout: KeyboardLayoutSnapshot?
    var message: String?
}

@MainActor
enum InputSourceController {
    static func select(
        _ language: KeyboardLanguage,
        for pid: pid_t,
        isValid: () -> Bool
    ) -> InputSourceSelection {
        guard isValid(), NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            return InputSourceSelection(message: "Текст преобразован. Язык не переключён: фокус изменился.")
        }
        // TIS выбирает последний использованный включённый источник указанного языка.
        // Все вызовы TextInputSources выполняются только в главном потоке.
        guard let reference = TISCopyInputSourceForLanguage(language.rawValue as CFString) else {
            let name = language == .english ? "английский" : "русский"
            return InputSourceSelection(
                message: "Текст преобразован. Добавьте \(name) источник ввода в настройках клавиатуры macOS."
            )
        }
        let source = reference.takeRetainedValue()
        guard isValid(), NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            return InputSourceSelection(message: "Текст преобразован. Язык не переключён: фокус изменился.")
        }
        let status = TISSelectInputSource(source)
        guard status == noErr else {
            return InputSourceSelection(message: "Текст преобразован. macOS не переключила язык: код \(status).")
        }
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return InputSourceSelection()
        }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return InputSourceSelection(layout: KeyboardLayoutSnapshot(data: data))
    }
}
