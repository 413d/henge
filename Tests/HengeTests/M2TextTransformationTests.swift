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
            mapper: NativeKeyboardLayoutMapper()
        )

        #expect(transformer.transform("ghbdtn") == .transformed("привет"))
    }

    @Test
    func transformerMapsRussianToEnglish() {
        let transformer = SimpleTextTransformer(
            detector: MajorityLayoutDetector(),
            mapper: NativeKeyboardLayoutMapper()
        )

        #expect(transformer.transform("привет") == .transformed("ghbdtn"))
    }

    @Test
    func transformerReturnsNoOpForEmptyText() {
        let transformer = SimpleTextTransformer(
            detector: MajorityLayoutDetector(),
            mapper: NativeKeyboardLayoutMapper()
        )

        #expect(transformer.transform("") == .noOp(.emptyText))
    }

    @Test
    func transformerReturnsNoOpForNeutralText() {
        let transformer = SimpleTextTransformer(
            detector: MajorityLayoutDetector(),
            mapper: NativeKeyboardLayoutMapper()
        )

        #expect(transformer.transform("12345") == .noOp(.neutralText))
    }

    @Test
    func transformerReturnsNoOpForAmbiguousDirection() {
        let transformer = SimpleTextTransformer(
            detector: MajorityLayoutDetector(),
            mapper: NativeKeyboardLayoutMapper()
        )

        #expect(transformer.transform("abвг") == .noOp(.ambiguousDirection))
    }

    @Test
    func liveUseCaseReplacesSelectedText() {
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
    }

    @Test
    func liveUseCaseSkipsNeutralText() {
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
    func liveUseCaseSkipsUnavailableSelection() {
        let runtime = SelectionStubRuntime(selection: .unavailable(.noSelection))
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
            selection: .available(
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

private final class SelectionStubRuntime: AppRuntime {
    var hasAccessibilityPermission: Bool { true }
    let layoutMapper: LayoutMapping = NativeKeyboardLayoutMapper()
    let clipboardManager: ClipboardManaging = MockClipboardManager()

    private let selection: SelectionProbe
    private let replacementResult: SelectionWriteResult?
    private(set) var replacedText: String?
    private(set) var replaceCallCount = 0

    init(selection: SelectionProbe, replacementResult: SelectionWriteResult? = nil) {
        self.selection = selection
        self.replacementResult = replacementResult
    }

    func openAccessibilitySettings() {}

    func registerFixTextHotkey(_ shortcut: Shortcut, handler: @escaping () -> Void) throws {}

    func unregisterFixTextHotkey() {}

    func inspectFocusedElement() -> FocusedElementProbe {
        .available(FocusedElementSnapshot(role: "AXTextField", subrole: nil, isSecure: false))
    }

    func inspectSelection() -> SelectionProbe {
        selection
    }

    func replaceSelection(with text: String) -> SelectionWriteResult {
        replacedText = text
        replaceCallCount += 1

        if let replacementResult {
            return replacementResult
        }

        switch selection {
        case let .available(snapshot):
            return .success(snapshot.range)
        case let .unavailable(reason):
            return .unavailable(.init(from: reason))
        }
    }
}

private extension SelectionWriteFailure {
    init(from reason: SelectionProbeFailure) {
        switch reason {
        case .missingPermission:
            self = .missingPermission
        case .noFocusedElement:
            self = .noFocusedElement
        case .secureField:
            self = .secureField
        case .noSelection:
            self = .noSelection
        case .unsupported:
            self = .unsupported
        case let .accessibilityError(error):
            self = .accessibilityError(error)
        }
    }
}
