import Foundation
import SwiftUI

@MainActor
final class HengeCoordinator: ObservableObject {
    @Published private(set) var state: ApplicationState

    private let configurationStore: ConfigurationStore
    private let fixTextUseCase: FixTextUseCaseProtocol
    private let runtime: AppRuntime
    private let loginItemManager: LoginItemManaging
    private let terminateApplication: () -> Void
    private let exceptionManager = ExceptionManager()
    private let exceptionMatcher = ExceptionMatcher()

    init(
        environment: AppEnvironment,
        terminateApplication: @escaping () -> Void = { NSApplication.shared.terminate(nil) }
    ) {
        configurationStore = environment.configurationStore
        fixTextUseCase = environment.fixTextUseCase
        runtime = environment.runtime
        loginItemManager = environment.loginItemManager
        self.terminateApplication = terminateApplication

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
        }

        state = ApplicationState(
            configuration: normalizedConfiguration,
            accessibilityGranted: environment.runtime.hasAccessibilityPermission,
            hotkeyRegistered: false,
            hotkeyRegistrationError: nil,
            lastProbeStatus: nil,
            launchAtLoginEnabled: systemLaunchAtLogin,
            launchAtLoginError: nil
        )

        updateHotkeyRegistration()
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
        state.lastProbeStatus
    }

    func applicationDisplayName(for bundleIdentifier: String) -> String {
        runtime.applicationIdentity(for: bundleIdentifier)?.displayName ?? bundleIdentifier
    }

    var statusItemSymbolName: String {
        state.configuration.isEnabled ? "keyboard" : "keyboard.badge.ellipsis"
    }

    func setEnabled(_ isEnabled: Bool) {
        state.configuration.isEnabled = isEnabled
        configurationStore.save(state.configuration)
        updateHotkeyRegistration()
    }

    func setLaunchAtLogin(_ launchAtLogin: Bool) {
        let previousState = state.launchAtLoginEnabled
        state.launchAtLoginError = nil

        do {
            try loginItemManager.setEnabled(launchAtLogin)
            let actualState = currentLaunchAtLoginEnabled()

            guard actualState == launchAtLogin else {
                throw LoginItemUpdateError.updateFailed("Launch at Login state could not be verified.")
            }

            state.launchAtLoginEnabled = actualState
            state.configuration.launchAtLogin = actualState
            configurationStore.save(state.configuration)
        } catch {
            state.launchAtLoginEnabled = previousState
            state.configuration.launchAtLogin = previousState
            state.launchAtLoginError = error.localizedDescription
            configurationStore.save(state.configuration)
        }
    }

    func resetConfigurationToDefaults() {
        let defaults = AppConfiguration.default
        do {
            try registerHotkey(defaults.shortcut)
        } catch {
            state.hotkeyRegistrationError = error.localizedDescription
            return
        }
        state.hotkeyRegistered = true
        state.hotkeyRegistrationError = nil

        state.configuration = defaults
        syncLaunchAtLoginState()
        state.lastProbeStatus = nil
        configurationStore.save(state.configuration)
        updateHotkeyRegistration()
    }

    func setShortcut(_ shortcut: Shortcut) {
        guard shortcut != state.configuration.shortcut else { return }

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
        guard canTriggerFixText else {
            return
        }

        state.lastProbeStatus = "Correction attempted."
        fixTextUseCase.execute(excludingApplicationBundleIdentifiers: Set(state.configuration.excludedApplicationBundleIdentifiers))
    }

    func addApplicationException(_ application: ApplicationIdentity) {
        state.configuration.excludedApplicationBundleIdentifiers = exceptionManager.add(
            application,
            to: state.configuration.excludedApplicationBundleIdentifiers
        )
        configurationStore.save(state.configuration)
    }

    func removeApplicationException(bundleIdentifier: String) {
        state.configuration.excludedApplicationBundleIdentifiers = exceptionManager.remove(
            bundleIdentifier: bundleIdentifier,
            from: state.configuration.excludedApplicationBundleIdentifiers
        )
        configurationStore.save(state.configuration)
    }

    func refreshPermissions() {
        state.accessibilityGranted = runtime.hasAccessibilityPermission
        syncLaunchAtLoginState()
    }

    func openAccessibilitySettings() {
        runtime.openAccessibilitySettings()
    }

    func quitApplication() {
        runtime.unregisterFixTextHotkey()
        state.hotkeyRegistered = false
        state.hotkeyRegistrationError = nil
        terminateApplication()
    }

    private func syncLaunchAtLoginState() {
        let actualStatus = currentLaunchAtLoginEnabled()
        state.launchAtLoginEnabled = actualStatus
        state.configuration.launchAtLogin = actualStatus
        state.launchAtLoginError = nil
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
            state.lastProbeStatus = nil
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
        guard state.configuration.isEnabled else {
            return
        }

        guard let application = runtime.activeApplication else {
            state.lastProbeStatus = "Henge could not identify the active application and left the text untouched."
            return
        }
        guard !exceptionMatcher.contains(application, in: Set(state.configuration.excludedApplicationBundleIdentifiers)) else {
            return
        }

        let accessibilityGranted = runtime.hasAccessibilityPermission
        state.accessibilityGranted = accessibilityGranted

        guard accessibilityGranted else {
            state.lastProbeStatus = FocusedElementProbeFailure.missingPermission.description
            return
        }

        switch runtime.inspectFocusedElement() {
        case let .unavailable(reason):
            state.lastProbeStatus = reason.description
            return
        case let .available(snapshot) where snapshot.isSecure:
            state.lastProbeStatus = "Focused secure text field detected. Henge left the content untouched."
            return
        case let .available(snapshot):
            state.lastProbeStatus = "Focused element resolved: \(snapshot.summary)."
        }

        guard canTriggerFixText else {
            return
        }

        state.lastProbeStatus = "Correction attempted."
        fixTextUseCase.execute(excludingApplicationBundleIdentifiers: Set(state.configuration.excludedApplicationBundleIdentifiers))
    }
}
