enum FixTextAvailability: Equatable {
    case available
    case deferred(String)
}

protocol FixTextUseCaseProtocol {
    var availability: FixTextAvailability { get }

    func execute()
}

struct DeferredFixTextUseCase: FixTextUseCaseProtocol {
    let availability: FixTextAvailability = .deferred(
        "Text correction remains unavailable while Milestone 1 native hotkey and text-integration spikes are being validated."
    )

    func execute() {
    }
}

/// The current M3 live slice intentionally stays selection-first.
///
/// The pure-domain word boundary detection is implemented and fully testable,
/// but live word-around-caret orchestration remains a later integration step so
/// this use case does not yet expand beyond the existing AX selection seam.
struct LiveFixTextUseCase: FixTextUseCaseProtocol {
    let availability: FixTextAvailability = .available

    private let runtime: AppRuntime
    private let transformer: TextTransforming

    init(runtime: AppRuntime, transformer: TextTransforming) {
        self.runtime = runtime
        self.transformer = transformer
    }

    func execute() {
        switch runtime.inspectSelection() {
        case let .available(selection):
            switch transformer.transform(selection.text) {
            case let .transformed(text):
                _ = runtime.replaceSelection(with: text)
            case .noOp:
                return
            }
        case .unavailable:
            return
        }
    }
}
