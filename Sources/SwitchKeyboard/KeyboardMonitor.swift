import AppKit
import ApplicationServices
import Carbon
import SwitchKeyboardCore

final class ConversionGate {
    private let lock = NSLock()
    private var revision = 0

    func invalidate() {
        lock.lock()
        revision &+= 1
        lock.unlock()
    }

    func token() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return revision
    }

    func matches(_ token: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return revision == token
    }
}

final class KeyboardMonitor {
    var onStatus: ((Bool, String) -> Void)?
    var onShortcutRecorded: ((Shortcut) -> Void)?
    var onRecordingCancelled: (() -> Void)?

    private let lifecycleLock = NSLock()
    private var runLoop: CFRunLoop?
    private var isStarted = false
    private var desiredShortcut: Shortcut
    private var desiredEnabled: Bool
    private var desiredPID: pid_t
    private let gate = ConversionGate()
    private let replacementQueue = DispatchQueue(label: "SwitchKeyboard.replacement", qos: .userInteractive)
    private let replacer = TextReplacer()

    // Эти поля доступны только из потока event tap.
    private var tap: CFMachPort?
    private var buffer = TypingBuffer()
    private var matcher: ShortcutMatcher
    private var shortcut: Shortcut
    private var isEnabled: Bool
    private var targetPID: pid_t
    private var isRecording = false
    private var recordingModifier: UInt16?
    private var recordingContaminated = false
    private var suppressedKeyUps: Set<UInt16> = []
    private var isReplacing = false
    private var operationID = 0
    private var deferredEvents: [(CGEvent, pid_t)] = []

    init(shortcut: Shortcut, isEnabled: Bool, targetPID: pid_t) {
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        self.targetPID = targetPID
        desiredShortcut = shortcut
        desiredEnabled = isEnabled
        desiredPID = targetPID
        matcher = ShortcutMatcher(shortcut: shortcut)
    }

    func start() {
        lifecycleLock.lock()
        guard !isStarted else { lifecycleLock.unlock(); return }
        isStarted = true
        lifecycleLock.unlock()
        let thread = Thread { [self] in eventThread() }
        thread.name = "SwitchKeyboard keyboard events"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    func stop() {
        gate.invalidate()
        perform { [self] in
            if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
            if let runLoop { CFRunLoopStop(runLoop) }
        }
    }

    func update(shortcut: Shortcut, isEnabled: Bool) {
        gate.invalidate()
        lifecycleLock.lock()
        desiredShortcut = shortcut
        desiredEnabled = isEnabled
        lifecycleLock.unlock()
        perform { [self] in
            self.shortcut = shortcut
            self.isEnabled = isEnabled
            matcher.reset(shortcut: shortcut)
            buffer.reset()
        }
    }

    func activate(pid: pid_t) {
        gate.invalidate()
        lifecycleLock.lock()
        desiredPID = pid
        lifecycleLock.unlock()
        perform { [self] in
            targetPID = pid
            buffer.reset()
            matcher.reset()
        }
    }

    func recordShortcut() {
        gate.invalidate()
        perform { [self] in
            isRecording = true
            recordingModifier = nil
            recordingContaminated = false
            matcher.reset()
            buffer.reset()
        }
    }

    func cancelRecording() {
        perform { [self] in
            isRecording = false
            recordingModifier = nil
            matcher.reset()
        }
    }

    private func perform(_ action: @escaping () -> Void) {
        lifecycleLock.lock()
        let loop = runLoop
        lifecycleLock.unlock()
        guard let loop else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue, action)
        CFRunLoopWakeUp(loop)
    }

    private func eventThread() {
        autoreleasepool {
            let mask = [CGEventType.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown,
                        .otherMouseDown, .scrollWheel]
                .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
            let callback: CGEventTapCallBack = { proxy, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(context).takeUnretainedValue()
                return monitor.handle(proxy: proxy, type: type, event: event) ? nil : Unmanaged.passUnretained(event)
            }
            guard let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
                lifecycleLock.lock()
                isStarted = false
                lifecycleLock.unlock()
                report(false, "Не удалось перехватить клавиши. Проверьте разрешения и перезапустите приложение.")
                return
            }
            lifecycleLock.lock()
            shortcut = desiredShortcut
            isEnabled = desiredEnabled
            targetPID = desiredPID
            matcher = ShortcutMatcher(shortcut: shortcut)
            isReplacing = false
            operationID &+= 1
            runLoop = CFRunLoopGetCurrent()
            lifecycleLock.unlock()
            tap = port
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            report(true, "Готово. Наберите текст и нажмите горячую клавишу.")
            CFRunLoopRun()
            gate.invalidate()
            operationID &+= 1
            isReplacing = false
            flushDeferredEvents()
            CFMachPortInvalidate(port)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            tap = nil
            buffer.reset()
            lifecycleLock.lock()
            runLoop = nil
            isStarted = false
            lifecycleLock.unlock()
        }
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            gate.invalidate()
            buffer.reset()
            matcher.reset(clearPressedState: true)
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard event.getIntegerValueField(.eventSourceUserData) != EventSupport.marker else { return false }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyUp, suppressedKeyUps.remove(keyCode) != nil {
            _ = matcher.handle(.keyUp(keyCode: keyCode))
            return true
        }
        if type == .keyDown, suppressedKeyUps.contains(keyCode) { return true }

        if [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel].contains(type) {
            gate.invalidate()
            // Эти клавиши физически предшествовали клику; отправляем их до смены поля.
            flushDeferredEvents(before: proxy)
            buffer.reset()
            _ = matcher.handle(.pointer)
            recordingContaminated = true
            return false
        }
        let input: ShortcutInput
        switch type {
        case .keyDown:
            input = .keyDown(
                keyCode: keyCode,
                modifiers: EventSupport.modifiers(event.flags),
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            )
        case .keyUp: input = .keyUp(keyCode: keyCode)
        case .flagsChanged:
            input = .modifiersChanged(
                keyCode: keyCode,
                modifiers: EventSupport.modifiers(event.flags),
                isPressed: EventSupport.isModifierPressed(keyCode: keyCode, flags: event.flags)
            )
        default: return false
        }
        let inactive = !isEnabled || targetPID == getpid() || isRecording
        let match: ShortcutMatch
        if inactive, type == .keyDown {
            matcher.reset()
            match = ShortcutMatch()
        } else {
            match = matcher.handle(input)
        }
        if match.suppress, type == .keyDown { suppressedKeyUps.insert(keyCode) }
        // Даже в паузе и собственном окне учитываем release удерживаемых клавиш.
        if IsSecureEventInputEnabled() {
            gate.invalidate()
            buffer.reset()
            matcher.reset(clearPressedState: true)
            return match.suppress
        }
        if isRecording { return record(type: type, event: event, keyCode: keyCode) }
        guard isEnabled, targetPID != getpid() else {
            matcher.reset()
            return match.suppress && type == .keyUp
        }
        if isReplacing {
            if match.suppress { return true }
            if let copy = event.copy() { deferredEvents.append((copy, targetPID)) }
            return true
        }
        if match.trigger { convert() }
        if !match.suppress, type == .keyDown { track(event, keyCode: keyCode) }
        return match.suppress
    }

    private func track(_ event: CGEvent, keyCode: UInt16) {
        let modifiers = EventSupport.modifiers(event.flags)
        // Переключение источника ввода не разрывает смешанный EN/RU-фрагмент.
        if keyCode == 49, [ShortcutModifiers.control, [.control, .option], .command].contains(modifiers) {
            return
        }
        // Такие сочетания могут удалять слова, перемещать курсор или вводить dead key.
        guard modifiers.intersection([.command, .control, .option]).isEmpty,
              !event.flags.contains(.maskSecondaryFn) else { buffer.reset(); return }
        switch keyCode {
        case 51: buffer.backspace()
        case 36, 48, 53, 76, 117, 115, 116, 119, 121, 123...126: buffer.reset()
        default:
            let text = EventSupport.text(from: event)
            if text.isEmpty { buffer.reset() } else { buffer.append(text) }
        }
    }

    private func record(type: CGEventType, event: CGEvent, keyCode: UInt16) -> Bool {
        if type == .keyDown {
            if keyCode == 53 {
                isRecording = false
                DispatchQueue.main.async { [weak self] in self?.onRecordingCancelled?() }
            } else {
                let modifiers = EventSupport.modifiers(event.flags)
                guard !modifiers.isEmpty else {
                    report(true, "Добавьте к клавише ⌘, ⌥, ⌃ или ⇧, либо нажмите один модификатор.")
                    suppressedKeyUps.insert(keyCode)
                    return true
                }
                finishRecording(Shortcut(keyCode: keyCode, modifiers: modifiers))
            }
            suppressedKeyUps.insert(keyCode)
            return true
        }
        guard type == .flagsChanged, let modifier = EventSupport.modifier(for: keyCode) else { return false }
        let pressed = EventSupport.isModifierPressed(keyCode: keyCode, flags: event.flags)
        if pressed {
            if recordingModifier == nil {
                recordingModifier = keyCode
                recordingContaminated = EventSupport.modifiers(event.flags) != modifier
            } else {
                recordingContaminated = true
            }
        } else if recordingModifier == keyCode {
            if !recordingContaminated, EventSupport.modifiers(event.flags).isEmpty {
                finishRecording(Shortcut(keyCode: keyCode, modifiers: modifier, isModifierOnly: true))
            }
            recordingModifier = nil
            recordingContaminated = false
        }
        return false
    }

    private func finishRecording(_ result: Shortcut) {
        isRecording = false
        shortcut = result
        matcher.reset(shortcut: result)
        DispatchQueue.main.async { [weak self] in self?.onShortcutRecorded?(result) }
    }

    private func convert() {
        guard !isReplacing, targetPID > 0 else { return }
        let text = buffer.text
        let pid = targetPID
        let token = gate.token()
        operationID &+= 1
        let operation = operationID
        isReplacing = true
        matcher.reset()
        replacementQueue.async { [self] in
            let plan = replacer.prepare(recentText: text, pid: pid) { [gate] in gate.matches(token) }
            perform { [self] in
                guard operationID == operation else { return }
                let apply = gate.matches(token) && plan.isReady
                // Весь пакет отправляется из одного потока; физический клик не вклинится
                // между подготовленным выделением и вставкой.
                if apply {
                    for event in plan.events { event.postToPid(pid) }
                }
                if apply, plan.usedRecentText {
                    buffer.replace(with: plan.text)
                } else {
                    buffer.reset()
                }
                isReplacing = false
                report(true, gate.matches(token) ? plan.message : "Замена отменена: фокус изменился.")
                flushDeferredEvents()
            }
        }
    }

    private func flushDeferredEvents(before proxy: CGEventTapProxy? = nil) {
        // Сохраняем порядок ввода, пришедшего во время межпроцессного запроса AX.
        let pending = deferredEvents
        deferredEvents.removeAll(keepingCapacity: true)
        for (event, pid) in pending {
            if pid == targetPID, event.type == .keyDown {
                track(event, keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)))
            }
            event.setIntegerValueField(.eventSourceUserData, value: EventSupport.marker)
            if let proxy { event.tapPostEvent(proxy) } else { event.postToPid(pid) }
        }
    }

    private func report(_ running: Bool, _ message: String) {
        DispatchQueue.main.async { [weak self] in self?.onStatus?(running, message) }
    }
}
