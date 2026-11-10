import Carbon
import CoreGraphics
import Foundation

/// Копия таблицы раскладки для event tap: не обращается к TIS из фонового потока.
struct KeyboardLayoutSnapshot {
    let data: Data

    func retranslate(_ event: CGEvent) {
        guard event.type == .keyDown || event.type == .keyUp else { return }
        let flags = event.flags
        let excludedFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskSecondaryFn]
        guard flags.intersection(excludedFlags).isEmpty else { return }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard Self.characterKeyCodes.contains(keyCode), Self.isPrintable(EventSupport.text(from: event)) else { return }
        let keyboardType = event.getIntegerValueField(.keyboardEventKeyboardType)
        guard keyboardType >= 0, keyboardType <= Int64(UInt32.max),
              data.count >= MemoryLayout<UCKeyboardLayout>.size else { return }

        // UCKeyTranslate ожидает биты Carbon EventRecord, а не сдвинутые CGEventFlags.
        var carbonModifiers: UInt32 = 0
        if flags.contains(.maskShift) { carbonModifiers |= UInt32(shiftKey) }
        if flags.contains(.maskAlphaShift) { carbonModifiers |= UInt32(alphaLock) }

        var output = [UniChar](repeating: 0, count: 64)
        var count = 0
        var deadKeyState: UInt32 = 0
        let status = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> OSStatus in
            guard let address = bytes.baseAddress,
                  Int(bitPattern: address) % MemoryLayout<UCKeyboardLayout>.alignment == 0 else {
                return OSStatus(paramErr)
            }
            let layout = address.assumingMemoryBound(to: UCKeyboardLayout.self)
            guard layout.pointee.keyLayoutHeaderFormat == UInt16(kUCKeyLayoutHeaderFormat),
                  layout.pointee.keyboardTypeCount > 0 else { return OSStatus(paramErr) }
            return UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDown),
                carbonModifiers >> 8,
                UInt32(keyboardType),
                OptionBits(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                output.count,
                &count,
                &output
            )
        }
        guard status == noErr, count > 0, count <= output.count,
              Self.isPrintable(String(utf16CodeUnits: output, count: count)) else { return }
        event.keyboardSetUnicodeString(stringLength: count, unicodeString: output)
    }

    private static func isPrintable(_ text: String) -> Bool {
        !text.isEmpty && !text.unicodeScalars.contains { scalar in
            scalar.properties.generalCategory == .control || (0xF700...0xF8FF).contains(scalar.value)
        }
    }

    // Служебные клавиши исключаются и при ошибочном/устаревшем Unicode в CGEvent.
    private static let characterKeyCodes: Set<Int64> = Set(
        (0...50).filter { $0 != 36 && $0 != 48 } + [
            65, 67, 69, 75, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92, 93, 94, 95
        ]
    )
}
