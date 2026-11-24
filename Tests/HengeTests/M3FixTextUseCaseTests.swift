import ApplicationServices
import Testing
@testable import Henge

struct M3FixTextUseCaseTests {
    @Test
    func liveUseCaseTransformsSelectionText() {
        let runtime = SelectionStubRuntime(selection: .success(
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
        let runtime = SelectionStubRuntime(selection: .success(
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
        let runtime = SelectionStubRuntime(selection: .success(
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
        let runtime = SelectionStubRuntime(selection: .success(
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
        let runtime = SelectionStubRuntime(selection: .success(
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
            selection: .success(
                SelectionSnapshot(text: "ghbdtn", range: SelectionRangeSnapshot(location: 0, length: 6))
            ),
            writeResult: .success(SelectionRangeSnapshot(location: 0, length: 6), viaClipboard: true)
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
            selection: .success(
                SelectionSnapshot(text: "ghbdtn", range: SelectionRangeSnapshot(location: 0, length: 6))
            ),
            writeResult: .success(SelectionRangeSnapshot(location: 0, length: 6), viaClipboard: false)
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
            selection: .success(
                SelectionSnapshot(text: "ghbdtn", range: SelectionRangeSnapshot(location: 0, length: 6))
            ),
            writeResult: .unavailable(.pasteUnverified)
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
            selection: .success(
                SelectionSnapshot(text: "ghbdtn", range: SelectionRangeSnapshot(location: 0, length: 6))
            ),
            writeResult: .unavailable(.clipboardRestoreFailed)
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
            selection: .success(
                SelectionSnapshot(text: "ghbdtn", range: SelectionRangeSnapshot(location: 0, length: 6))
            ),
            writeResult: .unavailable(.clipboardSuperseded)
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
            selection: .failure(.noFocusedElement)
        )
        #expect(makeUseCase(noAppRuntime).execute() == .failed(.noActiveApplication))

        let excludedRuntime = OutcomeStubRuntime(
            selection: .success(SelectionSnapshot(text: "ghbdtn", range: SelectionRangeSnapshot(location: 0, length: 6))),
            writeResult: .success(SelectionRangeSnapshot(location: 0, length: 6), viaClipboard: false)
        )
        #expect(
            makeUseCase(excludedRuntime).execute(excludingApplicationBundleIdentifiers: ["test.application"]) == .excluded
        )

        let missingPermissionRuntime = OutcomeStubRuntime(
            selection: .failure(.missingPermission)
        )
        #expect(makeUseCase(missingPermissionRuntime).execute() == .failed(.missingPermission))

        let noFocusedRuntime = OutcomeStubRuntime(
            selection: .failure(.noFocusedElement)
        )
        #expect(makeUseCase(noFocusedRuntime).execute() == .failed(.noFocusedElement))

        let secureRuntime = OutcomeStubRuntime(
            selection: .failure(.secureField)
        )
        #expect(makeUseCase(secureRuntime).execute() == .secureField)

        let noSelectionRuntime = OutcomeStubRuntime(
            selection: .failure(.noSelection)
        )
        #expect(makeUseCase(noSelectionRuntime).execute() == .nothingToFix)

        let axErrorRuntime = OutcomeStubRuntime(
            selection: .failure(.accessibilityError(.cannotComplete))
        )
        #expect(makeUseCase(axErrorRuntime).execute() == .failed(.accessibilityError(AXError.cannotComplete.rawValue)))

        let unsupportedRuntime = OutcomeStubRuntime(
            selection: .success(SelectionSnapshot(text: "ghbdtn", range: SelectionRangeSnapshot(location: 0, length: 6))),
            writeResult: .unavailable(.unsupported)
        )
        #expect(makeUseCase(unsupportedRuntime).execute() == .unsupported)
    }

    @Test
    func liveUseCaseHandlesEmojiSurrogatePairCaretOffset() {
        let text = "🎉ghbdtn"
        let snapshot = SelectionSnapshot(
            text: text,
            range: SelectionRangeSnapshot(location: 8, length: 0),
            isCaretContext: true
        )
        let runtime = RecordingStubRuntime(selection: .success(snapshot))
        let detector = RecordingWordBoundaryDetector()
        let useCase = LiveFixTextUseCase(
            runtime: runtime,
            transformer: SimpleTextTransformer(
                detector: MajorityLayoutDetector(),
                mapper: runtime.layoutMapper
            ),
            wordBoundaryDetector: detector
        )

        let outcome = useCase.execute()

        #expect(outcome == .fixed(viaClipboard: false))
        #expect(detector.lastCaretOffset == 7)
        #expect(detector.lastBoundary?.range == 1..<7)
        #expect(runtime.recordedReplacements.count == 1)
        #expect(runtime.recordedReplacements.first == RecordedReplacement(
            range: SelectionRangeSnapshot(location: 2, length: 6),
            context: snapshot,
            expectedText: "ghbdtn",
            text: "привет"
        ))
    }

    @Test
    func liveUseCaseHandlesZWJEmojiClusterCaretOffset() {
        let emoji = "👨‍👩‍👧"
        #expect(emoji.utf16.count == 8)
        let text = "\(emoji) ghbdtn"
        let snapshot = SelectionSnapshot(
            text: text,
            range: SelectionRangeSnapshot(location: text.utf16.count, length: 0),
            isCaretContext: true
        )
        let runtime = RecordingStubRuntime(selection: .success(snapshot))
        let useCase = LiveFixTextUseCase(
            runtime: runtime,
            transformer: SimpleTextTransformer(
                detector: MajorityLayoutDetector(),
                mapper: runtime.layoutMapper
            )
        )

        let outcome = useCase.execute()

        #expect(outcome == .fixed(viaClipboard: false))
        #expect(runtime.recordedReplacements.count == 1)
        #expect(runtime.recordedReplacements.first == RecordedReplacement(
            range: SelectionRangeSnapshot(location: 9, length: 6),
            context: snapshot,
            expectedText: "ghbdtn",
            text: "привет"
        ))
    }

    @Test
    func liveUseCaseHandlesCombiningMarkCaretOffsets() {
        let text = "cafe\u{0301} ghbdtn"
        for caretUTF16Offset in [6, text.utf16.count] {
            let snapshot = SelectionSnapshot(
                text: text,
                range: SelectionRangeSnapshot(location: caretUTF16Offset, length: 0),
                isCaretContext: true
            )
            let runtime = RecordingStubRuntime(selection: .success(snapshot))
            let useCase = LiveFixTextUseCase(
                runtime: runtime,
                transformer: SimpleTextTransformer(
                    detector: MajorityLayoutDetector(),
                    mapper: runtime.layoutMapper
                )
            )

            let outcome = useCase.execute()

            #expect(outcome == .fixed(viaClipboard: false))
            #expect(runtime.recordedReplacements.count == 1)
            #expect(runtime.recordedReplacements.first == RecordedReplacement(
                range: SelectionRangeSnapshot(location: 6, length: 6),
                context: snapshot,
                expectedText: "ghbdtn",
                text: "привет"
            ))
        }

        let midClusterSnapshot = SelectionSnapshot(
            text: text,
            range: SelectionRangeSnapshot(location: 4, length: 0),
            isCaretContext: true
        )
        let midClusterRuntime = RecordingStubRuntime(selection: .success(midClusterSnapshot))
        let midClusterOutcome = LiveFixTextUseCase(
            runtime: midClusterRuntime,
            transformer: SimpleTextTransformer(
                detector: MajorityLayoutDetector(),
                mapper: midClusterRuntime.layoutMapper
            )
        ).execute()

        #expect(midClusterOutcome == .nothingToFix)
        #expect(midClusterRuntime.recordedReplacements.isEmpty)
    }

    @Test
    func liveUseCaseHandlesLongMultilineDocumentCaretAtEnd() {
        let prefix = String(repeating: "lorem ipsum \n", count: 200)
        let text = prefix + "ghbdtn"
        let snapshot = SelectionSnapshot(
            text: text,
            range: SelectionRangeSnapshot(location: text.utf16.count, length: 0),
            isCaretContext: true
        )
        let runtime = RecordingStubRuntime(selection: .success(snapshot))
        let useCase = LiveFixTextUseCase(
            runtime: runtime,
            transformer: SimpleTextTransformer(
                detector: MajorityLayoutDetector(),
                mapper: runtime.layoutMapper
            )
        )

        let clock = ContinuousClock()
        var outcome: FixOutcome?
        let elapsed = clock.measure {
            outcome = useCase.execute()
        }

        #expect(outcome == .fixed(viaClipboard: false))
        #expect(elapsed < .seconds(1))
        #expect(runtime.recordedReplacements.count == 1)
        #expect(runtime.recordedReplacements.first == RecordedReplacement(
            range: SelectionRangeSnapshot(location: prefix.utf16.count, length: 6),
            context: snapshot,
            expectedText: "ghbdtn",
            text: "привет"
        ))
    }

    @Test
    func liveUseCaseSkipsCaretOffsetInsideSurrogatePairWithoutWrite() {
        let snapshot = SelectionSnapshot(
            text: "🎉ghbdtn",
            range: SelectionRangeSnapshot(location: 1, length: 0),
            isCaretContext: true
        )
        let runtime = RecordingStubRuntime(selection: .success(snapshot))
        let useCase = LiveFixTextUseCase(
            runtime: runtime,
            transformer: SimpleTextTransformer(
                detector: MajorityLayoutDetector(),
                mapper: runtime.layoutMapper
            )
        )

        let outcome = useCase.execute()

        #expect(outcome == .nothingToFix)
        #expect(runtime.recordedReplacements.isEmpty)
    }

    @Test
    func caretContextOperationPassesTextTargetWithActiveApplication() {
        let snapshot = SelectionSnapshot(
            text: "hello ghbdtn",
            range: SelectionRangeSnapshot(location: 12, length: 0),
            isCaretContext: true
        )
        let expectedApplication = ApplicationIdentity(bundleIdentifier: "com.apple.Notes", displayName: "Notes")!
        let runtime = RecordingStubRuntime(activeApplication: expectedApplication, selection: .success(snapshot))
        let useCase = LiveFixTextUseCase(
            runtime: runtime,
            transformer: SimpleTextTransformer(
                detector: MajorityLayoutDetector(),
                mapper: runtime.layoutMapper
            )
        )

        let outcome = useCase.execute()

        #expect(outcome == .fixed(viaClipboard: false))
        #expect(runtime.recordedReplacements.count == 1)
        #expect(runtime.recordedTargets.first?.application == expectedApplication)
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
    let layoutMapper: LayoutMapping = NativeKeyboardLayoutMapper.bundled()
    let clipboardManager: ClipboardManaging = MockClipboardManager()

    private let selection: Result<SelectionSnapshot, SelectionProbeFailure>
    private let writeResult: SelectionWriteResult

    init(
        activeApplication: ApplicationIdentity? = ApplicationIdentity(bundleIdentifier: "test.application", displayName: "Test Application"),
        selection: Result<SelectionSnapshot, SelectionProbeFailure>,
        writeResult: SelectionWriteResult = .unavailable(.unsupported)
    ) {
        self.activeApplication = activeApplication
        self.selection = selection
        self.writeResult = writeResult
    }

    func openAccessibilitySettings() {}
    func registerFixTextHotkey(_ shortcut: Shortcut, handler: @escaping () -> Void) throws {}
    func unregisterFixTextHotkey() {}
    func inspectFocusedElement() -> FocusedElementProbe {
        .available(FocusedElementSnapshot(role: "AXTextField", subrole: nil, isSecure: false))
    }
    func inspectTextContext(in application: ApplicationIdentity) -> TextContextProbe {
        makeTestTextContext(selection, in: application)
    }
    func replaceText(
        _ target: TextTarget,
        range: SelectionRangeSnapshot,
        context: SelectionSnapshot,
        expectedText: String,
        with text: String
    ) -> SelectionWriteResult { writeResult }
}

private struct RecordedReplacement: Equatable {
    let range: SelectionRangeSnapshot
    let context: SelectionSnapshot
    let expectedText: String
    let text: String
}

private final class RecordingWordBoundaryDetector: WordBoundaryDetecting, @unchecked Sendable {
    private let wrapped = DefaultWordBoundaryDetector()
    private(set) var lastCaretOffset: Int?
    private(set) var lastBoundary: WordBoundary?

    func detect(in text: String, caretOffset: Int) -> WordBoundary? {
        lastCaretOffset = caretOffset
        let boundary = wrapped.detect(in: text, caretOffset: caretOffset)
        lastBoundary = boundary
        return boundary
    }
}

private final class RecordingStubRuntime: AppRuntime {
    var hasAccessibilityPermission: Bool { true }
    var activeApplication: ApplicationIdentity?
    let layoutMapper: LayoutMapping = NativeKeyboardLayoutMapper.bundled()
    let clipboardManager: ClipboardManaging = MockClipboardManager()

    private let selection: Result<SelectionSnapshot, SelectionProbeFailure>
    private(set) var recordedReplacements: [RecordedReplacement] = []
    private(set) var recordedTargets: [TextTarget] = []

    init(
        activeApplication: ApplicationIdentity? = ApplicationIdentity(bundleIdentifier: "test.application", displayName: "Test Application"),
        selection: Result<SelectionSnapshot, SelectionProbeFailure>
    ) {
        self.activeApplication = activeApplication
        self.selection = selection
    }

    func openAccessibilitySettings() {}
    func registerFixTextHotkey(_ shortcut: Shortcut, handler: @escaping () -> Void) throws {}
    func unregisterFixTextHotkey() {}
    func inspectFocusedElement() -> FocusedElementProbe {
        .available(FocusedElementSnapshot(role: "AXTextField", subrole: nil, isSecure: false))
    }
    func inspectTextContext(in application: ApplicationIdentity) -> TextContextProbe {
        makeTestTextContext(selection, in: application)
    }
    func replaceText(
        _ target: TextTarget,
        range: SelectionRangeSnapshot,
        context: SelectionSnapshot,
        expectedText: String,
        with text: String
    ) -> SelectionWriteResult {
        recordedTargets.append(target)
        recordedReplacements.append(RecordedReplacement(
            range: range,
            context: context,
            expectedText: expectedText,
            text: text
        ))
        return .success(range, viaClipboard: false)
    }
}
