import Foundation

public struct WordBoundary: Equatable {
    public let text: String
    public let range: Range<Int>

    public init(text: String, range: Range<Int>) {
        self.text = text
        self.range = range
    }
}

public protocol WordBoundaryDetecting: Sendable {
    func detect(in text: String, caretOffset: Int) -> WordBoundary?
}

public struct DefaultWordBoundaryDetector: WordBoundaryDetecting {
    public init() {}

    public func detect(in text: String, caretOffset: Int) -> WordBoundary? {
        guard !text.isEmpty else {
            return nil
        }

        let safeOffset = max(0, min(caretOffset, text.count))
        let chars = Array(text)

        if safeOffset < chars.count && isWordCharacter(chars[safeOffset]) {
            return wordBoundary(in: chars, startingAt: safeOffset)
        }

        if let previousWord = previousWord(in: chars, before: safeOffset) {
            return previousWord
        }

        return nextWord(in: chars, after: safeOffset)
    }

    private func wordBoundary(in chars: [Character], startingAt index: Int) -> WordBoundary? {
        var start = index
        while start > 0 && isWordCharacter(chars[start - 1]) {
            start -= 1
        }

        var end = index
        while end < chars.count && isWordCharacter(chars[end]) {
            end += 1
        }

        guard start < end else {
            return nil
        }

        let word = String(chars[start..<end])
        return WordBoundary(text: word, range: start..<end)
    }

    private func previousWord(in chars: [Character], before index: Int) -> WordBoundary? {
        guard index > 0 else {
            return nil
        }

        var end = index
        while end > 0 && !isWordCharacter(chars[end - 1]) {
            end -= 1
        }

        if end == 0 && !isWordCharacter(chars[0]) {
            return nil
        }

        var start = end
        while start > 0 && isWordCharacter(chars[start - 1]) {
            start -= 1
        }

        guard start < end else {
            return nil
        }

        let word = String(chars[start..<end])
        return WordBoundary(text: word, range: start..<end)
    }

    private func nextWord(in chars: [Character], after index: Int) -> WordBoundary? {
        guard index < chars.count else {
            return nil
        }

        var start = index
        while start < chars.count && !isWordCharacter(chars[start]) {
            start += 1
        }

        guard start < chars.count else {
            return nil
        }

        var end = start
        while end < chars.count && isWordCharacter(chars[end]) {
            end += 1
        }

        guard start < end else {
            return nil
        }

        let word = String(chars[start..<end])
        return WordBoundary(text: word, range: start..<end)
    }

    private func isWordCharacter(_ character: Character) -> Bool {
        let scalar = String(character).unicodeScalars.first
        guard let scalar else {
            return false
        }

        let value = scalar.value
        return CharacterSet.letters.contains(scalar)
            || CharacterSet.decimalDigits.contains(scalar)
            || value == 0x005F
    }
}
