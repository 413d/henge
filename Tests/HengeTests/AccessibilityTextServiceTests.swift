import Foundation
import Testing

@testable import Henge

/// Covers `AccessibilityTextService.substring(in:of:)`, which paste verification
/// uses on text polled from the target application. The polled text can be shorter
/// than the range captured before the paste, so out-of-bounds ranges must return
/// `nil` instead of trapping inside `String.Index(utf16Offset:in:)`.
@Suite("AccessibilityTextService")
struct AccessibilityTextServiceTests {
    @Test
    func extractsRangeInsideText() {
        let text = "ghbdtn world"
        #expect(
            AccessibilityTextService.substring(
                in: SelectionRangeSnapshot(location: 0, length: 6),
                of: text
            ) == "ghbdtn"
        )
    }

    @Test
    func extractsEmptyRangeAtEndOfText() {
        let text = "ghbdtn"
        #expect(
            AccessibilityTextService.substring(
                in: SelectionRangeSnapshot(location: 6, length: 0),
                of: text
            ) == ""
        )
    }

    @Test
    func returnsNilWhenRangeExceedsTextLength() {
        let text = "hi"
        #expect(
            AccessibilityTextService.substring(
                in: SelectionRangeSnapshot(location: 0, length: 6),
                of: text
            ) == nil
        )
    }

    @Test
    func returnsNilWhenStartOffsetExceedsTextLength() {
        let text = "hi"
        #expect(
            AccessibilityTextService.substring(
                in: SelectionRangeSnapshot(location: 99, length: 0),
                of: text
            ) == nil
        )
    }

    @Test
    func returnsNilForEmptyPolledTextAgainstNonEmptyRange() {
        #expect(
            AccessibilityTextService.substring(
                in: SelectionRangeSnapshot(location: 0, length: 6),
                of: ""
            ) == nil
        )
        #expect(
            AccessibilityTextService.substring(
                in: SelectionRangeSnapshot(location: 0, length: 0),
                of: ""
            ) == ""
        )
    }

    @Test
    func returnsNilForNegativeComponents() {
        let text = "ghbdtn"
        #expect(
            AccessibilityTextService.substring(
                in: SelectionRangeSnapshot(location: -1, length: 2),
                of: text
            ) == nil
        )
        #expect(
            AccessibilityTextService.substring(
                in: SelectionRangeSnapshot(location: 0, length: -2),
                of: text
            ) == nil
        )
    }

    @Test
    func returnsNilWhenRangeSplitsSurrogatePair() {
        let text = "🎉ghbdtn"
        // The emoji occupies two UTF-16 code units, so offset 1 lands inside it.
        #expect(
            AccessibilityTextService.substring(
                in: SelectionRangeSnapshot(location: 1, length: 2),
                of: text
            ) == nil
        )
        #expect(
            AccessibilityTextService.substring(
                in: SelectionRangeSnapshot(location: 2, length: 6),
                of: text
            ) == "ghbdtn"
        )
    }
}
