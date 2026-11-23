enum MenuBarIconState: Equatable, Hashable, Sendable {
    case active
    case disabled
    case permissionRequired
    case degraded
}

struct ApplicationState: Equatable {
    var configuration: AppConfiguration
    var accessibilityGranted: Bool
    var hotkeyRegistered: Bool
    var hotkeyRegistrationError: String?
    var lastFixOutcome: FixOutcome?
    var lastProbeSummary: String?
    var launchAtLoginEnabled: Bool
    var launchAtLoginStatus: LoginItemStatus = .disabled
    var launchAtLoginError: String?
}
