import XCTest
@testable import SwitchKeyboardCore

final class ShortcutTests: XCTestCase {
    func testDefaultShortcutIsLeftOption() {
        XCTAssertEqual(Shortcut.leftOption.keyCode, 58)
        XCTAssertEqual(Shortcut.leftOption.modifiers, .option)
        XCTAssertTrue(Shortcut.leftOption.isModifierOnly)
        XCTAssertEqual(Shortcut.leftOption.displayName, "Левый Option")
    }

    func testShortcutRoundTripPreservesAllModifiers() throws {
        let shortcut = Shortcut(keyCode: 40, modifiers: [.command, .option, .control, .shift])
        let decoded = try JSONDecoder().decode(Shortcut.self, from: JSONEncoder().encode(shortcut))
        XCTAssertEqual(decoded, shortcut)
        XCTAssertEqual(decoded.displayName, "⌃⌥⇧⌘K")
    }

    func testModifierOnlyShortcutRoundTrip() throws {
        let data = try JSONEncoder().encode(Shortcut.leftOption)
        XCTAssertEqual(try JSONDecoder().decode(Shortcut.self, from: data), .leftOption)
    }
}
