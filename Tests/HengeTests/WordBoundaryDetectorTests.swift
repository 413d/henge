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
}
