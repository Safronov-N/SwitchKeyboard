public enum ShortcutInput: Equatable, Sendable {
    case keyDown(keyCode: UInt16, modifiers: ShortcutModifiers, isRepeat: Bool)
    case keyUp(keyCode: UInt16)
    case modifiersChanged(keyCode: UInt16, modifiers: ShortcutModifiers, isPressed: Bool)
    case pointer
}

public struct ShortcutMatch: Equatable, Sendable {
    public let trigger: Bool
    public let suppress: Bool

    public init(trigger: Bool = false, suppress: Bool = false) {
        self.trigger = trigger
        self.suppress = suppress
    }
}

/// Отделяет одиночное нажатие модификатора от его использования в обычных сочетаниях.
public struct ShortcutMatcher {
    private var shortcut: Shortcut
    private var modifierCandidate = false
    private var pressedModifiers = Set<UInt16>()
    private var suppressedKeys = Set<UInt16>()

    public init(shortcut: Shortcut) {
        self.shortcut = shortcut
    }

    public mutating func reset(shortcut: Shortcut? = nil, clearPressedState: Bool = false) {
        if let shortcut { self.shortcut = shortcut }
        modifierCandidate = false
        if clearPressedState { pressedModifiers.removeAll() }
        // По умолчанию удерживаемый Option не принимается за новый жест после переназначения.
        // После потери событий модификаторы можно очистить; подавленные keyUp сохраняются всегда.
    }

    public mutating func handle(_ input: ShortcutInput) -> ShortcutMatch {
        switch input {
        case let .keyDown(keyCode, modifiers, isRepeat):
            modifierCandidate = false
            if suppressedKeys.contains(keyCode) { return ShortcutMatch(suppress: true) }
            guard !shortcut.isModifierOnly, keyCode == shortcut.keyCode,
                  modifiers == shortcut.modifiers else { return ShortcutMatch() }
            suppressedKeys.insert(keyCode)
            return ShortcutMatch(trigger: !isRepeat, suppress: true)

        case let .keyUp(keyCode):
            modifierCandidate = false
            return ShortcutMatch(suppress: suppressedKeys.remove(keyCode) != nil)

        case let .modifiersChanged(keyCode, modifiers, isPressed):
            guard Self.momentaryModifierKeys.contains(keyCode) else {
                modifierCandidate = false
                return ShortcutMatch()
            }
            let wasPressed = pressedModifiers.contains(keyCode)
            if isPressed {
                pressedModifiers.insert(keyCode)
            } else {
                pressedModifiers.remove(keyCode)
            }
            guard shortcut.isModifierOnly else { return ShortcutMatch() }
            if isPressed {
                modifierCandidate = !wasPressed && pressedModifiers.count == 1
                    && keyCode == shortcut.keyCode && modifiers == shortcut.modifiers
                return ShortcutMatch()
            }
            let shouldTrigger = modifierCandidate && wasPressed && keyCode == shortcut.keyCode
                && pressedModifiers.isEmpty && modifiers.isEmpty
            modifierCandidate = false
            // flagsChanged передаётся приложению даже при срабатывании горячей клавиши.
            return ShortcutMatch(trigger: shouldTrigger)

        case .pointer:
            modifierCandidate = false
            return ShortcutMatch()
        }
    }

    private static let momentaryModifierKeys: Set<UInt16> = [54, 55, 56, 58, 59, 60, 61, 62, 63]
}
