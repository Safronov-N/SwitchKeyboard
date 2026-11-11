import XCTest
@testable import SwitchKeyboardCore

final class LanguageTests: XCTestCase {
    func testRequestedExamplesIncludeResultLanguage() {
        XCTAssertEqual(
            LayoutConverter.convertWithLanguage("руддщ"),
            LayoutConversion(text: "hello", targetLanguage: .english)
        )
        XCTAssertEqual(
            LayoutConverter.convertWithLanguage("ghbdtn rfr ltkf?"),
            LayoutConversion(text: "привет как дела?", targetLanguage: .russian)
        )
        XCTAssertEqual(
            LayoutConverter.convertWithLanguage("Ghbdtn^ rfr ltkf?"),
            LayoutConversion(text: "Привет, как дела?", targetLanguage: .russian)
        )
        XCTAssertEqual(
            LayoutConverter.convertWithLanguage("Ghbdtn рщц фку нщг"),
            LayoutConversion(text: "Привет how are you", targetLanguage: .english)
        )
    }

    func testMixedTextUsesLastConvertedWord() {
        XCTAssertEqual(
            LayoutConverter.convertWithLanguage("руддщ ghbdtn"),
            LayoutConversion(text: "hello привет", targetLanguage: .russian)
        )
        XCTAssertEqual(
            LayoutConverter.convertWithLanguage("ghbdtn руддщ"),
            LayoutConversion(text: "привет hello", targetLanguage: .english)
        )
    }

    func testCyrillicLetterMappedToPunctuationStillTargetsEnglish() {
        XCTAssertEqual(
            LayoutConverter.convertWithLanguage("ghbdtn ю? 123 😀"),
            LayoutConversion(text: "привет .? 123 😀", targetLanguage: .english)
        )
        XCTAssertEqual(
            LayoutConverter.convertWithLanguage("ЖЭХЪБЮЁ"),
            LayoutConversion(text: ":\"{}<>~", targetLanguage: .english)
        )
    }

    func testPhysicalPunctuationCanChangeResultLanguage() {
        XCTAssertEqual(
            LayoutConverter.convertWithLanguage("руддщ.", punctuation: .physicalKeys),
            LayoutConversion(text: "helloю", targetLanguage: .russian)
        )
        XCTAssertEqual(
            LayoutConverter.convertWithLanguage("[", punctuation: .physicalKeys),
            LayoutConversion(text: "х", targetLanguage: .russian)
        )
    }

    func testContextualPunctuationDoesNotChangeResultLanguage() {
        XCTAssertEqual(
            LayoutConverter.convertWithLanguage("РУДДЩ.;"),
            LayoutConversion(text: "HELLO.;", targetLanguage: .english)
        )
        XCTAssertEqual(
            LayoutConverter.convertWithLanguage("[ghbdtn]"),
            LayoutConversion(text: "[привет]", targetLanguage: .russian)
        )
    }

    func testUnchangedTextHasNoResultLanguage() {
        for text in ["", "123!? 😀", "é λ é\u{301}", "[] \"\" ;,."] {
            XCTAssertEqual(
                LayoutConverter.convertWithLanguage(text),
                LayoutConversion(text: text, targetLanguage: nil)
            )
        }
    }

    func testUnsupportedUnicodeSuffixDoesNotChangeResultLanguage() {
        XCTAssertEqual(
            LayoutConverter.convertWithLanguage("руддщ é λ😀"),
            LayoutConversion(text: "hello é λ😀", targetLanguage: .english)
        )
    }
}
