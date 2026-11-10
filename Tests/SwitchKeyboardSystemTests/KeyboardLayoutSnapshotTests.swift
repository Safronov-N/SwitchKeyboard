import Carbon
import CoreGraphics
import Foundation
import XCTest
@testable import SwitchKeyboard

final class KeyboardLayoutSnapshotTests: XCTestCase {
    func testEnglishQWERTYRetranslatesKeyDownAndKeyUp() throws {
        let snapshot = try snapshot(identifiers: ["com.apple.keylayout.ABC", "com.apple.keylayout.US"])
        for keyDown in [true, false] {
            let event = try event(keyCode: 4, text: "р", keyDown: keyDown)
            snapshot.retranslate(event)
            XCTAssertEqual(EventSupport.text(from: event), "h")
        }
    }

    func testRussianRetranslatesKeyDownAndKeyUp() throws {
        let snapshot = try snapshot(identifiers: ["com.apple.keylayout.Russian", "com.apple.keylayout.RussianWin"])
        for keyDown in [true, false] {
            let event = try event(keyCode: 4, text: "h", keyDown: keyDown)
            snapshot.retranslate(event)
            XCTAssertEqual(EventSupport.text(from: event), "р")
        }
    }

    func testShiftAndCapsLockUseCarbonModifierBits() throws {
        let layouts: [(Set<String>, String, String)] = [
            (["com.apple.keylayout.ABC", "com.apple.keylayout.US"], "р", "H"),
            (["com.apple.keylayout.Russian", "com.apple.keylayout.RussianWin"], "h", "Р")
        ]
        var checkedLayouts = 0
        for (identifiers, original, expected) in layouts {
            guard let data = loadLayoutData(identifiers: identifiers) else { continue }
            checkedLayouts += 1
            for flags: CGEventFlags in [.maskShift, .maskAlphaShift] {
                let event = try event(keyCode: 4, text: original, flags: flags)
                KeyboardLayoutSnapshot(data: data).retranslate(event)
                XCTAssertEqual(EventSupport.text(from: event), expected)
            }
        }
        if checkedLayouts == 0 { throw XCTSkip("Нет включённых стандартных раскладок QWERTY/ЙЦУКЕН") }
    }

    func testCommandControlOptionAndFnAreUntouched() throws {
        let snapshot = try snapshot(identifiers: ["com.apple.keylayout.ABC", "com.apple.keylayout.US"])
        for flags: CGEventFlags in [.maskCommand, .maskControl, .maskAlternate, .maskSecondaryFn] {
            let event = try event(keyCode: 4, text: "р", flags: flags)
            snapshot.retranslate(event)
            XCTAssertEqual(EventSupport.text(from: event), "р")
            XCTAssertEqual(event.flags, flags)
        }
    }

    func testServiceKeysAreUntouchedEvenWithPrintableUnicode() throws {
        let snapshot = try snapshot(identifiers: ["com.apple.keylayout.ABC", "com.apple.keylayout.US"])
        for keyCode: CGKeyCode in [36, 48, 51, 53, 76, 115, 116, 117, 119, 121, 123, 124, 125, 126] {
            let event = try event(keyCode: keyCode, text: "р")
            snapshot.retranslate(event)
            XCTAssertEqual(EventSupport.text(from: event), "р", "keyCode=\(keyCode)")
        }
    }

    func testEmptyAndControlUnicodeAreUntouched() throws {
        let snapshot = try snapshot(identifiers: ["com.apple.keylayout.ABC", "com.apple.keylayout.US"])
        for text in ["", "\n", "\t", "\u{1B}", "\u{F700}"] {
            let event = try event(keyCode: 4, text: text)
            snapshot.retranslate(event)
            XCTAssertEqual(EventSupport.text(from: event), text)
        }
    }

    func testEmptyAndTruncatedLayoutDataAreSafe() throws {
        for data in [Data(), Data(repeating: 0, count: MemoryLayout<UCKeyboardLayout>.size - 1)] {
            let event = try event(keyCode: 4, text: "р")
            KeyboardLayoutSnapshot(data: data).retranslate(event)
            XCTAssertEqual(EventSupport.text(from: event), "р")
        }
    }

    func testNonKeyboardEventIsUntouched() throws {
        let event = try event(keyCode: 4, text: "р")
        event.type = .flagsChanged
        KeyboardLayoutSnapshot(data: Data()).retranslate(event)
        XCTAssertEqual(EventSupport.text(from: event), "р")
    }

    private func event(
        keyCode: CGKeyCode,
        text: String,
        flags: CGEventFlags = [],
        keyDown: Bool = true
    ) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown))
        event.flags = flags
        event.setIntegerValueField(.keyboardEventKeyboardType, value: 40)
        let units = Array(text.utf16)
        event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        return event
    }

    private func snapshot(identifiers: Set<String>) throws -> KeyboardLayoutSnapshot {
        guard let data = loadLayoutData(identifiers: identifiers) else {
            throw XCTSkip("Нет включённой стандартной раскладки: \(identifiers.sorted().joined(separator: ", "))")
        }
        return KeyboardLayoutSnapshot(data: data)
    }

    private func loadLayoutData(identifiers: Set<String>) -> Data? {
        let load = { () -> Data? in
            guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue(),
                  let sources = list as NSArray as? [TISInputSource] else { return nil }
            for source in sources {
                guard let idPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
                let identifier = Unmanaged<CFString>.fromOpaque(idPointer).takeUnretainedValue() as String
                guard identifiers.contains(identifier),
                      let dataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
                    continue
                }
                let data = Unmanaged<CFData>.fromOpaque(dataPointer).takeUnretainedValue()
                guard let bytes = CFDataGetBytePtr(data) else { continue }
                return Data(bytes: bytes, count: CFDataGetLength(data))
            }
            return nil
        }
        return Thread.isMainThread ? load() : DispatchQueue.main.sync(execute: load)
    }
}
