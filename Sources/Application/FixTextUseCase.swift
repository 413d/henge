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
        "Text correction is intentionally deferred beyond M0 while the project skeleton, resident lifecycle and configuration contract are being validated."
    )

    func execute() {
    }
}
