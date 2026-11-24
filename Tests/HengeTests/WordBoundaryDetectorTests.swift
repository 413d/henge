import Testing
@testable import Henge

struct WordBoundaryDetectorTests {
    @Test
    func detectsWholeWordWhenCaretIsAtEnd() {
        let detector = DefaultWordBoundaryDetector()

        let boundary = detector.detect(in: "ghbdtn", caretOffset: 6)

        #expect(boundary?.text == "ghbdtn")
        #expect(boundary?.range == 0..<6)
    }

    @Test
    func detectsWholeWordWhenCaretIsAtStart() {
        let detector = DefaultWordBoundaryDetector()

        let boundary = detector.detect(in: "ghbdtn", caretOffset: 0)

        #expect(boundary?.text == "ghbdtn")
        #expect(boundary?.range == 0..<6)
    }

    @Test
    func detectsWordWhenCaretIsInsideToken() {
        let detector = DefaultWordBoundaryDetector()

        let boundary = detector.detect(in: "ghbdtn", caretOffset: 3)

        #expect(boundary?.text == "ghbdtn")
        #expect(boundary?.range == 0..<6)
    }

    @Test
    func detectsPreviousWordWhenCaretFollowsWhitespace() {
        let detector = DefaultWordBoundaryDetector()

        let boundary = detector.detect(in: "hello ghbdtn", caretOffset: 11)

        #expect(boundary?.text == "ghbdtn")
        #expect(boundary?.range == 6..<12)
    }

    @Test
    func detectsPreviousWordWhenCaretFollowsDelimitedPunctuation() {
        let detector = DefaultWordBoundaryDetector()

        let boundary = detector.detect(in: "ghbdtn, ", caretOffset: 8)

        #expect(boundary?.text == "ghbdtn")
        #expect(boundary?.range == 0..<6)
    }

    @Test
    func detectsWordWrappedInPunctuation() {
        let detector = DefaultWordBoundaryDetector()

        let boundary = detector.detect(in: "(ghbdtn)!", caretOffset: 9)

        #expect(boundary?.text == "ghbdtn")
        #expect(boundary?.range == 1..<7)
    }

    @Test
    func ignoresPunctuationAndWhitespaceOnlyInputs() {
        let detector = DefaultWordBoundaryDetector()

        #expect(detector.detect(in: "!!!", caretOffset: 1) == nil)
        #expect(detector.detect(in: " ", caretOffset: 1) == nil)
        #expect(detector.detect(in: "", caretOffset: 0) == nil)
    }

    @Test
    func keepsDigitsAndUnderscoreInsideToken() {
        let detector = DefaultWordBoundaryDetector()

        let boundary = detector.detect(in: "ghbdtn_123", caretOffset: 10)

        #expect(boundary?.text == "ghbdtn_123")
        #expect(boundary?.range == 0..<10)
    }

    @Test
    func handlesEmojiPrefixWithCharacterOffsets() {
        let detector = DefaultWordBoundaryDetector()

        let clamped = detector.detect(in: "🎉ghbdtn", caretOffset: 8)
        #expect(clamped?.text == "ghbdtn")
        #expect(clamped?.range == 1..<7)

        let atEnd = detector.detect(in: "🎉ghbdtn", caretOffset: 7)
        #expect(atEnd?.text == "ghbdtn")
        #expect(atEnd?.range == 1..<7)
    }

    @Test
    func handlesCombiningMarksWithCharacterOffsets() {
        let detector = DefaultWordBoundaryDetector()
        let text = "cafe\u{0301} ghbdtn"

        let boundary = detector.detect(in: text, caretOffset: text.count)

        #expect(boundary?.text == "ghbdtn")
        #expect(boundary?.range == 5..<11)
    }

    @Test
    func doesNotTruncateTokensLongerThanWindow() {
        let detector = DefaultWordBoundaryDetector()

        let token300 = String(repeating: "a", count: 300)
        let boundary300 = detector.detect(in: token300, caretOffset: 150)
        #expect(boundary300?.text == token300)
        #expect(boundary300?.range == 0..<300)

        let token4096 = String(repeating: "a", count: 4096)
        let boundary4096 = detector.detect(in: token4096, caretOffset: 2048)
        #expect(boundary4096?.text == token4096)
        #expect(boundary4096?.range == 0..<4096)

        let padded = "   " + token300 + "   "
        let fromTrailingSpace = detector.detect(in: padded, caretOffset: padded.count)
        #expect(fromTrailingSpace?.text == token300)
        #expect(fromTrailingSpace?.range == 3..<303)

        let fromLeadingSpace = detector.detect(in: padded, caretOffset: 0)
        #expect(fromLeadingSpace?.text == token300)
        #expect(fromLeadingSpace?.range == 3..<303)
    }

    @Test
    func findsNearestTokenWhenCaretIsAtWindowEdgeInWhitespace() {
        let detector = DefaultWordBoundaryDetector()

        // "far" ends 257 characters before caret (outside the 256-char backward window),
        // while "near" is 1 space after caret inside the forward window.
        let textPastBackwardWindow = "far" + String(repeating: " ", count: 257) + "near"
        let forwardBoundary = detector.detect(in: textPastBackwardWindow, caretOffset: 3 + 256)
        #expect(forwardBoundary?.text == "near")
        #expect(forwardBoundary?.range == 260..<264)

        // "edge" ends 255 spaces before caret (its last character is at distance 256, inside the window).
        let textInsideBackwardWindow = "edge" + String(repeating: " ", count: 255) + " near"
        let backwardBoundary = detector.detect(in: textInsideBackwardWindow, caretOffset: 4 + 255)
        #expect(backwardBoundary?.text == "edge")
        #expect(backwardBoundary?.range == 0..<4)

        // Forward window: 255 spaces places "near" at offset 255 (inside the 256-char window),
        // while 256 spaces places "far" at offset 256 (outside the window).
        let textInsideForwardWindow = String(repeating: " ", count: 255) + "near"
        let nearForward = detector.detect(in: textInsideForwardWindow, caretOffset: 0)
        #expect(nearForward?.text == "near")
        #expect(nearForward?.range == 255..<259)

        let textOutsideForwardWindow = String(repeating: " ", count: 256) + "far"
        #expect(detector.detect(in: textOutsideForwardWindow, caretOffset: 0) == nil)
    }

    @Test
    func detectsSingleWordInLargeDocumentAroundCaret() {
        let detector = DefaultWordBoundaryDetector()
        let padding = String(repeating: " ", count: 50_000)
        let text = padding + "ghbdtn" + padding

        let boundary = detector.detect(in: text, caretOffset: 50_003)

        #expect(boundary?.text == "ghbdtn")
        #expect(boundary?.range == 50_000..<50_006)
    }

    @Test
    func detectsFollowingWordFromZeroAndReturnsNilForPunctuationOnly() {
        let detector = DefaultWordBoundaryDetector()

        let following = detector.detect(in: "   ghbdtn", caretOffset: 0)
        #expect(following?.text == "ghbdtn")
        #expect(following?.range == 3..<9)

        #expect(detector.detect(in: "...,,,!!!", caretOffset: 4) == nil)
    }
}
