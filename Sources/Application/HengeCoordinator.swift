import Combine
import Foundation
import OSLog

@MainActor
final class HengeCoordinator: ObservableObject {
    @Published private(set) var state: ApplicationState
    @Published private var observedFrontmostExcludableApplication: ApplicationIdentity?

    private static let hengeBundleIdentifier = "io.github.413d.Henge"

    private let configurationStore: ConfigurationStore
    private let fixTextUseCase: FixTextUseCaseProtocol
    private let runtime: AppRuntime
    private let loginItemManager: LoginItemManaging
    private let selfBundleIdentifier: String?
    private let presentSettings: @MainActor () -> Void
    private let presentOnboarding: @MainActor () -> Void
    private let dismissOnboarding: @MainActor () -> Void
    private let terminateApplication: @MainActor () -> Void
    private let configLogger = Diagnostics.logger(.config)
    private var isExecutingFixText = false

    init(
        environment: AppEnvironment,
        selfBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        presentSettings: (@MainActor () -> Void)? = nil,
        presentOnboarding: (@MainActor () -> Void)? = nil,
        dismissOnboarding: (@MainActor () -> Void)? = nil,
        terminateApplication: (@MainActor () -> Void)? = nil
    ) {
        configurationStore = environment.configurationStore
        fixTextUseCase = environment.fixTextUseCase
        runtime = environment.runtime
        loginItemManager = environment.loginItemManager
        self.selfBundleIdentifier = selfBundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.presentSettings = presentSettings ?? {}
        self.presentOnboarding = presentOnboarding ?? {}
        self.dismissOnboarding = dismissOnboarding ?? {}
        self.terminateApplication = terminateApplication ?? {}

        let loadedConfiguration = environment.configurationStore.load()
        let reconciledLaunchAtLogin = Self.reconcileLaunchAtLogin(
            status: environment.loginItemManager.status,
            fallbackConfigurationFlag: loadedConfiguration.launchAtLogin
        )
        var normalizedConfiguration = loadedConfiguration
        normalizedConfiguration.launchAtLogin = reconciledLaunchAtLogin.configFlag

        if normalizedConfiguration != loadedConfiguration {
            environment.configurationStore.save(normalizedConfiguration)
        } else {
            configLogger.debug("\(DiagnosticsLabel.configSaveSkipped.rawValue, privacy: .public) reason=unchanged")
        }

        state = ApplicationState(
            configuration: normalizedConfiguration,
            accessibilityGranted: environment.runtime.hasAccessibilityPermission,
            hotkeyRegistered: false,
            hotkeyRegistrationError: nil,
            lastFixOutcome: nil,
            launchAtLoginEnabled: reconciledLaunchAtLogin.enabled,
            launchAtLoginStatus: reconciledLaunchAtLogin.status,
            launchAtLoginError: nil
        )

        updateHotkeyRegistration()
        refreshFrontmostExcludableApplication()

        environment.runtime.setActivationHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshPermissions()
            }
        }
    }

    var isEnabled: Bool {
        state.configuration.isEnabled
    }

    var shortcutDescription: String {
        state.configuration.shortcut.displayString
    }

    var canTriggerFixText: Bool {
        state.configuration.isEnabled
    }

    var frontmostExcludableApplication: ApplicationIdentity? {
        resolveFrontmostExcludableApplication()
    }

    var hotkeyStatusText: String {
        StatusPresenter.hotkeyStatusText(
            registrationError: state.hotkeyRegistrationError,
            hotkeyRegistered: state.hotkeyRegistered,
            accessibilityGranted: state.accessibilityGranted
        )
    }

    var launchAtLoginStatusText: String {
        StatusPresenter.launchAtLoginStatusText(
            error: state.launchAtLoginError,
            status: state.launchAtLoginStatus
        )
    }

    var lastProbeStatusText: String? {
        StatusPresenter.lastProbeStatusText(lastFixOutcome: state.lastFixOutcome)
    }

    static func statusText(for outcome: FixOutcome) -> String? {
        StatusPresenter.statusText(for: outcome)
    }

    func applicationDisplayName(for bundleIdentifier: String) -> String {
        runtime.applicationIdentity(for: bundleIdentifier)?.displayName ?? bundleIdentifier
    }

    var statusItemState: MenuBarIconState {
        StatusPresenter.statusItemState(
            isEnabled: state.configuration.isEnabled,
            accessibilityGranted: state.accessibilityGranted,
            hotkeyRegistered: state.hotkeyRegistered
        )
    }

    var statusItemSymbolName: String {
        StatusPresenter.statusItemSymbolName(for: statusItemState)
    }

    func setEnabled(_ isEnabled: Bool) {
        let previousConfiguration = state.configuration
        if state.configuration.isEnabled != isEnabled {
            state.configuration.isEnabled = isEnabled
        }
        saveConfigurationIfChanged(from: previousConfiguration)
        updateHotkeyRegistration()
    }

    func setLaunchAtLogin(_ launchAtLogin: Bool) {
        let previousEnabled = state.launchAtLoginEnabled
        let previousStatus = state.launchAtLoginStatus
        let previousConfiguration = state.configuration
        state.launchAtLoginError = nil

        do {
            try loginItemManager.setEnabled(launchAtLogin)
            let actualStatus = loginItemManager.status

            let targetState: (status: LoginItemStatus, enabled: Bool, configFlag: Bool) = switch (launchAtLogin, actualStatus) {
            case (true, .enabled):
                (.enabled, true, true)
            case (true, .requiresApproval):
                (.requiresApproval, false, true)
            case (false, .disabled):
                (.disabled, false, false)
            default:
                throw LoginItemUpdateError.updateFailed(
                    L10n.string(
                        "launch_at_login.error.unverified",
                        defaultValue: "Launch at Login state could not be verified."
                    )
                )
            }

            state.launchAtLoginStatus = targetState.status
            state.launchAtLoginEnabled = targetState.enabled
            state.configuration.launchAtLogin = targetState.configFlag
            saveConfigurationIfChanged(from: previousConfiguration)
        } catch {
            state.launchAtLoginEnabled = previousEnabled
            state.launchAtLoginStatus = previousStatus
            state.configuration = previousConfiguration
            state.launchAtLoginError = error.localizedDescription
        }
    }

    func resetConfigurationToDefaults() {
        let previousConfiguration = state.configuration
        let reconciled = Self.reconcileLaunchAtLogin(
            status: loginItemManager.status,
            fallbackConfigurationFlag: previousConfiguration.launchAtLogin
        )
        var resetConfiguration = AppConfiguration.default
        resetConfiguration.hasCompletedOnboarding = previousConfiguration.hasCompletedOnboarding
        resetConfiguration.launchAtLogin = reconciled.configFlag
        state.configuration = resetConfiguration
        state.launchAtLoginStatus = reconciled.status
        state.launchAtLoginEnabled = reconciled.enabled
        state.lastFixOutcome = nil
        saveConfigurationIfChanged(from: previousConfiguration)
        updateHotkeyRegistration()
        refreshFrontmostExcludableApplication()
    }

    func setShortcut(_ shortcut: Shortcut) {
        let previousConfiguration = state.configuration
        guard shortcut != previousConfiguration.shortcut else {
            saveConfigurationIfChanged(from: previousConfiguration)
            return
        }

        if previousConfiguration.isEnabled {
            do {
                try registerHotkey(shortcut)
            } catch {
                state.hotkeyRegistrationError = error.localizedDescription
                return
            }
            state.hotkeyRegistered = true
            state.hotkeyRegistrationError = nil
        }

        state.configuration.shortcut = shortcut
        saveConfigurationIfChanged(from: previousConfiguration)
    }

    func triggerFixText() {
        guard let application = preflightFixText() else {
            return
        }

        isExecutingFixText = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isExecutingFixText = false }

            let prepared = await self.runtime.prepareTargetApplicationForFixText(application)
            guard prepared else {
                self.state.lastFixOutcome = .failed(.focusLost(applicationName: application.displayName))
                return
            }

            self.executeFixText()
        }
    }

    @discardableResult
    func excludeFrontmostApplication() -> Bool {
        guard let application = frontmostExcludableApplication else {
            return false
        }

        addApplicationException(application)
        return true
    }

    func addApplicationException(_ application: ApplicationIdentity) {
        let previousConfiguration = state.configuration
        let updated = ExceptionManager.add(
            application,
            to: state.configuration.excludedApplicationBundleIdentifiers
        )
        if state.configuration.excludedApplicationBundleIdentifiers != updated {
            state.configuration.excludedApplicationBundleIdentifiers = updated
        }
        saveConfigurationIfChanged(from: previousConfiguration)
        refreshFrontmostExcludableApplication()
    }

    func removeApplicationException(bundleIdentifier: String) {
        let previousConfiguration = state.configuration
        let updated = ExceptionManager.remove(
            bundleIdentifier: bundleIdentifier,
            from: state.configuration.excludedApplicationBundleIdentifiers
        )
        if state.configuration.excludedApplicationBundleIdentifiers != updated {
            state.configuration.excludedApplicationBundleIdentifiers = updated
        }
        saveConfigurationIfChanged(from: previousConfiguration)
        refreshFrontmostExcludableApplication()
    }

    func refreshPermissions() {
        let accessibilityGranted = runtime.hasAccessibilityPermission
        if state.accessibilityGranted != accessibilityGranted {
            state.accessibilityGranted = accessibilityGranted
        }
        syncLaunchAtLoginState()
        refreshFrontmostExcludableApplication()
    }

    func openAccessibilitySettings() {
        runtime.openAccessibilitySettings()
    }

    func requestAccessibilityPermission() {
        runtime.requestAccessibilityPermission()
    }

    func startOnboardingIfNeeded() {
        let accessibilityGranted = runtime.hasAccessibilityPermission
        if state.accessibilityGranted != accessibilityGranted {
            state.accessibilityGranted = accessibilityGranted
        }

        if state.configuration.hasCompletedOnboarding {
            return
        }

        if accessibilityGranted {
            let previousConfiguration = state.configuration
            state.configuration.hasCompletedOnboarding = true
            saveConfigurationIfChanged(from: previousConfiguration)
            return
        }

        presentOnboarding()
    }

    func completeOnboarding() {
        let previousConfiguration = state.configuration
        if !state.configuration.hasCompletedOnboarding {
            state.configuration.hasCompletedOnboarding = true
        }
        saveConfigurationIfChanged(from: previousConfiguration)
        dismissOnboarding()
    }

    func openLoginItemSettings() {
        loginItemManager.openLoginItemSettings()
    }

    func openSettings() {
        refreshPermissions()
        presentSettings()
    }

    func quitApplication() {
        runtime.unregisterFixTextHotkey()
        state.hotkeyRegistered = false
        state.hotkeyRegistrationError = nil
        terminateApplication()
    }

    private static func reconcileLaunchAtLogin(
        status: LoginItemStatus,
        fallbackConfigurationFlag: Bool
    ) -> (enabled: Bool, status: LoginItemStatus, configFlag: Bool) {
        // launchAtLogin mirrors the system login-item state unless awaiting user approval.
        let configFlag: Bool = switch status {
        case .enabled:
            true
        case .disabled:
            false
        case .requiresApproval:
            fallbackConfigurationFlag
        }
        return (enabled: status == .enabled, status: status, configFlag: configFlag)
    }

    private func syncLaunchAtLoginState() {
        let previousConfiguration = state.configuration
        let reconciled = Self.reconcileLaunchAtLogin(
            status: loginItemManager.status,
            fallbackConfigurationFlag: previousConfiguration.launchAtLogin
        )
        if state.launchAtLoginStatus != reconciled.status {
            state.launchAtLoginStatus = reconciled.status
        }
        if state.launchAtLoginEnabled != reconciled.enabled {
            state.launchAtLoginEnabled = reconciled.enabled
        }
        if state.launchAtLoginError != nil {
            state.launchAtLoginError = nil
        }
        if state.configuration.launchAtLogin != reconciled.configFlag {
            state.configuration.launchAtLogin = reconciled.configFlag
        }
        saveConfigurationIfChanged(from: previousConfiguration)
    }

    private func saveConfigurationIfChanged(from previousConfiguration: AppConfiguration) {
        guard state.configuration != previousConfiguration else {
            configLogger.debug("\(DiagnosticsLabel.configSaveSkipped.rawValue, privacy: .public) reason=unchanged")
            return
        }
        configurationStore.save(state.configuration)
    }

    private func updateHotkeyRegistration() {
        guard state.configuration.isEnabled else {
            runtime.unregisterFixTextHotkey()
            state.hotkeyRegistered = false
            state.hotkeyRegistrationError = nil
            state.lastFixOutcome = nil
            return
        }

        do {
            try registerHotkey(state.configuration.shortcut)

            state.hotkeyRegistered = true
            state.hotkeyRegistrationError = nil
        } catch {
            state.hotkeyRegistered = false
            state.hotkeyRegistrationError = error.localizedDescription
        }
    }

    private func registerHotkey(_ shortcut: Shortcut) throws {
        try runtime.registerFixTextHotkey(shortcut) { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleFixTextHotkey()
            }
        }
    }

    private func handleFixTextHotkey() {
        guard preflightFixText() != nil else {
            return
        }

        executeFixText()
    }

    private func preflightFixText() -> ApplicationIdentity? {
        guard state.configuration.isEnabled, !isExecutingFixText else {
            return nil
        }

        guard let application = runtime.activeApplication else {
            state.lastFixOutcome = .failed(.noActiveApplication)
            return nil
        }
        guard !ExceptionMatcher.contains(
            application,
            in: state.configuration.excludedApplicationBundleIdentifiers
        ) else {
            return nil
        }

        let accessibilityGranted = runtime.hasAccessibilityPermission
        if state.accessibilityGranted != accessibilityGranted {
            state.accessibilityGranted = accessibilityGranted
        }
        guard accessibilityGranted else {
            state.lastFixOutcome = .failed(.missingPermission)
            return nil
        }

        return application
    }

    private func executeFixText() {
        guard state.configuration.isEnabled else {
            return
        }

        let outcome = fixTextUseCase.execute(
            excludingApplicationBundleIdentifiers: state.configuration.excludedApplicationBundleIdentifiers
        )
        if outcome == .failed(.missingPermission), state.accessibilityGranted {
            state.accessibilityGranted = false
        }
        state.lastFixOutcome = outcome == .excluded ? nil : outcome
    }

    private func refreshFrontmostExcludableApplication() {
        let resolved = resolveFrontmostExcludableApplication()
        if observedFrontmostExcludableApplication != resolved {
            observedFrontmostExcludableApplication = resolved
        }
    }

    private func resolveFrontmostExcludableApplication() -> ApplicationIdentity? {
        guard let application = runtime.activeApplication else {
            return nil
        }

        let bundleIdentifier = application.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleIdentifier.isEmpty else {
            return nil
        }

        if isOwnBundleIdentifier(bundleIdentifier) {
            return nil
        }

        let excluded = state.configuration.excludedApplicationBundleIdentifiers
        guard !ExceptionMatcher.contains(application, in: excluded),
              !excluded.contains(bundleIdentifier) else {
            return nil
        }

        return application
    }

    private func isOwnBundleIdentifier(_ bundleIdentifier: String) -> Bool {
        if bundleIdentifier == Self.hengeBundleIdentifier {
            return true
        }

        if let selfBundleIdentifier,
           !selfBundleIdentifier.isEmpty,
           bundleIdentifier == selfBundleIdentifier {
            return true
        }

        return false
    }
}
