import Testing
@testable import Henge

struct M2TextTransformationTests {
    @Test
    func majorityDetectorRecognizesEnglishText() {
        let detector = MajorityLayoutDetector()

        #expect(detector.detect("ghbdtn") == LayoutDetection(layout: .english, confidence: .clear))
    }

    @Test
    func majorityDetectorRecognizesRussianText() {
        let detector = MajorityLayoutDetector()

        #expect(detector.detect("руддщ") == LayoutDetection(layout: .russian, confidence: .clear))
    }

    @Test
    func majorityDetectorReturnsNeutralForDigits() {
        let detector = MajorityLayoutDetector()

        #expect(detector.detect("12345") == LayoutDetection(layout: nil, confidence: .neutral))
    }

    @Test
    func majorityDetectorReturnsNeutralForPunctuation() {
        let detector = MajorityLayoutDetector()

        #expect(detector.detect("!!!") == LayoutDetection(layout: nil, confidence: .neutral))
    }

    @Test
    func majorityDetectorReturnsAmbiguousForTie() {
        let detector = MajorityLayoutDetector()

        #expect(detector.detect("abвг") == LayoutDetection(layout: nil, confidence: .ambiguous))
    }

    @Test
    func transformerMapsEnglishToRussian() {
        let transformer = SimpleTextTransformer(
            detector: MajorityLayoutDetector(),
            mapper: NativeKeyboardLayoutMapper.bundled()
        )

        #expect(transformer.transform("ghbdtn") == .transformed("привет"))
    }

    @Test
    func transformerMapsRussianToEnglish() {
        let transformer = SimpleTextTransformer(
            detector: MajorityLayoutDetector(),
            mapper: NativeKeyboardLayoutMapper.bundled()
        )

        #expect(transformer.transform("привет") == .transformed("ghbdtn"))
    }

    @Test
    func transformerPreservesTitleCaseThroughIntegration() {
        let transformer = SimpleTextTransformer(
            detector: MajorityLayoutDetector(),
            mapper: NativeKeyboardLayoutMapper.bundled()
        )

        #expect(transformer.transform("Ghbdtn") == .transformed("Привет"))
    }

    @Test
    func transformerFallsBackToMappedTextWhenMapperChangesCharacterCount() {
        let transformer = SimpleTextTransformer(
            detector: MajorityLayoutDetector(),
            mapper: LengthChangingLayoutMapper()
        )

        #expect(transformer.transform("abc") == .transformed("converted!"))
    }

    @Test
    func transformerReturnsNoOpForEmptyText() {
        let transformer = SimpleTextTransformer(
            detector: MajorityLayoutDetector(),
            mapper: NativeKeyboardLayoutMapper.bundled()
        )

        #expect(transformer.transform("") == .noOp(.emptyText))
    }

    @Test
    func transformerReturnsNoOpForNeutralText() {
        let transformer = SimpleTextTransformer(
            detector: MajorityLayoutDetector(),
            mapper: NativeKeyboardLayoutMapper.bundled()
        )

        #expect(transformer.transform("12345") == .noOp(.neutralText))
    }

    @Test
    func transformerReturnsNoOpForAmbiguousDirection() {
        let transformer = SimpleTextTransformer(
            detector: MajorityLayoutDetector(),
            mapper: NativeKeyboardLayoutMapper.bundled()
        )

        #expect(transformer.transform("abвг") == .noOp(.ambiguousDirection))
    }

    @Test
    func liveUseCaseReplacesSelectedText() {
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

        useCase.execute()

        #expect(runtime.replacedText == "привет")
    }

    @Test
    func liveUseCaseSkipsNeutralText() {
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

        useCase.execute()

        #expect(runtime.replacedText == nil)
        #expect(runtime.replaceCallCount == 0)
    }

    @Test
    func liveUseCaseSkipsUnavailableSelection() {
        let runtime = SelectionStubRuntime(selection: .failure(.noSelection))
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
    func liveUseCaseDoesNotRetryFailedReplacement() {
        let runtime = SelectionStubRuntime(
            selection: .success(
                SelectionSnapshot(text: "ghbdtn", range: SelectionRangeSnapshot(location: 0, length: 6))
            ),
            replacementResult: .unavailable(.unsupported)
        )
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
}

final class SelectionStubRuntime: AppRuntime {
    var hasAccessibilityPermission: Bool { true }
    var activeApplication: ApplicationIdentity? = ApplicationIdentity(bundleIdentifier: "test.application", displayName: "Test Application")
    let layoutMapper: LayoutMapping = NativeKeyboardLayoutMapper.bundled()
    let clipboardManager: ClipboardManaging = MockClipboardManager()

    private let selection: Result<SelectionSnapshot, SelectionProbeFailure>
    private let replacementResult: SelectionWriteResult?
    private(set) var replacedText: String?
    private(set) var replaceCallCount = 0

    init(selection: Result<SelectionSnapshot, SelectionProbeFailure>, replacementResult: SelectionWriteResult? = nil) {
        self.selection = selection
        self.replacementResult = replacementResult
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
        replacedText = text
        replaceCallCount += 1

        if let replacementResult {
            return replacementResult
        }

        switch selection {
        case let .success(snapshot):
            return .success(snapshot.range, viaClipboard: false)
        case let .failure(reason):
            return .unavailable(.probe(reason))
        }
    }
}

func makeTestTextTarget(
    application: ApplicationIdentity,
    snapshot: FocusedElementSnapshot = FocusedElementSnapshot(role: "AXTextField", subrole: nil, isSecure: false)
) -> TextTarget {
    TextTarget(application: application, snapshot: snapshot)
}

func makeTestTextContext(
    _ selection: Result<SelectionSnapshot, SelectionProbeFailure>,
    in application: ApplicationIdentity,
    snapshot: FocusedElementSnapshot = FocusedElementSnapshot(role: "AXTextField", subrole: nil, isSecure: false)
) -> TextContextProbe {
    switch selection {
    case let .success(selectionSnapshot):
        return .available(
            TextContext(
                target: makeTestTextTarget(application: application, snapshot: snapshot),
                selection: selectionSnapshot
            )
        )
    case let .failure(reason):
        return .unavailable(reason)
    }
}

private struct LengthChangingLayoutMapper: LayoutMapping {
    func map(_ character: Character, from source: Layout, to target: Layout) -> Character? {
        nil
    }

    func map(text: String, from source: Layout, to target: Layout) -> String {
        "converted!"
    }
}
