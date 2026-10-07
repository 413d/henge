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
