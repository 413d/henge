import Foundation
import SwiftUI

@MainActor
final class HengeCoordinator: ObservableObject {
    @Published private(set) var state: ApplicationState

    private let configurationStore: ConfigurationStore
    private let fixTextUseCase: FixTextUseCaseProtocol
    private let runtime: AppRuntime
    private let exceptionManager = ExceptionManager()
    private let exceptionMatcher = ExceptionMatcher()

    init(environment: AppEnvironment) {
        configurationStore = environment.configurationStore
        fixTextUseCase = environment.fixTextUseCase
        runtime = environment.runtime
        state = ApplicationState(
            configuration: environment.configurationStore.load(),
            accessibilityGranted: environment.runtime.hasAccessibilityPermission,
            hotkeyRegistered: false,
            hotkeyRegistrationError: nil,
            lastProbeStatus: nil
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
            return hotkeyRegistrationError
        }

        if state.hotkeyRegistered, !state.accessibilityGranted {
            return "Global shortcut is registered, but Accessibility access is still required for text operations."
        }

        return state.hotkeyRegistered
            ? "Global shortcut is registered and ready for native validation."
            : "Global shortcut is inactive while Henge is disabled."
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
    }

    func openAccessibilitySettings() {
        runtime.openAccessibilitySettings()
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
            try runtime.registerFixTextHotkey(state.configuration.shortcut) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.handleFixTextHotkey()
                }
            }

            state.hotkeyRegistered = true
            state.hotkeyRegistrationError = nil
        } catch {
            state.hotkeyRegistered = false
            state.hotkeyRegistrationError = error.localizedDescription
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
