import Foundation
import AppKit
import CoreGraphics
import Testing
@testable import Henge

struct M4SafetyAndCompatibilityTests {
    @Test
    func selectionTakesPriorityOverCaretResolution() {
        let runtime = M4RuntimeStub(context: .available(
            SelectionSnapshot(text: "ghbdtn", range: SelectionRangeSnapshot(location: 4, length: 6))
        ))
        let useCase = makeUseCase(runtime)

        useCase.execute()

        #expect(runtime.directRange == SelectionRangeSnapshot(location: 4, length: 6))
        #expect(runtime.directReplacement == "привет")
    }

    @Test
    func caretInsideTokenReplacesWholeWordAndPreservesUtf16Range() {
        let runtime = M4RuntimeStub(context: .available(
            SelectionSnapshot(
                text: "café ghbdtn!",
                range: SelectionRangeSnapshot(location: 9, length: 0),
                isCaretContext: true
            )
        ))
        let useCase = makeUseCase(runtime)

        useCase.execute()

        #expect(runtime.directRange == SelectionRangeSnapshot(location: 5, length: 6))
        #expect(runtime.directReplacement == "привет")
    }

    @Test
    func excludedApplicationReturnsBeforeAccessibilityRead() {
        let runtime = M4RuntimeStub(context: .available(
            SelectionSnapshot(text: "ghbdtn", range: SelectionRangeSnapshot(location: 0, length: 6))
        ))
        let useCase = makeUseCase(runtime)

        useCase.execute(excludingApplicationBundleIdentifiers: ["test.application"])

        #expect(runtime.contextReadCount == 0)
        #expect(runtime.directReplacement == nil)
    }

    @Test
    func unsupportedAXReplacementUsesClipboardFallback() {
        let runtime = M4RuntimeStub(
            context: .available(SelectionSnapshot(text: "ghbdtn", range: SelectionRangeSnapshot(location: 0, length: 6))),
            directResult: .unavailable(.unsupported)
        )
        makeUseCase(runtime).execute()

        #expect(runtime.clipboardReplacement == "привет")
        #expect(runtime.clipboardCallCount == 1)
    }

    @Test
    func secureFieldNeverReachesReplacementPaths() {
        let runtime = M4RuntimeStub(context: .unavailable(.secureField))
        makeUseCase(runtime).execute()

        #expect(runtime.directCallCount == 0)
        #expect(runtime.clipboardCallCount == 0)
    }

    @Test
    func exceptionManagerPreventsDuplicatesAndRemovesByBundleID() {
        let manager = ExceptionManager()
        let application = ApplicationIdentity(bundleIdentifier: "com.example.Editor", displayName: "Editor")!

        let added = manager.add(application, to: [application.bundleIdentifier])
        #expect(added == [application.bundleIdentifier])
        #expect(manager.remove(bundleIdentifier: application.bundleIdentifier, from: added).isEmpty)
    }

    @Test
    func oldConfigurationWithoutExceptionsStillLoads() throws {
        let data = Data(#"{"schemaVersion":1,"isEnabled":false,"shortcut":{"key":"X","modifiers":2}}"#.utf8)
        let configuration = try JSONDecoder().decode(AppConfiguration.self, from: data)

        #expect(configuration.isEnabled == false)
        #expect(configuration.excludedApplicationBundleIdentifiers.isEmpty)
    }

    @Test
    func clipboardFallbackRestoresFullSnapshotAfterSuccess() {
        let pasteboard = TestReplacementPasteboard(initialString: "original clipboard")
        let original = ClipboardSnapshot(changeCount: 0, items: [PasteboardItemSnapshot(representations: [
            NSPasteboard.PasteboardType.string.rawValue: Data("original clipboard".utf8),
            NSPasteboard.PasteboardType.html.rawValue: Data("<b>original clipboard</b>".utf8)
        ])])
        let manager = TestReplacementClipboardManager(snapshot: original)
        let poster = TestClipboardEventPoster(pasteboard: pasteboard, copiedText: "ghbdtn")
        let replacement = AppKitClipboardReplacement(clipboardManager: manager, pasteboard: pasteboard, eventPoster: poster)

        let didReplace = replacement.replaceSelection(expectedText: "ghbdtn", with: "привет") {
            poster.pastedText == "привет"
        }
        #expect(didReplace)
        #expect(poster.copySucceeded)
        #expect(poster.pastedText == "привет")
        #expect(manager.restoredSnapshot == original)
    }

    @Test
    func clipboardFallbackRestoresSnapshotWhenCopiedSelectionDoesNotMatch() {
        let pasteboard = TestReplacementPasteboard(initialString: "original clipboard")
        let original = ClipboardSnapshot(changeCount: 0, items: [PasteboardItemSnapshot(representations: [
            NSPasteboard.PasteboardType.string.rawValue: Data("original clipboard".utf8)
        ])])
        let manager = TestReplacementClipboardManager(snapshot: original)
        let poster = TestClipboardEventPoster(pasteboard: pasteboard, copiedText: "different selection")
        let replacement = AppKitClipboardReplacement(clipboardManager: manager, pasteboard: pasteboard, eventPoster: poster)

        #expect(!replacement.replaceSelection(expectedText: "ghbdtn", with: "привет", verifyReplacement: { false }))
        #expect(manager.restoredSnapshot == original)
    }

    @Test
    func clipboardFallbackWaitsForAXConfirmationBeforeRestoringClipboard() {
        let pasteboard = TestReplacementPasteboard(initialString: "original clipboard")
        let manager = TestReplacementClipboardManager(snapshot: ClipboardSnapshot.empty)
        let poster = TestClipboardEventPoster(pasteboard: pasteboard, copiedText: "ghbdtn")
        let replacement = AppKitClipboardReplacement(clipboardManager: manager, pasteboard: pasteboard, eventPoster: poster)
        var verificationCount = 0

        let didReplace = replacement.replaceSelection(expectedText: "ghbdtn", with: "привет") {
            verificationCount += 1
            return verificationCount == 3
        }

        #expect(didReplace)
        #expect(verificationCount == 3)
        #expect(manager.restoredSnapshot == .empty)
    }

    @Test
    func clipboardFallbackReportsSnapshotRestorationFailure() {
        let pasteboard = TestReplacementPasteboard(initialString: "original clipboard")
        let manager = TestReplacementClipboardManager(snapshot: .empty, restorationSucceeds: false)
        let poster = TestClipboardEventPoster(pasteboard: pasteboard, copiedText: "ghbdtn")
        let replacement = AppKitClipboardReplacement(clipboardManager: manager, pasteboard: pasteboard, eventPoster: poster)

        #expect(!replacement.replaceSelection(expectedText: "ghbdtn", with: "привет", verifyReplacement: { true }))
        #expect(poster.pastedText == "привет")
        #expect(manager.restoredSnapshot == .empty)
    }

    @Test
    func clipboardFallbackSkipsWhenSnapshotIsOversized() {
        let pasteboard = TestReplacementPasteboard(initialString: "original clipboard")
        let initialChangeCount = pasteboard.changeCount
        let oversizedSnapshot = ClipboardSnapshot(
            changeCount: initialChangeCount,
            items: [PasteboardItemSnapshot(representations: [
                "public.png": Data([0x01, 0x02, 0x03])
            ])],
            oversizedTypes: ["public.png"]
        )
        let manager = TestReplacementClipboardManager(snapshot: oversizedSnapshot)
        let poster = TestClipboardEventPoster(pasteboard: pasteboard, copiedText: "ghbdtn")
        let replacement = AppKitClipboardReplacement(clipboardManager: manager, pasteboard: pasteboard, eventPoster: poster)

        let didReplace = replacement.replaceSelection(expectedText: "ghbdtn", with: "привет", verifyReplacement: { true })

        #expect(didReplace == false)
        #expect(pasteboard.changeCount == initialChangeCount)
        #expect(pasteboard.string() == "original clipboard")
        #expect(poster.copySucceeded == false)
        #expect(poster.pastedText == nil)
        #expect(manager.restoredSnapshot == nil)
    }

    private func makeUseCase(_ runtime: M4RuntimeStub) -> LiveFixTextUseCase {
        LiveFixTextUseCase(
            runtime: runtime,
            transformer: SimpleTextTransformer(detector: MajorityLayoutDetector(), mapper: runtime.layoutMapper)
        )
    }
}

private final class TestClipboardEventPoster: ClipboardEventPosting {
    private let pasteboard: TestReplacementPasteboard
    private let copiedText: String
    private(set) var pastedText: String?
    private(set) var copySucceeded = false

    init(pasteboard: TestReplacementPasteboard, copiedText: String) {
        self.pasteboard = pasteboard
        self.copiedText = copiedText
    }

    func postCommandKey(virtualKey: CGKeyCode) -> Bool {
        if virtualKey == 8 {
            pasteboard.clear()
            copySucceeded = pasteboard.setString(copiedText)
            return copySucceeded
        }
        if virtualKey == 9 {
            pastedText = pasteboard.string()
            return true
        }
        return false
    }
}

private final class TestReplacementPasteboard: ReplacementPasteboard {
    private(set) var changeCount = 0
    private var contents: String?

    init(initialString: String?) {
        contents = initialString
    }

    func string() -> String? { contents }

    func clear() {
        contents = nil
        changeCount += 1
    }

    func setString(_ string: String) -> Bool {
        contents = string
        changeCount += 1
        return true
    }
}

private final class TestReplacementClipboardManager: ClipboardManaging, @unchecked Sendable {
    private let originalSnapshot: ClipboardSnapshot
    private let restorationSucceeds: Bool
    private(set) var restoredSnapshot: ClipboardSnapshot?

    init(snapshot: ClipboardSnapshot, restorationSucceeds: Bool = true) {
        originalSnapshot = snapshot
        self.restorationSucceeds = restorationSucceeds
    }

    func snapshot() -> ClipboardSnapshot { originalSnapshot }

    func restore(_ snapshot: ClipboardSnapshot) -> Bool {
        restoredSnapshot = snapshot
        return restorationSucceeds
    }
}

private final class M4RuntimeStub: AppRuntime {
    var hasAccessibilityPermission = true
    var activeApplication: ApplicationIdentity? = ApplicationIdentity(bundleIdentifier: "test.application", displayName: "Test")
    let layoutMapper: LayoutMapping = NativeKeyboardLayoutMapper()
    let clipboardManager: ClipboardManaging = MockClipboardManager()
    private let context: TextContextProbe
    private let directResult: SelectionWriteResult
    private(set) var contextReadCount = 0
    private(set) var directCallCount = 0
    private(set) var clipboardCallCount = 0
    private(set) var directRange: SelectionRangeSnapshot?
    private(set) var directReplacement: String?
    private(set) var clipboardReplacement: String?

    init(context: TextContextProbe, directResult: SelectionWriteResult = .success(SelectionRangeSnapshot(location: 0, length: 0))) {
        self.context = context
        self.directResult = directResult
    }

    func openAccessibilitySettings() {}
    func registerFixTextHotkey(_ shortcut: Shortcut, handler: @escaping () -> Void) throws {}
    func unregisterFixTextHotkey() {}
    func inspectFocusedElement() -> FocusedElementProbe { .available(FocusedElementSnapshot(role: "AXTextField", subrole: nil, isSecure: false)) }
    func inspectSelection() -> SelectionProbe { .unavailable(.noSelection) }
    func inspectTextContext() -> TextContextProbe {
        contextReadCount += 1
        return context
    }
    func replaceSelection(with text: String) -> SelectionWriteResult { directResult }

    func replaceText(in range: SelectionRangeSnapshot, context: SelectionSnapshot, expectedText: String, with text: String) -> SelectionWriteResult {
        directCallCount += 1
        directRange = range
        directReplacement = text
        return directResult
    }

    func replaceTextUsingClipboard(in range: SelectionRangeSnapshot, context: SelectionSnapshot, expectedText: String, with text: String) -> SelectionWriteResult {
        clipboardCallCount += 1
        clipboardReplacement = text
        return .success(SelectionRangeSnapshot(location: range.location, length: text.utf16.count))
    }
}
