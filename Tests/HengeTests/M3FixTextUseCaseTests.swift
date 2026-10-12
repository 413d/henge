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
}
