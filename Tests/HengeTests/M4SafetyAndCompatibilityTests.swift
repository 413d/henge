import ApplicationServices
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

        let outcome = useCase.execute()

        #expect(outcome == .fixed(viaClipboard: false))
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

        let outcome = useCase.execute()

        #expect(outcome == .fixed(viaClipboard: false))
        #expect(runtime.directRange == SelectionRangeSnapshot(location: 5, length: 6))
        #expect(runtime.directReplacement == "привет")
    }

    @Test
    func excludedApplicationReturnsBeforeAccessibilityRead() {
        let runtime = M4RuntimeStub(context: .available(
            SelectionSnapshot(text: "ghbdtn", range: SelectionRangeSnapshot(location: 0, length: 6))
        ))
        let useCase = makeUseCase(runtime)

        let outcome = useCase.execute(excludingApplicationBundleIdentifiers: ["test.application"])

        #expect(outcome == .excluded)
        #expect(runtime.contextReadCount == 0)
        #expect(runtime.directReplacement == nil)
    }

    @Test
    func unsupportedAXReplacementUsesClipboardFallback() {
        let runtime = M4RuntimeStub(
            context: .available(SelectionSnapshot(text: "ghbdtn", range: SelectionRangeSnapshot(location: 0, length: 6))),
            directResult: .unavailable(.unsupported)
        )
        let outcome = makeUseCase(runtime).execute()

        #expect(outcome == .fixed(viaClipboard: true))
        #expect(runtime.clipboardReplacement == "привет")
        #expect(runtime.clipboardCallCount == 1)
    }

    @Test
    func secureFieldNeverReachesReplacementPaths() {
        let runtime = M4RuntimeStub(context: .unavailable(.secureField))
        let outcome = makeUseCase(runtime).execute()

        #expect(outcome == .secureField)
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

        let result = replacement.replaceSelection(expectedText: "ghbdtn", with: "привет") {
            poster.pastedText == "привет"
        }
        #expect(result == .success)
        #expect(pasteboard.lastTransientWrittenString == "привет")
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

        let result = replacement.replaceSelection(expectedText: "ghbdtn", with: "привет", verifyReplacement: { false })
        #expect(result == .failed)
        #expect(manager.restoredSnapshot == original)
    }

    @Test
    func clipboardFallbackWaitsForAXConfirmationBeforeRestoringClipboard() {
        let pasteboard = TestReplacementPasteboard(initialString: "original clipboard")
        let manager = TestReplacementClipboardManager(snapshot: ClipboardSnapshot.empty)
        let poster = TestClipboardEventPoster(pasteboard: pasteboard, copiedText: "ghbdtn")
        let replacement = AppKitClipboardReplacement(clipboardManager: manager, pasteboard: pasteboard, eventPoster: poster)
        var verificationCount = 0

        let result = replacement.replaceSelection(expectedText: "ghbdtn", with: "привет") {
            verificationCount += 1
            return verificationCount == 3
        }

        #expect(result == .success)
        #expect(verificationCount == 3)
        #expect(manager.restoredSnapshot == .empty)
    }

    @Test
    func clipboardFallbackReportsSnapshotRestorationFailure() {
        let pasteboard = TestReplacementPasteboard(initialString: "original clipboard")
        let manager = TestReplacementClipboardManager(snapshot: .empty, restorationSucceeds: false)
        let poster = TestClipboardEventPoster(pasteboard: pasteboard, copiedText: "ghbdtn")
        let replacement = AppKitClipboardReplacement(clipboardManager: manager, pasteboard: pasteboard, eventPoster: poster)

        let result = replacement.replaceSelection(expectedText: "ghbdtn", with: "привет", verifyReplacement: { true })
        #expect(result == .restoreFailed)
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

        let result = replacement.replaceSelection(expectedText: "ghbdtn", with: "привет", verifyReplacement: { true })

        #expect(result == .failed)
        #expect(pasteboard.changeCount == initialChangeCount)
        #expect(pasteboard.string() == "original clipboard")
        #expect(poster.copySucceeded == false)
        #expect(poster.pastedText == nil)
        #expect(manager.restoredSnapshot == nil)
    }

    @Test
    func replacementPasteIsMarkedTransient() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        let replacementPasteboard = AppKitReplacementPasteboard(pasteboard: pasteboard)
        let didWrite = replacementPasteboard.setTransientString("привет")

        #expect(didWrite)
        let item = pasteboard.pasteboardItems?.first
        #expect(item != nil)
        let types = Set(item?.types.map(\.rawValue) ?? [])
        #expect(types.contains("org.nspasteboard.TransientType"))
        #expect(types.contains("org.nspasteboard.ConcealedType"))
        #expect(item?.string(forType: .string) == "привет")
    }

    @Test
    func clipboardFallbackReportsUnverifiedPaste() {
        let pasteboard = TestReplacementPasteboard(initialString: "original clipboard")
        let original = ClipboardSnapshot(changeCount: 0, items: [PasteboardItemSnapshot(representations: [
            NSPasteboard.PasteboardType.string.rawValue: Data("original clipboard".utf8)
        ])])
        let manager = TestReplacementClipboardManager(snapshot: original)
        let poster = TestClipboardEventPoster(pasteboard: pasteboard, copiedText: "ghbdtn")
        let replacement = AppKitClipboardReplacement(
            clipboardManager: manager,
            pasteboard: pasteboard,
            operationBudget: 0.05,
            eventPoster: poster
        )

        let result = replacement.replaceSelection(expectedText: "ghbdtn", with: "привет", verifyReplacement: { false })

        #expect(result == .pasteUnverified)
        #expect(poster.pastedText == "привет")
        #expect(manager.restoredSnapshot == original)
    }

    @Test
    func restoreFailureIsReportedAsClipboardRestoreFailed() {
        let pasteboard = TestReplacementPasteboard(initialString: "original clipboard")
        let original = ClipboardSnapshot(changeCount: 0, items: [PasteboardItemSnapshot(representations: [
            NSPasteboard.PasteboardType.string.rawValue: Data("original clipboard".utf8)
        ])])
        let manager = TestReplacementClipboardManager(snapshot: original, restorationSucceeds: false)
        let poster = TestClipboardEventPoster(pasteboard: pasteboard, copiedText: "ghbdtn")
        let replacement = AppKitClipboardReplacement(clipboardManager: manager, pasteboard: pasteboard, eventPoster: poster)

        let result = replacement.replaceSelection(expectedText: "ghbdtn", with: "привет", verifyReplacement: { true })

        #expect(result == .restoreFailed)
        #expect(manager.restoredSnapshot == original)
    }

    @Test
    func clipboardFallbackSkipsRestoreWhenClipboardIsSuperseded() {
        let pasteboard = TestReplacementPasteboard(initialString: "original clipboard")
        let original = ClipboardSnapshot(changeCount: 0, items: [PasteboardItemSnapshot(representations: [
            NSPasteboard.PasteboardType.string.rawValue: Data("original clipboard".utf8)
        ])])
        let manager = TestReplacementClipboardManager(snapshot: original)
        let poster = TestClipboardEventPoster(pasteboard: pasteboard, copiedText: "ghbdtn")
        let replacement = AppKitClipboardReplacement(clipboardManager: manager, pasteboard: pasteboard, eventPoster: poster)

        let result = replacement.replaceSelection(expectedText: "ghbdtn", with: "привет") {
            _ = pasteboard.setString("user copied something else")
            return true
        }

        #expect(result == .superseded)
        #expect(manager.restoredSnapshot == nil)
        #expect(pasteboard.string() == "user copied something else")
    }

    @Test
    func clipboardRestoreIsSkippedWhenUserCopiedNewerContent() {
        let pasteboard = TestReplacementPasteboard(initialString: "original clipboard")
        let original = ClipboardSnapshot(changeCount: 0, items: [PasteboardItemSnapshot(representations: [
            NSPasteboard.PasteboardType.string.rawValue: Data("original clipboard".utf8)
        ])])
        let manager = TestReplacementClipboardManager(snapshot: original)
        let poster = TestClipboardEventPoster(pasteboard: pasteboard, copiedText: "ghbdtn") {
            _ = pasteboard.setString("new")
        }
        let replacement = AppKitClipboardReplacement(clipboardManager: manager, pasteboard: pasteboard, eventPoster: poster)

        let result = replacement.replaceSelection(expectedText: "ghbdtn", with: "привет", verifyReplacement: { true })

        #expect(result == .superseded)
        #expect(poster.pastedText == "привет")
        #expect(manager.restoredSnapshot == nil)
        #expect(pasteboard.string() == "new")
    }

    @Test
    func clipboardRestoreRunsWhenPasteboardWasNotTouched() {
        let pasteboard = TestReplacementPasteboard(initialString: "original clipboard")
        let original = ClipboardSnapshot(changeCount: 0, items: [PasteboardItemSnapshot(representations: [
            NSPasteboard.PasteboardType.string.rawValue: Data("original clipboard".utf8)
        ])])
        let manager = TestReplacementClipboardManager(snapshot: original)
        let poster = TestClipboardEventPoster(pasteboard: pasteboard, copiedText: "ghbdtn")
        let replacement = AppKitClipboardReplacement(clipboardManager: manager, pasteboard: pasteboard, eventPoster: poster)

        let result = replacement.replaceSelection(expectedText: "ghbdtn", with: "привет", verifyReplacement: { true })

        #expect(result == .success)
        #expect(poster.pastedText == "привет")
        #expect(manager.restoredSnapshot == original)
    }

    @Test
    func clipboardRestoreIsSkippedWhenTargetChangesAfterUserCopiedNewerContent() {
        let pasteboard = TestReplacementPasteboard(initialString: "original clipboard")
        let original = ClipboardSnapshot(changeCount: 0, items: [PasteboardItemSnapshot(representations: [
            NSPasteboard.PasteboardType.string.rawValue: Data("original clipboard".utf8)
        ])])
        let manager = TestReplacementClipboardManager(snapshot: original)
        let poster = TestClipboardEventPoster(pasteboard: pasteboard, copiedText: "ghbdtn")
        let replacement = AppKitClipboardReplacement(clipboardManager: manager, pasteboard: pasteboard, eventPoster: poster)
        var validationCalls = 0

        let result = replacement.replaceSelection(
            expectedText: "ghbdtn",
            with: "привет",
            validateTarget: {
                validationCalls += 1
                if validationCalls == 3 {
                    _ = pasteboard.setString("new")
                    return false
                }
                return true
            },
            verifyReplacement: { true }
        )

        #expect(result == .superseded)
        #expect(manager.restoredSnapshot == nil)
        #expect(pasteboard.string() == "new")
    }

    @Test
    func clipboardFallbackDoesNotExceedSingleOperationBudget() {
        let pasteboard = TestReplacementPasteboard(initialString: "original clipboard")
        let original = ClipboardSnapshot(changeCount: 0, items: [PasteboardItemSnapshot(representations: [
            NSPasteboard.PasteboardType.string.rawValue: Data("original clipboard".utf8)
        ])])
        let manager = TestReplacementClipboardManager(snapshot: original)
        let poster = TestClipboardEventPoster(pasteboard: pasteboard, copiedText: "ghbdtn", copyDelay: 0.08)
        let replacement = AppKitClipboardReplacement(
            clipboardManager: manager,
            pasteboard: pasteboard,
            operationBudget: 0.20,
            eventPoster: poster
        )
        var verificationCalls = 0
        let start = Date()

        let result = replacement.replaceSelection(expectedText: "ghbdtn", with: "привет") {
            verificationCalls += 1
            return false
        }

        let elapsed = Date().timeIntervalSince(start)
        #expect(result == .pasteUnverified)
        #expect(poster.pasteCount == 1)
        #expect(poster.pastedText == "привет")
        #expect(verificationCalls >= 2)
        #expect(elapsed < 0.26)
        #expect(manager.restoredSnapshot == original)
    }

    @Test
    func inspectionRejectsElementWhosePIDBelongsToDifferentApplication() {
        let notes = ApplicationIdentity(bundleIdentifier: "com.apple.Notes", displayName: "Notes")!
        let otherPID: pid_t = 9002
        let otherElement = AXUIElementCreateApplication(otherPID)
        let spyClipboard = SpyClipboardReplacement()
        let runtime = LiveAppRuntime(
            clipboardManager: MockClipboardManager(),
            clipboardReplacement: spyClipboard,
            applicationProvider: StubM4ApplicationProvider(activeApp: notes, pid: 4100),
            permissionProbe: AccessibilityPermissionProbe(isTrustedProvider: { true }),
            focusedElementResolver: {
                .success(ResolvedFocusedElement(
                    element: otherElement,
                    snapshot: FocusedElementSnapshot(role: "AXTextField", subrole: nil, isSecure: false)
                ))
            }
        )

        let probe = runtime.inspectTextContext(in: notes)
        #expect(probe == .unavailable(.noFocusedElement))

        let useCase = LiveFixTextUseCase(
            runtime: runtime,
            transformer: SimpleTextTransformer(detector: MajorityLayoutDetector(), mapper: runtime.layoutMapper)
        )
        let outcome = useCase.execute()
        #expect(outcome == .failed(.noFocusedElement))
        #expect(spyClipboard.callCount == 0)
    }

    @Test
    func secureSnapshotNeverReachesWriteOrReadsAXValue() {
        let notes = ApplicationIdentity(bundleIdentifier: "com.apple.Notes", displayName: "Notes")!
        let element = AXUIElementCreateApplication(4100)
        let spyClipboard = SpyClipboardReplacement()
        var resolveCount = 0
        let runtime = LiveAppRuntime(
            clipboardManager: MockClipboardManager(),
            clipboardReplacement: spyClipboard,
            applicationProvider: StubM4ApplicationProvider(activeApp: notes, pid: 4100),
            permissionProbe: AccessibilityPermissionProbe(isTrustedProvider: { true }),
            focusedElementResolver: {
                resolveCount += 1
                return .success(ResolvedFocusedElement(
                    element: element,
                    snapshot: FocusedElementSnapshot(role: "AXSecureTextField", subrole: "AXSecureTextField", isSecure: true)
                ))
            }
        )

        let probe = runtime.inspectTextContext(in: notes)
        #expect(probe == .unavailable(.secureField))
        #expect(resolveCount == 1)

        let secureTarget = TextTarget(
            application: notes,
            snapshot: FocusedElementSnapshot(role: "AXSecureTextField", subrole: "AXSecureTextField", isSecure: true),
            element: element
        )
        let snapshot = SelectionSnapshot(text: "secret", range: SelectionRangeSnapshot(location: 0, length: 6))
        let directResult = runtime.replaceText(
            secureTarget,
            range: snapshot.range,
            context: snapshot,
            expectedText: "secret",
            with: "ыускуе"
        )
        let clipboardResult = runtime.replaceTextUsingClipboard(
            secureTarget,
            range: snapshot.range,
            context: snapshot,
            expectedText: "secret",
            with: "ыускуе"
        )
        #expect(directResult == .unavailable(.secureField))
        #expect(clipboardResult == .unavailable(.secureField))
        #expect(resolveCount == 1)
        #expect(spyClipboard.callCount == 0)

        let stub = M4RuntimeStub(context: .unavailable(.secureField))
        let outcome = makeUseCase(stub).execute()
        #expect(outcome == .secureField)
        #expect(stub.axValueReadCount == 0)
        #expect(stub.directCallCount == 0)
        #expect(stub.clipboardCallCount == 0)
    }

    @Test
    func elementSwappedBetweenInspectionAndWriteFailsDirectWriteAndClipboardValidation() {
        let notes = ApplicationIdentity(bundleIdentifier: "com.apple.Notes", displayName: "Notes")!
        let originalElement = AXUIElementCreateApplication(4100)
        let swappedElement = AXUIElementCreateApplication(4101)
        let spyClipboard = SpyClipboardReplacement()
        var currentFocused = originalElement
        let runtime = LiveAppRuntime(
            clipboardManager: MockClipboardManager(),
            clipboardReplacement: spyClipboard,
            applicationProvider: StubM4ApplicationProvider(activeApp: notes, pid: 4100),
            permissionProbe: AccessibilityPermissionProbe(isTrustedProvider: { true }),
            focusedElementResolver: {
                .success(ResolvedFocusedElement(
                    element: currentFocused,
                    snapshot: FocusedElementSnapshot(role: "AXTextField", subrole: nil, isSecure: false)
                ))
            }
        )

        let target = TextTarget(
            application: notes,
            snapshot: FocusedElementSnapshot(role: "AXTextField", subrole: nil, isSecure: false),
            element: originalElement
        )
        let snapshot = SelectionSnapshot(text: "ghbdtn", range: SelectionRangeSnapshot(location: 0, length: 6))

        // Element swaps before write
        currentFocused = swappedElement

        let directResult = runtime.replaceText(
            target,
            range: snapshot.range,
            context: snapshot,
            expectedText: "ghbdtn",
            with: "привет"
        )
        #expect(directResult == .unavailable(.unsupported))

        let clipboardResult = runtime.replaceTextUsingClipboard(
            target,
            range: snapshot.range,
            context: snapshot,
            expectedText: "ghbdtn",
            with: "привет"
        )
        #expect(clipboardResult == .unavailable(.unsupported))
        #expect(spyClipboard.callCount == 0)

        // Also verify validateTarget aborting mid-clipboard-replacement prevents paste
        let pasteboard = TestReplacementPasteboard(initialString: "original clipboard")
        let original = ClipboardSnapshot(changeCount: 0, items: [PasteboardItemSnapshot(representations: [
            NSPasteboard.PasteboardType.string.rawValue: Data("original clipboard".utf8)
        ])])
        let manager = TestReplacementClipboardManager(snapshot: original)
        let poster = TestClipboardEventPoster(pasteboard: pasteboard, copiedText: "ghbdtn")
        let replacement = AppKitClipboardReplacement(clipboardManager: manager, pasteboard: pasteboard, eventPoster: poster)
        var validationCalls = 0
        let pasteResult = replacement.replaceSelection(
            expectedText: "ghbdtn",
            with: "привет",
            processIdentifier: 4100,
            validateTarget: {
                validationCalls += 1
                // Pass copy checks (1 & 2), fail paste check (3) after element swaps mid-flight
                return validationCalls < 3
            },
            verifyReplacement: { true }
        )
        #expect(pasteResult == .failed)
        #expect(poster.pasteCount == 0)
        #expect(poster.pastedText == nil)
        #expect(manager.restoredSnapshot == original)
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
    private let copyDelay: TimeInterval
    private let afterPaste: (() -> Void)?
    private(set) var pastedText: String?
    private(set) var pasteCount = 0
    private(set) var copySucceeded = false

    init(
        pasteboard: TestReplacementPasteboard,
        copiedText: String,
        copyDelay: TimeInterval = 0,
        afterPaste: (() -> Void)? = nil
    ) {
        self.pasteboard = pasteboard
        self.copiedText = copiedText
        self.copyDelay = copyDelay
        self.afterPaste = afterPaste
    }

    func postCommandKey(virtualKey: CGKeyCode) -> Bool {
        if virtualKey == 8 {
            if copyDelay > 0 {
                pasteboard.scheduleCopy(copiedText, after: copyDelay)
                copySucceeded = true
                return true
            }
            pasteboard.clear()
            copySucceeded = pasteboard.setString(copiedText)
            return copySucceeded
        }
        if virtualKey == 9 {
            pasteCount += 1
            pastedText = pasteboard.string()
            afterPaste?()
            return true
        }
        return false
    }
}

private final class TestReplacementPasteboard: ReplacementPasteboard {
    private var storedChangeCount = 0
    private var contents: String?
    private var pendingCopy: (text: String, readyAt: Date)?
    private(set) var lastTransientWrittenString: String?

    var changeCount: Int {
        flushPendingCopyIfReady()
        return storedChangeCount
    }

    init(initialString: String?) {
        contents = initialString
    }

    func scheduleCopy(_ string: String, after delay: TimeInterval) {
        pendingCopy = (string, Date().addingTimeInterval(delay))
    }

    func string() -> String? {
        flushPendingCopyIfReady()
        return contents
    }

    func clear() {
        pendingCopy = nil
        contents = nil
        storedChangeCount += 1
    }

    func setString(_ string: String) -> Bool {
        pendingCopy = nil
        contents = string
        storedChangeCount += 1
        return true
    }

    func setTransientString(_ string: String) -> Bool {
        pendingCopy = nil
        lastTransientWrittenString = string
        contents = string
        storedChangeCount += 1
        return true
    }

    private func flushPendingCopyIfReady() {
        guard let pendingCopy, Date() >= pendingCopy.readyAt else { return }
        self.pendingCopy = nil
        contents = pendingCopy.text
        storedChangeCount += 1
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
    private let context: SelectionProbe
    private let directResult: SelectionWriteResult
    private(set) var contextReadCount = 0
    private(set) var axValueReadCount = 0
    private(set) var directCallCount = 0
    private(set) var clipboardCallCount = 0
    private(set) var directRange: SelectionRangeSnapshot?
    private(set) var directReplacement: String?
    private(set) var clipboardReplacement: String?

    init(context: SelectionProbe, directResult: SelectionWriteResult = .success(SelectionRangeSnapshot(location: 0, length: 0))) {
        self.context = context
        self.directResult = directResult
    }

    func openAccessibilitySettings() {}
    func registerFixTextHotkey(_ shortcut: Shortcut, handler: @escaping () -> Void) throws {}
    func unregisterFixTextHotkey() {}
    func inspectFocusedElement() -> FocusedElementProbe { .available(FocusedElementSnapshot(role: "AXTextField", subrole: nil, isSecure: false)) }
    func inspectTextContext(in application: ApplicationIdentity) -> TextContextProbe {
        contextReadCount += 1
        if case .available = context {
            axValueReadCount += 1
        }
        return makeTestTextContext(context, in: application)
    }

    func replaceText(_ target: TextTarget, range: SelectionRangeSnapshot, context: SelectionSnapshot, expectedText: String, with text: String) -> SelectionWriteResult {
        directCallCount += 1
        directRange = range
        directReplacement = text
        return directResult
    }

    func replaceTextUsingClipboard(_ target: TextTarget, range: SelectionRangeSnapshot, context: SelectionSnapshot, expectedText: String, with text: String) -> SelectionWriteResult {
        clipboardCallCount += 1
        clipboardReplacement = text
        return .success(SelectionRangeSnapshot(location: range.location, length: text.utf16.count))
    }
}

private final class SpyClipboardReplacement: ClipboardReplacing {
    private(set) var callCount = 0

    func replaceSelection(expectedText: String, with replacement: String, verifyReplacement: () -> Bool) -> ClipboardReplacementResult {
        callCount += 1
        return .failed
    }
}

private final class StubM4ApplicationProvider: ActiveApplicationProviding, @unchecked Sendable {
    private let activeApp: ApplicationIdentity
    private let pid: pid_t

    init(activeApp: ApplicationIdentity, pid: pid_t) {
        self.activeApp = activeApp
        self.pid = pid
    }

    func activeApplication() -> ApplicationIdentity? { activeApp }
    func application(bundleIdentifier: String) -> ApplicationIdentity? {
        activeApp.bundleIdentifier == bundleIdentifier ? activeApp : nil
    }
    func activeProcessIdentifier(for application: ApplicationIdentity) -> pid_t? {
        application.bundleIdentifier == activeApp.bundleIdentifier ? pid : nil
    }
}
