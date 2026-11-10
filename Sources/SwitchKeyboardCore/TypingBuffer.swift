import Foundation

/// Хранит только текущий набранный фрагмент; приложение сбрасывает его при смене контекста.
public struct TypingBuffer {
    public private(set) var text = ""
    public let capacity: Int

    public init(capacity: Int = 1024) {
        self.capacity = max(0, capacity)
    }

    public mutating func append(_ value: String) {
        for character in value {
            if character.isNewline {
                reset()
            } else if !character.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) {
                text.append(character)
            }
        }
        trimToCapacity()
    }

    public mutating func backspace() {
        if !text.isEmpty { text.removeLast() }
    }

    public mutating func reset() {
        text.removeAll(keepingCapacity: false)
    }

    public mutating func replace(with value: String) {
        reset()
        append(value)
    }

    private mutating func trimToCapacity() {
        let overflow = text.count - capacity
        if overflow > 0 { text.removeFirst(overflow) }
    }
}
