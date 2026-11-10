import XCTest
@testable import SwitchKeyboardCore

final class LayoutConverterTests: XCTestCase {
    func testRequestedExamples() {
        XCTAssertEqual(LayoutConverter.convert("руддщ"), "hello")
        XCTAssertEqual(LayoutConverter.convert("ghbdtn rfr ltkf?"), "привет как дела?")
        XCTAssertEqual(LayoutConverter.convert("Ghbdtn рщц фку нщг"), "Привет how are you")
    }

    func testAlphabetAndCapitalization() {
        XCTAssertEqual(
            LayoutConverter.convert("qwertyuiopasdfghjklzxcvbnm"),
            "йцукенгшщзфывапролдячсмить"
        )
        XCTAssertEqual(
            LayoutConverter.convert("QWERTYUIOPASDFGHJKLZXCVBNM"),
            "ЙЦУКЕНГШЩЗФЫВАПРОЛДЯЧСМИТЬ"
        )
        XCTAssertEqual(
            LayoutConverter.convert("ЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮЁ"),
            "QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>~"
        )
    }

    func testPhysicalModeIsInvolutionForAllMappedKeys() {
        let text = "qwertyuiop[]asdfghjkl;'zxcvbnm,.` QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>~"
        let converted = LayoutConverter.convert(text, punctuation: .physicalKeys)
        XCTAssertEqual(converted, "йцукенгшщзхъфывапролджэячсмитьбюё ЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮЁ")
        XCTAssertEqual(LayoutConverter.convert(converted, punctuation: .physicalKeys), text)
    }

    func testOrdinaryPunctuationAndUnicodeArePreserved() {
        XCTAssertEqual(LayoutConverter.convert("Ghbdtn, vbh! Rfr ltkf? 123 😀"), "Привет, мир! Как дела? 123 😀")
        XCTAssertEqual(LayoutConverter.convert("руддщ."), "hello.")
        XCTAssertEqual(LayoutConverter.convert("  ghbdtn   "), "  привет   ")
        XCTAssertEqual(LayoutConverter.convert("café 👩‍💻"), "сфаé 👩‍💻")
    }

    func testAmbiguousPunctuationIsConvertedOnlyBeforeLatinLetters() {
        XCTAssertEqual(LayoutConverter.convert(";bpym"), "жизнь")
        XCTAssertEqual(LayoutConverter.convert("[jxe"), "хочу")
        XCTAssertEqual(LayoutConverter.convert("'nj"), "это")
        XCTAssertEqual(LayoutConverter.convert("j,]tv"), "объем")
        XCTAssertEqual(LayoutConverter.convert("ghbdtn;"), "привет;")
        XCTAssertEqual(LayoutConverter.convert("j,"), "о,")
        XCTAssertEqual(LayoutConverter.convert("j,", punctuation: .physicalKeys), "об")
    }

    func testPairedDelimitersRemainDelimiters() {
        XCTAssertEqual(LayoutConverter.convert("[ghbdtn] \"vbh\" 'ntcn'"), "[привет] \"мир\" 'тест'")
        XCTAssertEqual(LayoutConverter.convert("{ghbdtn} <vbh> `ntcn`"), "{привет} <мир> `тест`")
    }
}
