import Foundation

/// Меняет соответствующие клавиши QWERTY и ЙЦУКЕН без словарей и проверки орфографии.
public enum LayoutConverter {
    public enum PunctuationMode: Sendable {
        /// Сохраняет знаки в конце слова и парные кавычки/скобки.
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

    public static func convert(
        _ text: String,
        punctuation: PunctuationMode = .contextual
    ) -> String {
        let characters = Array(text)
        let punctuationPositions = punctuation == .contextual ? contextualPunctuation(in: characters) : []
        return String(characters.enumerated().map { index, character in
            guard let replacement = replacements[character] else { return character }
            guard punctuation == .contextual, isASCIIPunctuation(character) else { return replacement }
            // Одинаковый знак может быть буквой ошибочной раскладки или обычной пунктуацией.
            // Без словаря заменяем его только перед латинской буквой, вне парных разделителей.
            guard punctuationPositions.contains(index) else { return character }
            return replacement
        })
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
                if followedByLatin { positions.insert(index) }
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
