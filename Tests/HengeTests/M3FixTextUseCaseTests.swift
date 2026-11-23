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

        useCase.execute()

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

        useCase.execute()

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

        useCase.execute()

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

        useCase.execute()

        #expect(runtime.replacedText == "ПРИВЕТ")
        #expect(runtime.replaceCallCount == 1)
    }

    @Test
    func liveUseCaseSkipsNoOpSelection() {
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

        useCase.execute()

        #expect(runtime.replacedText == nil)
        #expect(runtime.replaceCallCount == 0)
    }

    @Test
    func statusChannelReportsClipboardFallbackSuccess() {
        let runtime = ClipboardStatusStubRuntime(
            selection: .available(
                SelectionSnapshot(text: "ghbdtn", range: SelectionRangeSnapshot(location: 0, length: 6))
            ),
            directResult: .unavailable(.unsupported),
            clipboardResult: .success(SelectionRangeSnapshot(location: 0, length: 6))
        )
        let statusChannel = FixTextStatusChannel()
        let useCase = LiveFixTextUseCase(
            runtime: runtime,
            transformer: SimpleTextTransformer(
                detector: MajorityLayoutDetector(),
                mapper: runtime.layoutMapper
            ),
            statusChannel: statusChannel
        )

        #expect(statusChannel.take() == nil)
        useCase.execute()
        #expect(statusChannel.take() == "Text corrected using the clipboard fallback.")
        #expect(statusChannel.take() == nil)
    }

    @Test
    func statusChannelReportsDirectSuccessAndClipboardFailures() {
        let directRuntime = ClipboardStatusStubRuntime(
            selection: .available(
                SelectionSnapshot(text: "ghbdtn", range: SelectionRangeSnapshot(location: 0, length: 6))
            ),
            directResult: .success(SelectionRangeSnapshot(location: 0, length: 6)),
            clipboardResult: .unavailable(.unsupported)
        )
        let statusChannel = FixTextStatusChannel()
        let directUseCase = LiveFixTextUseCase(
            runtime: directRuntime,
            transformer: SimpleTextTransformer(
                detector: MajorityLayoutDetector(),
                mapper: directRuntime.layoutMapper
            ),
            statusChannel: statusChannel
        )
        directUseCase.execute()
        #expect(statusChannel.take() == "Text corrected.")

        let unverifiedRuntime = ClipboardStatusStubRuntime(
            selection: .available(
                SelectionSnapshot(text: "ghbdtn", range: SelectionRangeSnapshot(location: 0, length: 6))
            ),
            directResult: .unavailable(.unsupported),
            clipboardResult: .unavailable(.pasteUnverified)
        )
        LiveFixTextUseCase(
            runtime: unverifiedRuntime,
            transformer: SimpleTextTransformer(
                detector: MajorityLayoutDetector(),
                mapper: unverifiedRuntime.layoutMapper
            ),
            statusChannel: statusChannel
        ).execute()
        #expect(statusChannel.take() == SelectionWriteFailure.pasteUnverified.description)

        let restoreFailedRuntime = ClipboardStatusStubRuntime(
            selection: .available(
                SelectionSnapshot(text: "ghbdtn", range: SelectionRangeSnapshot(location: 0, length: 6))
            ),
            directResult: .unavailable(.unsupported),
            clipboardResult: .unavailable(.clipboardRestoreFailed)
        )
        LiveFixTextUseCase(
            runtime: restoreFailedRuntime,
            transformer: SimpleTextTransformer(
                detector: MajorityLayoutDetector(),
                mapper: restoreFailedRuntime.layoutMapper
            ),
            statusChannel: statusChannel
        ).execute()
        #expect(statusChannel.take() == SelectionWriteFailure.clipboardRestoreFailed.description)

        let supersededRuntime = ClipboardStatusStubRuntime(
            selection: .available(
                SelectionSnapshot(text: "ghbdtn", range: SelectionRangeSnapshot(location: 0, length: 6))
            ),
            directResult: .unavailable(.unsupported),
            clipboardResult: .unavailable(.clipboardSuperseded)
        )
        LiveFixTextUseCase(
            runtime: supersededRuntime,
            transformer: SimpleTextTransformer(
                detector: MajorityLayoutDetector(),
                mapper: supersededRuntime.layoutMapper
            ),
            statusChannel: statusChannel
        ).execute()
        #expect(statusChannel.take() == nil)
    }
}

private final class ClipboardStatusStubRuntime: AppRuntime {
    var hasAccessibilityPermission: Bool { true }
    var activeApplication: ApplicationIdentity? = ApplicationIdentity(bundleIdentifier: "test.application", displayName: "Test Application")
    let layoutMapper: LayoutMapping = NativeKeyboardLayoutMapper()
    let clipboardManager: ClipboardManaging = MockClipboardManager()

    private let selection: SelectionProbe
    private let directResult: SelectionWriteResult
    private let clipboardResult: SelectionWriteResult

    init(
        selection: SelectionProbe,
        directResult: SelectionWriteResult,
        clipboardResult: SelectionWriteResult
    ) {
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
