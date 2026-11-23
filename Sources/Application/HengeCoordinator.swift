import Foundation
import OSLog
import SwiftUI

@MainActor
final class HengeCoordinator: ObservableObject {
    @Published private(set) var state: ApplicationState

    private let configurationStore: ConfigurationStore
    private let fixTextUseCase: FixTextUseCaseProtocol
    private let runtime: AppRuntime
    private let loginItemManager: LoginItemManaging
    private let presentSettings: @MainActor () -> Void
    private let terminateApplication: @MainActor () -> Void
    private let exceptionManager = ExceptionManager()
    private let exceptionMatcher = ExceptionMatcher()
    private let configLogger = Diagnostics.logger(.config)
    private var isExecutingFixText = false

    init(
        environment: AppEnvironment,
        presentSettings: (@MainActor () -> Void)? = nil,
        terminateApplication: (@MainActor () -> Void)? = nil
    ) {
        configurationStore = environment.configurationStore
        fixTextUseCase = environment.fixTextUseCase
        runtime = environment.runtime
        loginItemManager = environment.loginItemManager
        self.presentSettings = presentSettings ?? {}
        self.terminateApplication = terminateApplication ?? {
            NSApplication.shared.terminate(nil)
        }

        let loadedConfiguration = environment.configurationStore.load()
        let systemLaunchAtLogin = environment.loginItemManager.status == .enabled
        let normalizedConfiguration = AppConfiguration(
            schemaVersion: loadedConfiguration.schemaVersion,
            isEnabled: loadedConfiguration.isEnabled,
            launchAtLogin: systemLaunchAtLogin,
            shortcut: loadedConfiguration.shortcut,
            excludedApplicationBundleIdentifiers: loadedConfiguration.excludedApplicationBundleIdentifiers
        )

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
            lastProbeSummary: nil,
            launchAtLoginEnabled: systemLaunchAtLogin,
            launchAtLoginError: nil
        )

        updateHotkeyRegistration()

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

    var fixTextAvailability: FixTextAvailability {
        fixTextUseCase.availability
    }

    var canTriggerFixText: Bool {
        guard state.configuration.isEnabled else {
            return false
        }

        if case .available = fixTextUseCase.availability {
            return true
        }

        return false
    }

    var hotkeyStatusText: String {
        if let hotkeyRegistrationError = state.hotkeyRegistrationError {
            return state.hotkeyRegistered
                ? "\(hotkeyRegistrationError) The current shortcut remains active."
                : hotkeyRegistrationError
        }

        if state.hotkeyRegistered, !state.accessibilityGranted {
            return "Global shortcut is registered, but Accessibility access is still required for text operations."
        }

        return state.hotkeyRegistered
            ? "Global shortcut is registered and ready for native validation."
            : "Global shortcut is inactive while Henge is disabled."
    }

    var launchAtLoginStatusText: String {
        if let launchAtLoginError = state.launchAtLoginError {
            return launchAtLoginError
        }

        return state.launchAtLoginEnabled
            ? "Launch at Login is enabled."
            : "Launch at Login is disabled."
    }

    var lastProbeStatusText: String? {
        if let outcome = state.lastFixOutcome {
            return Self.statusText(for: outcome)
        }
        return state.lastProbeSummary
    }

    static func statusText(for outcome: FixOutcome) -> String? {
        switch outcome {
        case .fixed(viaClipboard: false):
            return "Text corrected."
        case .fixed(viaClipboard: true):
            return "Text corrected using the clipboard fallback."
        case .nothingToFix:
            return "Nothing to fix in the current text."
        case .secureField:
            return "Focused secure text field detected. Henge left the content untouched."
        case .excluded:
            return nil
        case .unsupported:
            return "The focused element does not support text replacement."
        case .pasteUnverified:
            return "Henge attempted clipboard replacement, but could not verify that the text changed."
        case let .failed(reason):
            switch reason {
            case .noActiveApplication:
                return "Henge could not identify the active application and left the text untouched."
            case .missingPermission:
                return "Accessibility access is required before Henge can inspect the focused element."
            case .noFocusedElement:
                return "No focused text element is currently available for Henge to inspect."
            case let .accessibilityError(code):
                return "Henge could not inspect or update the focused element (AXError \(code))."
            case .clipboardRestoreFailed:
                return "Henge could not restore the original clipboard contents after replacement."
            case .clipboardSuperseded:
                return "Clipboard contents changed before restoration, so Henge kept the new clipboard contents."
            case let .focusLost(applicationName):
                return "Henge could not restore focus to \(applicationName) and left the text untouched."
            }
        }
    }

    func applicationDisplayName(for bundleIdentifier: String) -> String {
        runtime.applicationIdentity(for: bundleIdentifier)?.displayName ?? bundleIdentifier
    }

    var statusItemState: MenuBarIconState {
        guard state.configuration.isEnabled else {
            return .disabled
        }

        if !state.accessibilityGranted {
            return .permissionRequired
        }

        if !state.hotkeyRegistered {
            return .degraded
        }

        return .active
    }

    var statusItemSymbolName: String {
        switch statusItemState {
        case .disabled:
            return "cloud"
        case .permissionRequired, .degraded:
            return "exclamationmark.cloud"
        case .active:
            return "cloud.fill"
        }
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
        let previousState = state.launchAtLoginEnabled
        let previousConfiguration = state.configuration
        state.launchAtLoginError = nil

        do {
            try loginItemManager.setEnabled(launchAtLogin)
            let actualState = currentLaunchAtLoginEnabled()

            guard actualState == launchAtLogin else {
                throw LoginItemUpdateError.updateFailed("Launch at Login state could not be verified.")
            }

            state.launchAtLoginEnabled = actualState
            state.configuration.launchAtLogin = actualState
            saveConfigurationIfChanged(from: previousConfiguration)
        } catch {
            state.launchAtLoginEnabled = previousState
            state.configuration.launchAtLogin = previousState
            state.launchAtLoginError = error.localizedDescription
            saveConfigurationIfChanged(from: previousConfiguration)
        }
    }

    func resetConfigurationToDefaults() {
        let previousConfiguration = state.configuration
        state.configuration = AppConfiguration.default
        // launchAtLogin mirrors the system login-item state, not the config default.
        let systemLaunchAtLogin = currentLaunchAtLoginEnabled()
        state.launchAtLoginEnabled = systemLaunchAtLogin
        state.configuration.launchAtLogin = systemLaunchAtLogin
        state.lastFixOutcome = nil
        state.lastProbeSummary = nil
        saveConfigurationIfChanged(from: previousConfiguration)
        updateHotkeyRegistration()
    }

    func setShortcut(_ shortcut: Shortcut) {
        guard shortcut != state.configuration.shortcut else {
            configLogger.debug("\(DiagnosticsLabel.configSaveSkipped.rawValue, privacy: .public) reason=unchanged")
            return
        }

        if state.configuration.isEnabled {
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
        configurationStore.save(state.configuration)
    }

    func triggerFixText() {
        guard state.configuration.isEnabled, !isExecutingFixText else {
            return
        }

        let excluded = Set(state.configuration.excludedApplicationBundleIdentifiers)
        guard let application = runtime.activeApplication else {
            state.lastProbeSummary = nil
            state.lastFixOutcome = .failed(.noActiveApplication)
            return
        }
        guard !exceptionMatcher.contains(application, in: excluded) else {
            return
        }

        let accessibilityGranted = runtime.hasAccessibilityPermission
        state.accessibilityGranted = accessibilityGranted
        guard accessibilityGranted else {
            state.lastProbeSummary = nil
            state.lastFixOutcome = .failed(.missingPermission)
            return
        }

        guard canTriggerFixText else {
            return
        }

        isExecutingFixText = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isExecutingFixText = false }

            let prepared = await self.runtime.prepareTargetApplicationForFixText(application)
            guard prepared else {
                self.state.lastProbeSummary = nil
                self.state.lastFixOutcome = .failed(.focusLost(applicationName: application.displayName))
                return
            }

            self.executeFixTextWithPreflight()
        }
    }

    func addApplicationException(_ application: ApplicationIdentity) {
        let previousConfiguration = state.configuration
        let updated = exceptionManager.add(
            application,
            to: state.configuration.excludedApplicationBundleIdentifiers
        )
        if state.configuration.excludedApplicationBundleIdentifiers != updated {
            state.configuration.excludedApplicationBundleIdentifiers = updated
        }
        saveConfigurationIfChanged(from: previousConfiguration)
    }

    func removeApplicationException(bundleIdentifier: String) {
        let previousConfiguration = state.configuration
        let updated = exceptionManager.remove(
            bundleIdentifier: bundleIdentifier,
            from: state.configuration.excludedApplicationBundleIdentifiers
        )
        if state.configuration.excludedApplicationBundleIdentifiers != updated {
            state.configuration.excludedApplicationBundleIdentifiers = updated
        }
        saveConfigurationIfChanged(from: previousConfiguration)
    }

    func refreshPermissions() {
        let accessibilityGranted = runtime.hasAccessibilityPermission
        if state.accessibilityGranted != accessibilityGranted {
            state.accessibilityGranted = accessibilityGranted
        }
        syncLaunchAtLoginState()
    }

    func openAccessibilitySettings() {
        runtime.openAccessibilitySettings()
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

    private func syncLaunchAtLoginState() {
        let resolved = currentLaunchAtLoginEnabled()
        if state.launchAtLoginEnabled != resolved {
            state.launchAtLoginEnabled = resolved
        }
        if state.launchAtLoginError != nil {
            state.launchAtLoginError = nil
        }
        guard state.configuration.launchAtLogin != resolved else {
            configLogger.debug("\(DiagnosticsLabel.configSaveSkipped.rawValue, privacy: .public) reason=unchanged")
            return
        }
        state.configuration.launchAtLogin = resolved
        configurationStore.save(state.configuration)
    }

    private func saveConfigurationIfChanged(from previousConfiguration: AppConfiguration) {
        guard state.configuration != previousConfiguration else {
            configLogger.debug("\(DiagnosticsLabel.configSaveSkipped.rawValue, privacy: .public) reason=unchanged")
            return
        }
        configurationStore.save(state.configuration)
    }

    private func currentLaunchAtLoginEnabled() -> Bool {
        loginItemManager.status == .enabled
    }

    private func updateHotkeyRegistration() {
        guard state.configuration.isEnabled else {
            runtime.unregisterFixTextHotkey()
            state.hotkeyRegistered = false
            state.hotkeyRegistrationError = nil
            state.lastFixOutcome = nil
            state.lastProbeSummary = nil
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
        guard !isExecutingFixText else {
            return
        }

        executeFixTextWithPreflight()
    }

    private func executeFixTextWithPreflight() {
        guard state.configuration.isEnabled else {
            return
        }

        let excluded = Set(state.configuration.excludedApplicationBundleIdentifiers)
        guard let application = runtime.activeApplication else {
            state.lastProbeSummary = nil
            state.lastFixOutcome = .failed(.noActiveApplication)
            return
        }
        guard !exceptionMatcher.contains(application, in: excluded) else {
            return
        }

        let accessibilityGranted = runtime.hasAccessibilityPermission
        state.accessibilityGranted = accessibilityGranted

        guard accessibilityGranted else {
            state.lastProbeSummary = nil
            state.lastFixOutcome = .failed(.missingPermission)
            return
        }

        let focusedSnapshot: FocusedElementSnapshot
        switch runtime.inspectFocusedElement() {
        case let .unavailable(reason):
            state.lastProbeSummary = nil
            state.lastFixOutcome = Self.outcome(from: reason)
            return
        case let .available(snapshot) where snapshot.isSecure:
            state.lastProbeSummary = nil
            state.lastFixOutcome = .secureField
            return
        case let .available(snapshot):
            focusedSnapshot = snapshot
        }

        guard canTriggerFixText else {
            state.lastFixOutcome = nil
            state.lastProbeSummary = "Focused element resolved: \(focusedSnapshot.summary)."
            return
        }

        state.lastProbeSummary = nil
        let outcome = fixTextUseCase.execute(
            excludingApplicationBundleIdentifiers: state.configuration.excludedApplicationBundleIdentifiers
        )
        state.lastFixOutcome = outcome == .excluded ? nil : outcome
    }

    private static func outcome(from failure: FocusedElementProbeFailure) -> FixOutcome {
        switch failure {
        case .missingPermission:
            return .failed(.missingPermission)
        case .noFocusedElement:
            return .failed(.noFocusedElement)
        case let .accessibilityError(error):
            return .failed(.accessibilityError(error.rawValue))
        }
    }
}
