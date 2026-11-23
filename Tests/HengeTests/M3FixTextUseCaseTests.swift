import ApplicationServices
import Testing
@testable import Henge

struct M3FixTextUseCaseTests {
    @Test
    func liveUseCaseTransformsSelectionText() {
        let runtime = SelectionStubRuntime(selection: .available(
            SelectionSnapshot(text: "ghbdtn", range: SelectionRangeSnapshot(location: 0, length: 6))
        ))
        let useCase = LiveFixTextUseCase(
            runtime: runtime,
            transformer: SimpleTextTransformer(
                detector: MajorityLayoutDetector(),
                mapper: runtime.layoutMapper
            )
        )

        let outcome = useCase.execute()

        #expect(outcome == .fixed(viaClipboard: false))
        #expect(runtime.replacedText == "привет")
        #expect(runtime.replaceCallCount == 1)
    }

    @Test
    func liveUseCasePreservesTitleCaseSelectionText() {
        let runtime = SelectionStubRuntime(selection: .available(
            SelectionSnapshot(text: "Ghbdtn", range: SelectionRangeSnapshot(location: 0, length: 6))
        ))
        let useCase = LiveFixTextUseCase(
            runtime: runtime,
            transformer: SimpleTextTransformer(
                detector: MajorityLayoutDetector(),
                mapper: runtime.layoutMapper
            )
        )

        let outcome = useCase.execute()

        #expect(outcome == .fixed(viaClipboard: false))
        #expect(runtime.replacedText == "Привет")
        #expect(runtime.replaceCallCount == 1)
    }

    @Test
    func liveUseCaseTransformsRussianSelectionText() {
        let runtime = SelectionStubRuntime(selection: .available(
            SelectionSnapshot(text: "Привет", range: SelectionRangeSnapshot(location: 0, length: 6))
        ))
        let useCase = LiveFixTextUseCase(
            runtime: runtime,
            transformer: SimpleTextTransformer(
                detector: MajorityLayoutDetector(),
                mapper: runtime.layoutMapper
            )
        )

        let outcome = useCase.execute()

        #expect(outcome == .fixed(viaClipboard: false))
        #expect(runtime.replacedText == "Ghbdtn")
        #expect(runtime.replaceCallCount == 1)
    }

    @Test
    func liveUseCasePreservesUppercaseSelectionText() {
        let runtime = SelectionStubRuntime(selection: .available(
            SelectionSnapshot(text: "GHBDTN", range: SelectionRangeSnapshot(location: 0, length: 6))
        ))
        let useCase = LiveFixTextUseCase(
            runtime: runtime,
            transformer: SimpleTextTransformer(
                detector: MajorityLayoutDetector(),
                mapper: runtime.layoutMapper
            )
        )

        let outcome = useCase.execute()

        #expect(outcome == .fixed(viaClipboard: false))
        #expect(runtime.replacedText == "ПРИВЕТ")
        #expect(runtime.replaceCallCount == 1)
    }

    @Test
    func liveUseCaseSkipsNoOpSelectionAndReturnsNothingToFix() {
        let runtime = SelectionStubRuntime(selection: .available(
            SelectionSnapshot(text: "12345", range: SelectionRangeSnapshot(location: 0, length: 5))
        ))
        let useCase = LiveFixTextUseCase(
            runtime: runtime,
            transformer: SimpleTextTransformer(
                detector: MajorityLayoutDetector(),
                mapper: runtime.layoutMapper
            )
        )

        let outcome = useCase.execute()

        #expect(outcome == .nothingToFix)
        #expect(runtime.replacedText == nil)
        #expect(runtime.replaceCallCount == 0)
    }

    @Test
    func liveUseCaseReturnsClipboardFallbackSuccessOutcome() {
        let runtime = OutcomeStubRuntime(
            selection: .available(
                SelectionSnapshot(text: "ghbdtn", range: SelectionRangeSnapshot(location: 0, length: 6))
            ),
            directResult: .unavailable(.unsupported),
            clipboardResult: .success(SelectionRangeSnapshot(location: 0, length: 6))
        )
        let useCase = LiveFixTextUseCase(
            runtime: runtime,
            transformer: SimpleTextTransformer(
                detector: MajorityLayoutDetector(),
                mapper: runtime.layoutMapper
            )
        )

        let outcome = useCase.execute()

        #expect(outcome == .fixed(viaClipboard: true))
    }

    @Test
    func liveUseCaseReturnsDirectSuccessAndClipboardFailureOutcomes() {
        let directRuntime = OutcomeStubRuntime(
            selection: .available(
                SelectionSnapshot(text: "ghbdtn", range: SelectionRangeSnapshot(location: 0, length: 6))
            ),
            directResult: .success(SelectionRangeSnapshot(location: 0, length: 6)),
            clipboardResult: .unavailable(.unsupported)
        )
        let directOutcome = LiveFixTextUseCase(
            runtime: directRuntime,
            transformer: SimpleTextTransformer(
                detector: MajorityLayoutDetector(),
                mapper: directRuntime.layoutMapper
            )
        ).execute()
        #expect(directOutcome == .fixed(viaClipboard: false))

        let unverifiedRuntime = OutcomeStubRuntime(
            selection: .available(
                SelectionSnapshot(text: "ghbdtn", range: SelectionRangeSnapshot(location: 0, length: 6))
            ),
            directResult: .unavailable(.unsupported),
            clipboardResult: .unavailable(.pasteUnverified)
        )
        let unverifiedOutcome = LiveFixTextUseCase(
            runtime: unverifiedRuntime,
            transformer: SimpleTextTransformer(
                detector: MajorityLayoutDetector(),
                mapper: unverifiedRuntime.layoutMapper
            )
        ).execute()
        #expect(unverifiedOutcome == .pasteUnverified)

        let restoreFailedRuntime = OutcomeStubRuntime(
            selection: .available(
                SelectionSnapshot(text: "ghbdtn", range: SelectionRangeSnapshot(location: 0, length: 6))
            ),
            directResult: .unavailable(.unsupported),
            clipboardResult: .unavailable(.clipboardRestoreFailed)
        )
        let restoreFailedOutcome = LiveFixTextUseCase(
            runtime: restoreFailedRuntime,
            transformer: SimpleTextTransformer(
                detector: MajorityLayoutDetector(),
                mapper: restoreFailedRuntime.layoutMapper
            )
        ).execute()
        #expect(restoreFailedOutcome == .failed(.clipboardRestoreFailed))

        let supersededRuntime = OutcomeStubRuntime(
            selection: .available(
                SelectionSnapshot(text: "ghbdtn", range: SelectionRangeSnapshot(location: 0, length: 6))
            ),
            directResult: .unavailable(.unsupported),
            clipboardResult: .unavailable(.clipboardSuperseded)
        )
        let supersededOutcome = LiveFixTextUseCase(
            runtime: supersededRuntime,
            transformer: SimpleTextTransformer(
                detector: MajorityLayoutDetector(),
                mapper: supersededRuntime.layoutMapper
            )
        ).execute()
        #expect(supersededOutcome == .failed(.clipboardSuperseded))
    }

    @Test
    func liveUseCaseReturnsStructuredOutcomesForNonSuccessPaths() {
        let noAppRuntime = OutcomeStubRuntime(
            activeApplication: nil,
            selection: .unavailable(.noFocusedElement),
            directResult: .unavailable(.unsupported),
            clipboardResult: .unavailable(.unsupported)
        )
        #expect(makeUseCase(noAppRuntime).execute() == .failed(.noActiveApplication))

        let excludedRuntime = OutcomeStubRuntime(
            selection: .available(SelectionSnapshot(text: "ghbdtn", range: SelectionRangeSnapshot(location: 0, length: 6))),
            directResult: .success(SelectionRangeSnapshot(location: 0, length: 6)),
            clipboardResult: .unavailable(.unsupported)
        )
        #expect(
            makeUseCase(excludedRuntime).execute(excludingApplicationBundleIdentifiers: ["test.application"]) == .excluded
        )

        let missingPermissionRuntime = OutcomeStubRuntime(
            selection: .unavailable(.missingPermission),
            directResult: .unavailable(.unsupported),
            clipboardResult: .unavailable(.unsupported)
        )
        #expect(makeUseCase(missingPermissionRuntime).execute() == .failed(.missingPermission))

        let noFocusedRuntime = OutcomeStubRuntime(
            selection: .unavailable(.noFocusedElement),
            directResult: .unavailable(.unsupported),
            clipboardResult: .unavailable(.unsupported)
        )
        #expect(makeUseCase(noFocusedRuntime).execute() == .failed(.noFocusedElement))

        let secureRuntime = OutcomeStubRuntime(
            selection: .unavailable(.secureField),
            directResult: .unavailable(.unsupported),
            clipboardResult: .unavailable(.unsupported)
        )
        #expect(makeUseCase(secureRuntime).execute() == .secureField)

        let noSelectionRuntime = OutcomeStubRuntime(
            selection: .unavailable(.noSelection),
            directResult: .unavailable(.unsupported),
            clipboardResult: .unavailable(.unsupported)
        )
        #expect(makeUseCase(noSelectionRuntime).execute() == .nothingToFix)

        let axErrorRuntime = OutcomeStubRuntime(
            selection: .unavailable(.accessibilityError(.cannotComplete)),
            directResult: .unavailable(.unsupported),
            clipboardResult: .unavailable(.unsupported)
        )
        #expect(makeUseCase(axErrorRuntime).execute() == .failed(.accessibilityError(AXError.cannotComplete.rawValue)))

        let unsupportedRuntime = OutcomeStubRuntime(
            selection: .available(SelectionSnapshot(text: "ghbdtn", range: SelectionRangeSnapshot(location: 0, length: 6))),
            directResult: .unavailable(.unsupported),
            clipboardResult: .unavailable(.unsupported)
        )
        #expect(makeUseCase(unsupportedRuntime).execute() == .unsupported)
    }

    private func makeUseCase(_ runtime: OutcomeStubRuntime) -> LiveFixTextUseCase {
        LiveFixTextUseCase(
            runtime: runtime,
            transformer: SimpleTextTransformer(
                detector: MajorityLayoutDetector(),
                mapper: runtime.layoutMapper
            )
        )
    }
}

private final class OutcomeStubRuntime: AppRuntime {
    var hasAccessibilityPermission: Bool { true }
    var activeApplication: ApplicationIdentity?
    let layoutMapper: LayoutMapping = NativeKeyboardLayoutMapper()
    let clipboardManager: ClipboardManaging = MockClipboardManager()

    private let selection: SelectionProbe
    private let directResult: SelectionWriteResult
    private let clipboardResult: SelectionWriteResult

    init(
        activeApplication: ApplicationIdentity? = ApplicationIdentity(bundleIdentifier: "test.application", displayName: "Test Application"),
        selection: SelectionProbe,
        directResult: SelectionWriteResult,
        clipboardResult: SelectionWriteResult
    ) {
        self.activeApplication = activeApplication
        self.selection = selection
        self.directResult = directResult
        self.clipboardResult = clipboardResult
    }

    func openAccessibilitySettings() {}
    func registerFixTextHotkey(_ shortcut: Shortcut, handler: @escaping () -> Void) throws {}
    func unregisterFixTextHotkey() {}
    func inspectFocusedElement() -> FocusedElementProbe {
        .available(FocusedElementSnapshot(role: "AXTextField", subrole: nil, isSecure: false))
    }
    func inspectSelection() -> SelectionProbe { selection }
    func replaceSelection(with text: String) -> SelectionWriteResult { directResult }
    func replaceText(
        in range: SelectionRangeSnapshot,
        context: SelectionSnapshot,
        expectedText: String,
        with text: String,
        in application: ApplicationIdentity
    ) -> SelectionWriteResult { directResult }
    func replaceTextUsingClipboard(
        in range: SelectionRangeSnapshot,
        context: SelectionSnapshot,
        expectedText: String,
        with text: String,
        in application: ApplicationIdentity
    ) -> SelectionWriteResult { clipboardResult }
}
