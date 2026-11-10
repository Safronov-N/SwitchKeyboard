import XCTest
@testable import SwitchKeyboardCore

final class ShortcutMatcherTests: XCTestCase {
    func testLeftOptionTriggersOnlyOnReleaseAndDoesNotSuppressFlags() {
        var matcher = ShortcutMatcher(shortcut: .leftOption)
        XCTAssertEqual(matcher.handle(.modifiersChanged(keyCode: 58, modifiers: .option, isPressed: true)), .init())
        XCTAssertEqual(
            matcher.handle(.modifiersChanged(keyCode: 58, modifiers: [], isPressed: false)),
            .init(trigger: true)
        )
        XCTAssertEqual(matcher.handle(.modifiersChanged(keyCode: 58, modifiers: [], isPressed: false)), .init())
    }

    func testOptionWithLetterDoesNotTrigger() {
        var matcher = ShortcutMatcher(shortcut: .leftOption)
        _ = matcher.handle(.modifiersChanged(keyCode: 58, modifiers: .option, isPressed: true))
        XCTAssertEqual(matcher.handle(.keyDown(keyCode: 0, modifiers: .option, isRepeat: false)), .init())
        _ = matcher.handle(.keyUp(keyCode: 0))
        XCTAssertFalse(matcher.handle(.modifiersChanged(keyCode: 58, modifiers: [], isPressed: false)).trigger)
    }

    func testRightOptionDoesNotTriggerLeftOptionShortcut() {
        var matcher = ShortcutMatcher(shortcut: .leftOption)
        _ = matcher.handle(.modifiersChanged(keyCode: 61, modifiers: .option, isPressed: true))
        XCTAssertFalse(matcher.handle(.modifiersChanged(keyCode: 61, modifiers: [], isPressed: false)).trigger)
    }

    func testTwoDifferentModifiersDoNotTrigger() {
        var matcher = ShortcutMatcher(shortcut: .leftOption)
        _ = matcher.handle(.modifiersChanged(keyCode: 58, modifiers: .option, isPressed: true))
        _ = matcher.handle(.modifiersChanged(keyCode: 56, modifiers: [.option, .shift], isPressed: true))
        _ = matcher.handle(.modifiersChanged(keyCode: 56, modifiers: .option, isPressed: false))
        XCTAssertFalse(matcher.handle(.modifiersChanged(keyCode: 58, modifiers: [], isPressed: false)).trigger)
    }

    func testBothOptionKeysInvalidateGesture() {
        for first: UInt16 in [58, 61] {
            let second: UInt16 = first == 58 ? 61 : 58
            var matcher = ShortcutMatcher(shortcut: .leftOption)
            _ = matcher.handle(.modifiersChanged(keyCode: first, modifiers: .option, isPressed: true))
            _ = matcher.handle(.modifiersChanged(keyCode: second, modifiers: .option, isPressed: true))
            XCTAssertFalse(matcher.handle(.modifiersChanged(keyCode: second, modifiers: .option, isPressed: false)).trigger)
            XCTAssertFalse(matcher.handle(.modifiersChanged(keyCode: first, modifiers: [], isPressed: false)).trigger)
        }
    }

    func testRepeatedModifierPressIsNotAnotherGesture() {
        var matcher = ShortcutMatcher(shortcut: .leftOption)
        _ = matcher.handle(.modifiersChanged(keyCode: 58, modifiers: .option, isPressed: true))
        _ = matcher.handle(.modifiersChanged(keyCode: 58, modifiers: .option, isPressed: true))
        XCTAssertFalse(matcher.handle(.modifiersChanged(keyCode: 58, modifiers: [], isPressed: false)).trigger)
    }

    func testMouseCancelsModifierGesture() {
        var matcher = ShortcutMatcher(shortcut: .leftOption)
        _ = matcher.handle(.modifiersChanged(keyCode: 58, modifiers: .option, isPressed: true))
        _ = matcher.handle(.pointer)
        XCTAssertFalse(matcher.handle(.modifiersChanged(keyCode: 58, modifiers: [], isPressed: false)).trigger)
    }

    func testCapsLockDoesNotBecomePermanentlyHeldModifier() {
        var matcher = ShortcutMatcher(shortcut: .leftOption)
        _ = matcher.handle(.modifiersChanged(keyCode: 57, modifiers: [], isPressed: true))
        _ = matcher.handle(.modifiersChanged(keyCode: 58, modifiers: .option, isPressed: true))
        XCTAssertTrue(matcher.handle(.modifiersChanged(keyCode: 58, modifiers: [], isPressed: false)).trigger)
    }

    func testChordTriggersOnceSuppressesRepeatsAndKeyUp() {
        var matcher = ShortcutMatcher(shortcut: .init(keyCode: 40, modifiers: [.control, .option]))
        XCTAssertEqual(
            matcher.handle(.keyDown(keyCode: 40, modifiers: [.control, .option], isRepeat: false)),
            .init(trigger: true, suppress: true)
        )
        XCTAssertEqual(
            matcher.handle(.keyDown(keyCode: 40, modifiers: [.control, .option], isRepeat: true)),
            .init(suppress: true)
        )
        _ = matcher.handle(.modifiersChanged(keyCode: 58, modifiers: .control, isPressed: false))
        XCTAssertEqual(matcher.handle(.keyUp(keyCode: 40)), .init(suppress: true))
        XCTAssertEqual(matcher.handle(.keyUp(keyCode: 40)), .init())
    }

    func testChordNeedsExactKeyAndModifiers() {
        var matcher = ShortcutMatcher(shortcut: .init(keyCode: 40, modifiers: [.control, .option]))
        XCTAssertEqual(matcher.handle(.keyDown(keyCode: 40, modifiers: .option, isRepeat: false)), .init())
        XCTAssertEqual(matcher.handle(.keyDown(keyCode: 40, modifiers: [.control, .option, .shift], isRepeat: false)), .init())
        XCTAssertEqual(matcher.handle(.keyDown(keyCode: 0, modifiers: [.control, .option], isRepeat: false)), .init())
    }

    func testResetPreservesPendingSuppressedKeyUp() {
        var matcher = ShortcutMatcher(shortcut: .init(keyCode: 40, modifiers: [.control, .option]))
        _ = matcher.handle(.keyDown(keyCode: 40, modifiers: [.control, .option], isRepeat: false))
        matcher.reset(shortcut: .leftOption)
        XCTAssertEqual(matcher.handle(.keyUp(keyCode: 40)), .init(suppress: true))
    }

    func testResetCancelsPendingModifierGesture() {
        var matcher = ShortcutMatcher(shortcut: .leftOption)
        _ = matcher.handle(.modifiersChanged(keyCode: 58, modifiers: .option, isPressed: true))
        matcher.reset()
        XCTAssertFalse(matcher.handle(.modifiersChanged(keyCode: 58, modifiers: [], isPressed: false)).trigger)
        _ = matcher.handle(.modifiersChanged(keyCode: 58, modifiers: .option, isPressed: true))
        XCTAssertTrue(matcher.handle(.modifiersChanged(keyCode: 58, modifiers: [], isPressed: false)).trigger)
    }

    func testLostModifierEventsCanBeClearedBeforeNextGesture() {
        var matcher = ShortcutMatcher(shortcut: .leftOption)
        _ = matcher.handle(.modifiersChanged(keyCode: 56, modifiers: .shift, isPressed: true))
        matcher.reset(clearPressedState: true)
        _ = matcher.handle(.modifiersChanged(keyCode: 58, modifiers: .option, isPressed: true))
        XCTAssertTrue(matcher.handle(.modifiersChanged(keyCode: 58, modifiers: [], isPressed: false)).trigger)
    }
}
