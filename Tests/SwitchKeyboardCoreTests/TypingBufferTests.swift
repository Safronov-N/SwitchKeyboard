import XCTest
@testable import SwitchKeyboardCore

final class TypingBufferTests: XCTestCase {
    func testAppendingAndBackspacePreserveWordsAndSpaces() {
        var buffer = TypingBuffer()
        buffer.append("ghbdtn ")
        buffer.append("rfr ltkf?")
        buffer.backspace()
        XCTAssertEqual(buffer.text, "ghbdtn rfr ltkf")
    }

    func testBackspaceDeletesOneGrapheme() {
        var buffer = TypingBuffer()
        buffer.append("a👩‍💻e\u{301}")
        buffer.backspace()
        XCTAssertEqual(buffer.text, "a👩‍💻")
        buffer.backspace()
        XCTAssertEqual(buffer.text, "a")
        buffer.backspace()
        buffer.backspace()
        XCTAssertEqual(buffer.text, "")
    }

    func testCapacityKeepsOnlyNewestCharactersWithoutSplittingEmoji() {
        var buffer = TypingBuffer(capacity: 3)
        buffer.append("old 👩‍💻ab")
        XCTAssertEqual(buffer.text, "👩‍💻ab")
        buffer.append("c")
        XCTAssertEqual(buffer.text, "abc")
    }

    func testNewlineResetsPreviousContext() {
        var buffer = TypingBuffer()
        buffer.append("old\r\nnew")
        XCTAssertEqual(buffer.text, "new")
        buffer.append("\u{2028}last")
        XCTAssertEqual(buffer.text, "last")
    }

    func testControlsAreNotStored() {
        var buffer = TypingBuffer()
        buffer.append("a\t\u{0}\u{1B}b")
        XCTAssertEqual(buffer.text, "ab")
    }

    func testReplacementAndReset() {
        var buffer = TypingBuffer()
        buffer.append("руддщ")
        buffer.replace(with: "hello")
        XCTAssertEqual(buffer.text, "hello")
        buffer.reset()
        XCTAssertTrue(buffer.text.isEmpty)
    }

    func testZeroOrNegativeCapacityStoresNothing() {
        var zero = TypingBuffer(capacity: 0)
        zero.append("hello")
        XCTAssertTrue(zero.text.isEmpty)
        var negative = TypingBuffer(capacity: -1)
        negative.append("hello")
        XCTAssertTrue(negative.text.isEmpty)
    }
}
