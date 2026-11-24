import ApplicationServices
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

    @Test
    func replaceTextUsesDirectAXWriteWhenSupported() {
        let app = ApplicationIdentity(bundleIdentifier: "com.apple.Notes", displayName: "Notes")!
        let element = AXUIElementCreateApplication(4100)
        let accessor = InMemoryAXElementAccessor(
            text: "hello ghbdtn",
            selectedRange: SelectionRangeSnapshot(location: 6, length: 6)
        )
        let clipboard = FakeClipboardReplacement(outcome: .success)
        let service = makeService(app: app, element: element, accessor: accessor, clipboard: clipboard)

        let context = SelectionSnapshot(
            text: "ghbdtn",
            range: SelectionRangeSnapshot(location: 6, length: 6)
        )
        let target = TextTarget(
            application: app,
            snapshot: FocusedElementSnapshot(role: "AXTextField", subrole: nil, isSecure: false),
            element: element
        )

        let result = service.replaceText(
            target,
            range: context.range,
            context: context,
            expectedText: "ghbdtn",
            with: "привет"
        )

        #expect(result == .success(SelectionRangeSnapshot(location: 6, length: 6), viaClipboard: false))
        #expect(accessor.text == "hello привет")
        #expect(accessor.selectedRange == SelectionRangeSnapshot(location: 12, length: 0))
        #expect(clipboard.callCount == 0)
    }

    @Test
    func replaceTextFallsBackToClipboardWhenSelectedTextWriteIsUnsupported() {
        let app = ApplicationIdentity(bundleIdentifier: "com.apple.Notes", displayName: "Notes")!
        let element = AXUIElementCreateApplication(4100)
        let accessor = InMemoryAXElementAccessor(
            text: "hello ghbdtn",
            selectedRange: SelectionRangeSnapshot(location: 12, length: 0),
            selectedTextWriteError: .attributeUnsupported
        )
        var validatedTarget = false
        var verifiedReplacement = false
        let clipboard = FakeClipboardReplacement { expectedText, replacement, targetPID, validateTarget, verifyReplacement in
            #expect(expectedText == "ghbdtn")
            #expect(targetPID == 4100)
            validatedTarget = validateTarget()
            accessor.replaceSelectedRange(with: replacement)
            verifiedReplacement = verifyReplacement()
            return .success
        }
        let service = makeService(app: app, element: element, accessor: accessor, clipboard: clipboard)

        let context = SelectionSnapshot(
            text: "hello ghbdtn",
            range: SelectionRangeSnapshot(location: 12, length: 0),
            isCaretContext: true
        )
        let target = TextTarget(
            application: app,
            snapshot: FocusedElementSnapshot(role: "AXTextArea", subrole: nil, isSecure: false),
            element: element
        )

        let result = service.replaceText(
            target,
            range: SelectionRangeSnapshot(location: 6, length: 6),
            context: context,
            expectedText: "ghbdtn",
            with: "привет"
        )

        #expect(result == .success(SelectionRangeSnapshot(location: 6, length: 6), viaClipboard: true))
        #expect(validatedTarget)
        #expect(verifiedReplacement)
        #expect(clipboard.callCount == 1)
        #expect(accessor.text == "hello привет")
    }

    @Test
    func replaceTextNoOpsOnSecureFieldWithoutAXAccessOrClipboardFallback() {
        let app = ApplicationIdentity(bundleIdentifier: "com.apple.Notes", displayName: "Notes")!
        let element = AXUIElementCreateApplication(4100)
        let accessor = InMemoryAXElementAccessor(
            text: "secret",
            selectedRange: SelectionRangeSnapshot(location: 0, length: 6),
            selectedTextWriteError: .attributeUnsupported
        )
        let clipboard = FakeClipboardReplacement(outcome: .success)
        let service = makeService(
            app: app,
            element: element,
            isSecure: true,
            accessor: accessor,
            clipboard: clipboard
        )

        let context = SelectionSnapshot(
            text: "secret",
            range: SelectionRangeSnapshot(location: 0, length: 6)
        )
        let target = TextTarget(
            application: app,
            snapshot: FocusedElementSnapshot(role: "AXTextField", subrole: "AXSecureTextField", isSecure: true),
            element: element
        )

        let result = service.replaceText(
            target,
            range: context.range,
            context: context,
            expectedText: "secret",
            with: "ыускуе"
        )

        #expect(result == .unavailable(.secureField))
        #expect(accessor.readAttributes.isEmpty)
        #expect(accessor.writtenAttributes.isEmpty)
        #expect(clipboard.callCount == 0)
        #expect(accessor.text == "secret")
    }

    @Test
    func replaceTextRestoresContextRangeWhenClipboardFallbackAborts() {
        let app = ApplicationIdentity(bundleIdentifier: "com.apple.Notes", displayName: "Notes")!
        let element = AXUIElementCreateApplication(4100)
        let caretRange = SelectionRangeSnapshot(location: 12, length: 0)
        let wordRange = SelectionRangeSnapshot(location: 6, length: 6)
        let accessor = InMemoryAXElementAccessor(
            text: "hello ghbdtn",
            selectedRange: caretRange,
            selectedTextWriteError: .attributeUnsupported
        )
        let clipboard = FakeClipboardReplacement(outcome: .failed)
        let service = makeService(app: app, element: element, accessor: accessor, clipboard: clipboard)

        let context = SelectionSnapshot(
            text: "hello ghbdtn",
            range: caretRange,
            isCaretContext: true
        )
        let target = TextTarget(
            application: app,
            snapshot: FocusedElementSnapshot(role: "AXTextArea", subrole: nil, isSecure: false),
            element: element
        )

        let result = service.replaceText(
            target,
            range: wordRange,
            context: context,
            expectedText: "ghbdtn",
            with: "привет"
        )

        #expect(result == .unavailable(.unsupported))
        #expect(clipboard.callCount == 1)
        #expect(accessor.writtenRanges == [wordRange, caretRange])
        #expect(accessor.selectedRange == caretRange)
        #expect(accessor.text == "hello ghbdtn")
    }

    @Test
    func replaceTextDoesNotFallBackToClipboardOnNonUnsupportedAXWriteFailure() {
        let app = ApplicationIdentity(bundleIdentifier: "com.apple.Notes", displayName: "Notes")!
        let element = AXUIElementCreateApplication(4100)
        let caretRange = SelectionRangeSnapshot(location: 12, length: 0)
        let wordRange = SelectionRangeSnapshot(location: 6, length: 6)
        let accessor = InMemoryAXElementAccessor(
            text: "hello ghbdtn",
            selectedRange: caretRange,
            selectedTextWriteError: .cannotComplete
        )
        let clipboard = FakeClipboardReplacement(outcome: .success)
        let service = makeService(app: app, element: element, accessor: accessor, clipboard: clipboard)

        let context = SelectionSnapshot(
            text: "hello ghbdtn",
            range: caretRange,
            isCaretContext: true
        )
        let target = TextTarget(
            application: app,
            snapshot: FocusedElementSnapshot(role: "AXTextArea", subrole: nil, isSecure: false),
            element: element
        )

        let result = service.replaceText(
            target,
            range: wordRange,
            context: context,
            expectedText: "ghbdtn",
            with: "привет"
        )

        #expect(result == .unavailable(.accessibilityError(.cannotComplete)))
        #expect(clipboard.callCount == 0)
        #expect(accessor.writtenRanges == [wordRange, caretRange])
        #expect(accessor.selectedRange == caretRange)
    }

    private func makeService(
        app: ApplicationIdentity,
        element: AXUIElement,
        isSecure: Bool = false,
        pid: pid_t = 4100,
        accessor: InMemoryAXElementAccessor,
        clipboard: FakeClipboardReplacement
    ) -> AccessibilityTextService {
        let snapshot = FocusedElementSnapshot(
            role: "AXTextField",
            subrole: isSecure ? "AXSecureTextField" : nil,
            isSecure: isSecure
        )
        return AccessibilityTextService(
            clipboardReplacement: clipboard,
            applicationProvider: StubTextServiceAppProvider(app: app, pid: pid),
            permissionProbe: AccessibilityPermissionProbe(isTrustedProvider: { true }),
            elementAccessor: accessor,
            focusedElementResolver: {
                .success(ResolvedFocusedElement(element: element, snapshot: snapshot))
            }
        )
    }
}

private final class StubTextServiceAppProvider: ActiveApplicationProviding, @unchecked Sendable {
    let app: ApplicationIdentity
    let pid: pid_t

    init(app: ApplicationIdentity, pid: pid_t) {
        self.app = app
        self.pid = pid
    }

    func activeApplication() -> ApplicationIdentity? { app }
    func application(bundleIdentifier: String) -> ApplicationIdentity? {
        app.bundleIdentifier == bundleIdentifier ? app : nil
    }
    func activeProcessIdentifier(for application: ApplicationIdentity) -> pid_t? {
        application == app ? pid : nil
    }
}

private final class FakeClipboardReplacement: ClipboardReplacing {
    private let handler: (String, String, pid_t, () -> Bool, () -> Bool) -> ClipboardReplacementResult
    private(set) var callCount = 0

    init(outcome: ClipboardReplacementResult) {
        self.handler = { _, _, _, _, _ in outcome }
    }

    init(handler: @escaping (String, String, pid_t, () -> Bool, () -> Bool) -> ClipboardReplacementResult) {
        self.handler = handler
    }

    func replaceSelection(
        expectedText: String,
        with replacement: String,
        processIdentifier: pid_t,
        validateTarget: () -> Bool,
        verifyReplacement: () -> Bool
    ) -> ClipboardReplacementResult {
        callCount += 1
        return handler(expectedText, replacement, processIdentifier, validateTarget, verifyReplacement)
    }
}

private final class InMemoryAXElementAccessor: AccessibilityElementAccessing {
    var text: String
    var selectedRange: SelectionRangeSnapshot
    let selectedTextWriteError: AXError
    private(set) var readAttributes: [String] = []
    private(set) var writtenAttributes: [String] = []
    private(set) var writtenRanges: [SelectionRangeSnapshot] = []

    init(
        text: String,
        selectedRange: SelectionRangeSnapshot,
        selectedTextWriteError: AXError = .success
    ) {
        self.text = text
        self.selectedRange = selectedRange
        self.selectedTextWriteError = selectedTextWriteError
    }

    func copyAttributeValue(_ attribute: CFString, from element: AXUIElement) -> (AXError, CFTypeRef?) {
        let name = attribute as String
        readAttributes.append(name)
        switch name {
        case kAXValueAttribute:
            return (.success, text as CFTypeRef)
        case kAXSelectedTextRangeAttribute:
            var cfRange = CFRange(location: selectedRange.location, length: selectedRange.length)
            return (.success, AXValueCreate(.cfRange, &cfRange))
        case kAXSelectedTextAttribute:
            guard let substring = AccessibilityTextService.substring(in: selectedRange, of: text) else {
                return (.failure, nil)
            }
            return (.success, substring as CFTypeRef)
        default:
            return (.attributeUnsupported, nil)
        }
    }

    func setAttributeValue(_ attribute: CFString, value: CFTypeRef, on element: AXUIElement) -> AXError {
        let name = attribute as String
        writtenAttributes.append(name)
        switch name {
        case kAXSelectedTextRangeAttribute:
            guard CFGetTypeID(value) == AXValueGetTypeID() else {
                return .illegalArgument
            }
            let axValue = unsafeDowncast(value, to: AXValue.self)
            var cfRange = CFRange()
            guard AXValueGetValue(axValue, .cfRange, &cfRange) else {
                return .illegalArgument
            }
            let snapshot = SelectionRangeSnapshot(location: cfRange.location, length: cfRange.length)
            selectedRange = snapshot
            writtenRanges.append(snapshot)
            return .success
        case kAXSelectedTextAttribute:
            guard selectedTextWriteError == .success else {
                return selectedTextWriteError
            }
            guard let replacement = value as? String else {
                return .illegalArgument
            }
            replaceSelectedRange(with: replacement)
            return .success
        default:
            return .attributeUnsupported
        }
    }

    func replaceSelectedRange(with replacement: String) {
        let nsText = text as NSString
        let nsRange = NSRange(location: selectedRange.location, length: selectedRange.length)
        text = nsText.replacingCharacters(in: nsRange, with: replacement)
        let length = (replacement as NSString).length
        selectedRange = SelectionRangeSnapshot(location: selectedRange.location + length, length: 0)
    }
}
