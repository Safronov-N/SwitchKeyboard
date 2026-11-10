public enum KeyboardLanguage: String, Equatable, Sendable {
    case english = "en"
    case russian = "ru"
}

public struct LayoutConversion: Equatable, Sendable {
    public let text: String
    public let targetLanguage: KeyboardLanguage?

    public init(text: String, targetLanguage: KeyboardLanguage?) {
        self.text = text
        self.targetLanguage = targetLanguage
    }
}
