struct ApplicationState: Equatable {
    var configuration: AppConfiguration
    var accessibilityGranted: Bool
    var hotkeyRegistered: Bool
    var hotkeyRegistrationError: String?
    var lastProbeStatus: String?
}
