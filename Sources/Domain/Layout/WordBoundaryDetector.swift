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

        let anchor: (index: String.Index, offset: Int)?
        if caretIndex < text.endIndex && isWordCharacter(text[caretIndex]) {
            anchor = (caretIndex, safeOffset)
        } else {
            anchor = findNearbyWordCharacter(in: text, from: caretIndex, offset: safeOffset, direction: .backward)
                ?? findNearbyWordCharacter(in: text, from: caretIndex, offset: safeOffset, direction: .forward)
        }

        guard let anchor else {
            return nil
        }

        return expandWord(in: text, around: anchor.index, offset: anchor.offset)
    }

    private enum SearchDirection {
        case backward
        case forward
    }

    private func findNearbyWordCharacter(
        in text: String,
        from index: String.Index,
        offset: Int,
        direction: SearchDirection
    ) -> (index: String.Index, offset: Int)? {
        var cursor = index
        var cursorOffset = offset

        for _ in 0..<Self.windowSize {
            switch direction {
            case .backward:
                guard cursor > text.startIndex else { return nil }
                cursor = text.index(before: cursor)
                cursorOffset -= 1
                if isWordCharacter(text[cursor]) {
                    return (cursor, cursorOffset)
                }
            case .forward:
                guard cursor < text.endIndex else { return nil }
                if isWordCharacter(text[cursor]) {
                    return (cursor, cursorOffset)
                }
                cursor = text.index(after: cursor)
                cursorOffset += 1
            }
        }

        return nil
    }

    private func expandWord(
        in text: String,
        around index: String.Index,
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
