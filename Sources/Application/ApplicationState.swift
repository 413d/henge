struct ApplicationState: Equatable {
    var configuration: AppConfiguration
    var accessibilityGranted: Bool
    var hotkeyRegistered: Bool
    var hotkeyRegistrationError: String?
    var lastFixOutcome: FixOutcome?
    var lastProbeSummary: String?
    var launchAtLoginEnabled: Bool
    var launchAtLoginError: String?
}
