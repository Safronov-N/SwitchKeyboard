import Foundation

/// Меняет соответствующие клавиши QWERTY и ЙЦУКЕН без словарей и проверки орфографии.
public enum LayoutConverter {
    public enum PunctuationMode: Sendable {
        /// Сохраняет обычные знаки и распознаёт символы верхнего ряда после латинского текста.
        case contextual
        /// Меняет все буквенные клавиши, включая `[];'`,.`, строго обратимо.
        case physicalKeys
    }

    private static let pairs: [(Character, Character)] = Array(
        zip(
            "qwertyuiop[]asdfghjkl;'zxcvbnm,.`",
            "йцукенгшщзхъфывапролджэячсмитьбюё"
        )
    )

    private static let replacements: [Character: Character] = {
        var result: [Character: Character] = [:]
        let shiftedPunctuation: [Character: Character] = [
            "[": "{", "]": "}", ";": ":", "'": "\"", ",": "<", ".": ">", "`": "~"
        ]
        for (english, russian) in pairs {
            result[english] = russian
            result[russian] = english
            let upperEnglish = shiftedPunctuation[english] ?? Character(String(english).uppercased())
            let upperRussian = Character(String(russian).uppercased())
            result[upperEnglish] = upperRussian
            result[upperRussian] = upperEnglish
        }
        return result
    }()

    // Символы верхнего ряда с Shift: ABC → стандартная русская раскладка macOS.
    private static let russianShiftedSymbols: [Character: Character] = [
        "@": "\"", "#": "№", "$": "%", "%": ":", "^": ",", "&": ".", "*": ";"
    ]

    public static func convert(
        _ text: String,
        punctuation: PunctuationMode = .contextual
    ) -> String {
        convertWithLanguage(text, punctuation: punctuation).text
    }

    public static func convertWithLanguage(
        _ text: String,
        punctuation: PunctuationMode = .contextual
    ) -> LayoutConversion {
        let characters = Array(text)
        let punctuationPositions = punctuation == .contextual ? contextualPunctuation(in: characters) : []
        var result = ""
        result.reserveCapacity(text.utf8.count)
        var targetLanguage: KeyboardLanguage?
        var followsLatin = false
        for (index, character) in characters.enumerated() {
            if punctuation == .contextual, followsLatin, let symbol = russianShiftedSymbols[character] {
                result.append(symbol)
                continue
            }
            followsLatin = isLatinLetter(character)
            guard let replacement = replacements[character] else {
                result.append(character)
                continue
            }
            // Одинаковый знак может быть буквой ошибочной раскладки или обычной пунктуацией.
            // Контекст учитывает соседние латинские буквы и парные разделители.
            if punctuation == .contextual, isASCIIPunctuation(character), !punctuationPositions.contains(index) {
                result.append(character)
                continue
            }
            result.append(replacement)
            // Направление определяется исходной клавишей: русская «ю» даёт английскую точку.
            targetLanguage = followsLatin || isASCIIPunctuation(character) ? .russian : .english
        }
        return LayoutConversion(text: result, targetLanguage: targetLanguage)
    }

    private static func isLatinLetter(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return false }
        return (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
    }

    private static func isASCIIPunctuation(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return false }
        return scalar.isASCII && !isLatinLetter(character)
    }

    private static func contextualPunctuation(in characters: [Character]) -> Set<Int> {
        let protected = protectedDelimiters(in: characters)
        var positions = Set<Int>()
        var followedByLatin = false
        for index in characters.indices.reversed() {
            let character = characters[index]
            if isLatinLetter(character) {
                followedByLatin = true
            } else if !protected.contains(index), isASCIIPunctuation(character), replacements[character] != nil {
                let followsLatin = index > 0 && isLatinLetter(characters[index - 1])
                let startsDotSequence = character == "." && index + 1 < characters.count && characters[index + 1] == "."
                let isWordEnding = followsLatin && (character == "[" || character == ".") && !startsDotSequence
                if followedByLatin || isWordEnding { positions.insert(index) }
            } else {
                followedByLatin = false
            }
        }
        return positions
    }

    private static func protectedDelimiters(in characters: [Character]) -> Set<Int> {
        var protected = Set<Int>()
        let pairs: [Character: Character] = ["[": "]", "{": "}", "<": ">", "\"": "\"", "'": "'", "`": "`"]
        var openings: [Character: [Int]] = [:]
        for (index, character) in characters.enumerated() {
            // Апостроф внутри слова относится к клавише, а не к кавычкам.
            if character == "'", index > 0, index + 1 < characters.count,
               isLatinLetter(characters[index - 1]), isLatinLetter(characters[index + 1]) {
                continue
            }
            if let opener = pairs.first(where: { $0.value == character })?.key,
               let opening = openings[opener]?.popLast() {
                protected.insert(opening)
                protected.insert(index)
            } else if pairs[character] != nil {
                openings[character, default: []].append(index)
            }
        }
        return protected
    }
}
