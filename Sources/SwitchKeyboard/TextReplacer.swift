import AppKit
import ApplicationServices
import SwitchKeyboardCore

struct ReplacementPlan {
    var events: [CGEvent] = []
    var usedRecentText = false
    var text = ""
    var message: String

    var isReady: Bool { !events.isEmpty }
}

final class TextReplacer {
    // AX не выполняется в callback перехвата клавиш. Лимит относится к каждому IPC-запросу.
    private let timeout: Float = 0.04
    private let source = CGEventSource(stateID: .privateState)

    func prepare(recentText: String, pid: pid_t, isValid: () -> Bool) -> ReplacementPlan {
        guard isValid(), isFrontmost(pid), AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
            return ReplacementPlan(message: "Замена отменена: фокус изменился или нет системных разрешений.")
        }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        guard let element = focusedElement(in: app) else {
            return ReplacementPlan(message: "Приложение не предоставляет доступ к активному текстовому полю.")
        }
        AXUIElementSetMessagingTimeout(element, timeout)
        guard stringAttribute(element, kAXSubroleAttribute) != kAXSecureTextFieldSubrole as String else {
            return ReplacementPlan(message: "Преобразование в поле пароля отключено.")
        }
        let role = stringAttribute(element, kAXRoleAttribute)
        guard [kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String].contains(role) else {
            return ReplacementPlan(message: "Активное поле не поддерживает безопасную замену текста.")
        }

        var selectionError = AXError.success
        let selection = selectedRange(element, error: &selectionError)
        guard selectionError == .success || selectionError == .attributeUnsupported
                || selectionError == .notImplemented else {
            return ReplacementPlan(message: "Не удалось проверить выделение. Замена отменена.")
        }
        var selectedTextError = AXError.success
        let selectedText = stringAttribute(element, kAXSelectedTextAttribute, error: &selectedTextError)
        if selection == nil, selectedTextError != .success {
            return ReplacementPlan(message: "Редактор не позволяет проверить выделение. Замена отменена.")
        }
        let original: String
        let range: CFRange?
        let usesBuffer: Bool
        if (selection?.length ?? 0) > 0 || selectedText?.isEmpty == false {
            let text = selectedText ?? selection.flatMap { string(element, in: $0) }
            guard let text, !text.isEmpty, text.utf16.count <= 16_384,
                  selection == nil || selection?.length == text.utf16.count else {
                return ReplacementPlan(message: "Не удалось прочитать выделение. Выделите меньший фрагмент.")
            }
            original = text
            range = selection
            usesBuffer = false
        } else {
            guard !recentText.isEmpty else {
                return ReplacementPlan(message: "Нет набранного фрагмента. Наберите текст или выделите существующий.")
            }
            original = recentText
            usesBuffer = true
            if let selection {
                let count = recentText.utf16.count
                guard selection.location >= count else {
                    return ReplacementPlan(message: "Курсор переместился. Наберите фрагмент заново или выделите текст.")
                }
                let candidate = CFRange(location: selection.location - count, length: count)
                guard let actual = string(element, in: candidate), actual == recentText else {
                    return ReplacementPlan(message: "Текст изменился в редакторе. Выделите нужный фрагмент для замены.")
                }
                range = candidate
            } else {
                // Для терминалов и редакторов без AX range доступен только недавний ввод.
                range = nil
            }
        }
        let converted = LayoutConverter.convert(original)
        guard converted != original else { return ReplacementPlan(message: "В фрагменте нет букв EN/RU для замены.") }
        guard isValid(), isFrontmost(pid), let current = focusedElement(in: app), CFEqual(current, element),
              selectionMatches(element, range: selection, selectedText: selectedText) else {
            return ReplacementPlan(message: "Замена отменена: активное поле или выделение изменились.")
        }

        // Сначала готовим все события: сбой выделения памяти не должен оставить удалённый текст.
        guard let insertion = unicodeEvents(converted) else {
            return ReplacementPlan(message: "Не удалось подготовить вставку текста.")
        }
        var prefix: [CGEvent] = []
        if usesBuffer {
            var settable = DarwinBoolean(false)
            let selectionSupport = AXUIElementIsAttributeSettable(
                element, kAXSelectedTextRangeAttribute as CFString, &settable
            )
            let canSelect = range != nil && selectionSupport == .success && settable.boolValue
            // AX-запись выделения в WebKit может применяться после следующего клавиатурного события.
            // Выделение клавишами и Unicode-вставка идут через одну очередь приложения.
            let events = canSelect
                ? selectionEvents(count: original.count)
                : backspaceEvents(count: original.count)
            guard let events else { return ReplacementPlan(message: "Не удалось подготовить замену.") }
            prefix = events
        }
        guard isValid(), isFrontmost(pid), let current = focusedElement(in: app), CFEqual(current, element),
              selectionMatches(element, range: selection, selectedText: selectedText) else {
            return ReplacementPlan(message: "Замена отменена: фокус или выделение изменились.")
        }
        // Здесь только чтение и подготовка. Пакет отправит поток event tap после проверки token.
        return ReplacementPlan(
            events: prefix + insertion,
            usedRecentText: usesBuffer,
            text: converted,
            message: "Текст преобразован."
        )
    }

    private func isFrontmost(_ pid: pid_t) -> Bool {
        DispatchQueue.main.sync { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
    }

    private func focusedElement(in app: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var error = AXError.success
        return stringAttribute(element, attribute, error: &error)
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String, error: inout AXError) -> String? {
        var value: CFTypeRef?
        error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else { return nil }
        guard let text = value as? String else { error = .failure; return nil }
        return text
    }

    private func selectedRange(_ element: AXUIElement, error: inout AXError) -> CFRange? {
        var value: CFTypeRef?
        error = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value)
        guard error == .success else { return nil }
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { error = .failure; return nil }
        let axValue = value as! AXValue
        var range = CFRange()
        guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range),
              range.location >= 0, range.length >= 0 else { error = .failure; return nil }
        return range
    }

    private func selectionMatches(_ element: AXUIElement, range: CFRange?, selectedText: String?) -> Bool {
        var error = AXError.success
        let current = selectedRange(element, error: &error)
        if let range { return error == .success && current == range }
        guard error == .attributeUnsupported || error == .notImplemented else { return false }
        var textError = AXError.success
        let currentText = stringAttribute(element, kAXSelectedTextAttribute, error: &textError)
        return textError == .success && currentText == selectedText
    }

    private func string(_ element: AXUIElement, in range: CFRange) -> String? {
        var range = range
        guard let value = AXValueCreate(.cfRange, &range) else { return nil }
        var result: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(
            element, kAXStringForRangeParameterizedAttribute as CFString, value, &result
        ) == .success, let text = result as? String { return text }
        guard let text = stringAttribute(element, kAXValueAttribute) else { return nil }
        let nsText = text as NSString
        guard range.location <= nsText.length, range.length <= nsText.length - range.location else { return nil }
        return nsText.substring(with: NSRange(location: range.location, length: range.length))
    }

    private func keyboardEvent(keyCode: CGKeyCode, down: Bool) -> CGEvent? {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { return nil }
        event.flags = []
        event.setIntegerValueField(.eventSourceUserData, value: EventSupport.marker)
        return event
    }

    private func selectionEvents(count: Int) -> [CGEvent]? {
        var result: [CGEvent] = []
        result.reserveCapacity(count * 2)
        for _ in 0..<count {
            guard let down = keyboardEvent(keyCode: 123, down: true),
                  let up = keyboardEvent(keyCode: 123, down: false) else { return nil }
            down.flags = .maskShift
            up.flags = .maskShift
            result.append(contentsOf: [down, up])
        }
        return result
    }

    private func backspaceEvents(count: Int) -> [CGEvent]? {
        var result: [CGEvent] = []
        result.reserveCapacity(count * 2)
        for _ in 0..<count {
            guard let down = keyboardEvent(keyCode: 51, down: true),
                  let up = keyboardEvent(keyCode: 51, down: false) else { return nil }
            result.append(contentsOf: [down, up])
        }
        return result
    }

    private func unicodeEvents(_ text: String) -> [CGEvent]? {
        // Короткие пакеты совместимы с полями, ограничивающими длину Unicode-события.
        // Граница пакета не разрывает суррогатную пару или составной символ.
        var chunks: [String] = []
        var chunk = ""
        for character in text {
            let next = String(character)
            if !chunk.isEmpty, chunk.utf16.count + next.utf16.count > 20 {
                chunks.append(chunk)
                chunk = ""
            }
            chunk.append(character)
        }
        if !chunk.isEmpty { chunks.append(chunk) }
        var result: [CGEvent] = []
        for chunk in chunks {
            let units = Array(chunk.utf16)
            guard let down = keyboardEvent(keyCode: 0, down: true),
                  let up = keyboardEvent(keyCode: 0, down: false) else { return nil }
            down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            result.append(contentsOf: [down, up])
        }
        return result
    }
}

private func == (lhs: CFRange?, rhs: CFRange?) -> Bool {
    switch (lhs, rhs) {
    case let (.some(lhs), .some(rhs)): return lhs.location == rhs.location && lhs.length == rhs.length
    case (.none, .none): return true
    default: return false
    }
}
