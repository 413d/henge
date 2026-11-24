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
    /// Maximum number of delimiter characters scanned on each side of the caret
    /// when searching for a nearby word. Once inside a word-character run,
    /// scanning continues past this window without truncation.
    static let windowSize = 256

    public init() {}

    public func detect(in text: String, caretOffset: Int) -> WordBoundary? {
        guard !text.isEmpty else {
            return nil
        }

        let caretIndex: String.Index
        let safeOffset: Int
        if caretOffset <= 0 {
            caretIndex = text.startIndex
            safeOffset = 0
        } else if let resolved = text.index(text.startIndex, offsetBy: caretOffset, limitedBy: text.endIndex) {
            caretIndex = resolved
            safeOffset = caretOffset
        } else {
            caretIndex = text.endIndex
            safeOffset = text.count
        }

        if caretIndex < text.endIndex && isWordCharacter(text[caretIndex]) {
            return wordBoundary(in: text, startingAt: caretIndex, offset: safeOffset)
        }

        if let previousWord = previousWord(in: text, before: caretIndex, offset: safeOffset) {
            return previousWord
        }

        return nextWord(in: text, after: caretIndex, offset: safeOffset)
    }

    private func wordBoundary(
        in text: String,
        startingAt index: String.Index,
        offset: Int
    ) -> WordBoundary? {
        var start = index
        var startOffset = offset
        while start > text.startIndex {
            let prev = text.index(before: start)
            guard isWordCharacter(text[prev]) else {
                break
            }
            start = prev
            startOffset -= 1
        }

        var end = text.index(after: index)
        var endOffset = offset + 1
        while end < text.endIndex && isWordCharacter(text[end]) {
            end = text.index(after: end)
            endOffset += 1
        }

        guard startOffset < endOffset else {
            return nil
        }

        return WordBoundary(text: String(text[start..<end]), range: startOffset..<endOffset)
    }

    private func previousWord(
        in text: String,
        before index: String.Index,
        offset: Int
    ) -> WordBoundary? {
        guard index > text.startIndex else {
            return nil
        }

        var end = index
        var endOffset = offset
        var steps = 0

        while end > text.startIndex && steps < Self.windowSize {
            let prev = text.index(before: end)
            if isWordCharacter(text[prev]) {
                break
            }
            end = prev
            endOffset -= 1
            steps += 1
        }

        guard end > text.startIndex, steps < Self.windowSize else {
            return nil
        }

        var start = end
        var startOffset = endOffset
        while start > text.startIndex {
            let prev = text.index(before: start)
            guard isWordCharacter(text[prev]) else {
                break
            }
            start = prev
            startOffset -= 1
        }

        guard startOffset < endOffset else {
            return nil
        }

        return WordBoundary(text: String(text[start..<end]), range: startOffset..<endOffset)
    }

    private func nextWord(
        in text: String,
        after index: String.Index,
        offset: Int
    ) -> WordBoundary? {
        guard index < text.endIndex else {
            return nil
        }

        var start = index
        var startOffset = offset
        var steps = 0

        while start < text.endIndex && steps < Self.windowSize && !isWordCharacter(text[start]) {
            start = text.index(after: start)
            startOffset += 1
            steps += 1
        }

        guard start < text.endIndex, steps < Self.windowSize else {
            return nil
        }

        var end = text.index(after: start)
        var endOffset = startOffset + 1
        while end < text.endIndex && isWordCharacter(text[end]) {
            end = text.index(after: end)
            endOffset += 1
        }

        guard startOffset < endOffset else {
            return nil
        }

        return WordBoundary(text: String(text[start..<end]), range: startOffset..<endOffset)
    }

    private func isWordCharacter(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else {
            return false
        }

        let value = scalar.value
        if scalar.isASCII {
            return (value >= 0x41 && value <= 0x5A)
                || (value >= 0x61 && value <= 0x7A)
                || (value >= 0x30 && value <= 0x39)
                || value == 0x005F
        }

        return CharacterSet.letters.contains(scalar)
            || CharacterSet.decimalDigits.contains(scalar)
    }
}
