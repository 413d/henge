import Foundation
import OSLog
import SwiftUI

@MainActor
final class HengeCoordinator: ObservableObject {
    @Published private(set) var state: ApplicationState

    private static let hengeBundleIdentifier = "io.github.413d.Henge"

    private let configurationStore: ConfigurationStore
    private let fixTextUseCase: FixTextUseCaseProtocol
    private let runtime: AppRuntime
    private let loginItemManager: LoginItemManaging
    private let selfBundleIdentifier: String?
    private let presentSettings: @MainActor () -> Void
    private let terminateApplication: @MainActor () -> Void
    private let exceptionManager = ExceptionManager()
    private let exceptionMatcher = ExceptionMatcher()
    private let configLogger = Diagnostics.logger(.config)
    private var isExecutingFixText = false
    private var lastObservedFrontmostExcludableApplication: ApplicationIdentity?

    init(
        environment: AppEnvironment,
        selfBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        presentSettings: (@MainActor () -> Void)? = nil,
        terminateApplication: (@MainActor () -> Void)? = nil
    ) {
        configurationStore = environment.configurationStore
        fixTextUseCase = environment.fixTextUseCase
        runtime = environment.runtime
        loginItemManager = environment.loginItemManager
        self.selfBundleIdentifier = selfBundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.presentSettings = presentSettings ?? {}
        self.terminateApplication = terminateApplication ?? {
            NSApplication.shared.terminate(nil)
        }

        let loadedConfiguration = environment.configurationStore.load()
        let systemLaunchAtLoginStatus = environment.loginItemManager.status
        let systemLaunchAtLoginEnabled = systemLaunchAtLoginStatus == .enabled
        let resolvedConfigurationLaunchAtLogin: Bool = switch systemLaunchAtLoginStatus {
        case .enabled:
            true
        case .disabled:
            false
        case .requiresApproval:
            loadedConfiguration.launchAtLogin
        }
        let normalizedConfiguration = AppConfiguration(
            schemaVersion: loadedConfiguration.schemaVersion,
            isEnabled: loadedConfiguration.isEnabled,
            launchAtLogin: resolvedConfigurationLaunchAtLogin,
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
            launchAtLoginEnabled: systemLaunchAtLoginEnabled,
            launchAtLoginStatus: systemLaunchAtLoginStatus,
            launchAtLoginError: nil
        )

        updateHotkeyRegistration()
        lastObservedFrontmostExcludableApplication = resolveFrontmostExcludableApplication()

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

    var frontmostExcludableApplication: ApplicationIdentity? {
        resolveFrontmostExcludableApplication()
    }

    var hotkeyStatusText: String {
        if let hotkeyRegistrationError = state.hotkeyRegistrationError {
            return state.hotkeyRegistered
                ? L10n.format(
                    "hotkey.status.error_with_active_fallback",
                    defaultValue: "%@ The current shortcut remains active.",
                    hotkeyRegistrationError
                )
                : hotkeyRegistrationError
        }

        if state.hotkeyRegistered, !state.accessibilityGranted {
            return L10n.string(
                "hotkey.status.registered_accessibility_required",
                defaultValue: "Global shortcut is registered, but Accessibility access is still required for text operations."
            )
        }

        return state.hotkeyRegistered
            ? L10n.string(
                "hotkey.status.registered_ready",
                defaultValue: "Global shortcut is registered and ready for native validation."
            )
            : L10n.string(
                "hotkey.status.inactive_disabled",
                defaultValue: "Global shortcut is inactive while Henge is disabled."
            )
    }

    var launchAtLoginStatusText: String {
        if let launchAtLoginError = state.launchAtLoginError {
            return launchAtLoginError
        }

        switch state.launchAtLoginStatus {
        case .enabled:
            return L10n.string(
                "launch_at_login.status.enabled",
                defaultValue: "Launch at Login is enabled."
            )
        case .disabled:
            return L10n.string(
                "launch_at_login.status.disabled",
                defaultValue: "Launch at Login is disabled."
            )
        case .requiresApproval:
            return L10n.string(
                "launch_at_login.status.requires_approval",
                defaultValue: "Approval required in System Settings → Login Items."
            )
        }
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
            return L10n.string("fix_outcome.fixed_direct", defaultValue: "Text corrected.")
        case .fixed(viaClipboard: true):
            return L10n.string(
                "fix_outcome.fixed_clipboard",
                defaultValue: "Text corrected using the clipboard fallback."
            )
        case .nothingToFix:
            return L10n.string(
                "fix_outcome.nothing_to_fix",
                defaultValue: "Nothing to fix in the current text."
            )
        case .secureField:
            return L10n.string(
                "fix_outcome.secure_field",
                defaultValue: "Focused secure text field detected. Henge left the content untouched."
            )
        case .excluded:
            return nil
        case .unsupported:
            return L10n.string(
                "fix_outcome.unsupported",
                defaultValue: "The focused element does not support text replacement."
            )
        case .pasteUnverified:
            return L10n.string(
                "fix_outcome.paste_unverified",
                defaultValue: "Henge attempted clipboard replacement, but could not verify that the text changed."
            )
        case let .failed(reason):
            switch reason {
            case .noActiveApplication:
                return L10n.string(
                    "fix_outcome.failed.no_active_application",
                    defaultValue: "Henge could not identify the active application and left the text untouched."
                )
            case .missingPermission:
                return L10n.string(
                    "fix_outcome.failed.missing_permission",
                    defaultValue: "Accessibility access is required before Henge can inspect the focused element."
                )
            case .noFocusedElement:
                return L10n.string(
                    "fix_outcome.failed.no_focused_element",
                    defaultValue: "No focused text element is currently available for Henge to inspect."
                )
            case let .accessibilityError(code):
                return L10n.format(
                    "fix_outcome.failed.accessibility_error",
                    defaultValue: "Henge could not inspect or update the focused element (AXError %d).",
                    code
                )
            case .clipboardRestoreFailed:
                return L10n.string(
                    "fix_outcome.failed.clipboard_restore_failed",
                    defaultValue: "Henge could not restore the original clipboard contents after replacement."
                )
            case .clipboardSuperseded:
                return L10n.string(
                    "fix_outcome.failed.clipboard_superseded",
                    defaultValue: "Clipboard contents changed before restoration, so Henge kept the new clipboard contents."
                )
            case let .focusLost(applicationName):
                return L10n.format(
                    "fix_outcome.failed.focus_lost",
                    defaultValue: "Henge could not restore focus to %@ and left the text untouched.",
                    applicationName
                )
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
        let previousEnabled = state.launchAtLoginEnabled
        let previousStatus = state.launchAtLoginStatus
        let previousConfiguration = state.configuration
        state.launchAtLoginError = nil

        do {
            try loginItemManager.setEnabled(launchAtLogin)
            let actualStatus = loginItemManager.status

            switch (launchAtLogin, actualStatus) {
            case (true, .enabled):
                state.launchAtLoginStatus = .enabled
                state.launchAtLoginEnabled = true
                state.configuration.launchAtLogin = true
            case (true, .requiresApproval):
                state.launchAtLoginStatus = .requiresApproval
                state.launchAtLoginEnabled = false
                state.configuration.launchAtLogin = true
            case (false, .disabled):
                state.launchAtLoginStatus = .disabled
                state.launchAtLoginEnabled = false
                state.configuration.launchAtLogin = false
            default:
                throw LoginItemUpdateError.updateFailed(
                    L10n.string(
                        "launch_at_login.error.unverified",
                        defaultValue: "Launch at Login state could not be verified."
                    )
                )
            }

            saveConfigurationIfChanged(from: previousConfiguration)
        } catch {
            state.launchAtLoginEnabled = previousEnabled
            state.launchAtLoginStatus = previousStatus
            state.configuration = previousConfiguration
            state.launchAtLoginError = error.localizedDescription
            saveConfigurationIfChanged(from: previousConfiguration)
        }
    }

    func resetConfigurationToDefaults() {
        let previousConfiguration = state.configuration
        state.configuration = AppConfiguration.default
        // launchAtLogin mirrors the system login-item state, not the config default.
        let systemStatus = loginItemManager.status
        state.launchAtLoginStatus = systemStatus
        state.launchAtLoginEnabled = systemStatus == .enabled
        switch systemStatus {
        case .enabled:
            state.configuration.launchAtLogin = true
        case .disabled:
            state.configuration.launchAtLogin = false
        case .requiresApproval:
            state.configuration.launchAtLogin = previousConfiguration.launchAtLogin
        }
        state.lastFixOutcome = nil
        state.lastProbeSummary = nil
        saveConfigurationIfChanged(from: previousConfiguration)
        updateHotkeyRegistration()
        lastObservedFrontmostExcludableApplication = resolveFrontmostExcludableApplication()
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
        let updated = exceptionManager.add(
            application,
            to: state.configuration.excludedApplicationBundleIdentifiers
        )
        if state.configuration.excludedApplicationBundleIdentifiers != updated {
            state.configuration.excludedApplicationBundleIdentifiers = updated
        }
        saveConfigurationIfChanged(from: previousConfiguration)
        lastObservedFrontmostExcludableApplication = resolveFrontmostExcludableApplication()
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
        lastObservedFrontmostExcludableApplication = resolveFrontmostExcludableApplication()
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

    private func syncLaunchAtLoginState() {
        let currentStatus = loginItemManager.status
        let resolvedEnabled = currentStatus == .enabled
        if state.launchAtLoginStatus != currentStatus {
            state.launchAtLoginStatus = currentStatus
        }
        if state.launchAtLoginEnabled != resolvedEnabled {
            state.launchAtLoginEnabled = resolvedEnabled
        }
        if state.launchAtLoginError != nil {
            state.launchAtLoginError = nil
        }
        guard currentStatus != .requiresApproval else {
            configLogger.debug("\(DiagnosticsLabel.configSaveSkipped.rawValue, privacy: .public) reason=requiresApproval")
            return
        }
        guard state.configuration.launchAtLogin != resolvedEnabled else {
            configLogger.debug("\(DiagnosticsLabel.configSaveSkipped.rawValue, privacy: .public) reason=unchanged")
            return
        }
        state.configuration.launchAtLogin = resolvedEnabled
        configurationStore.save(state.configuration)
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
            state.lastProbeSummary = L10n.format(
                "probe.status.focused_element_resolved",
                defaultValue: "Focused element resolved: %@.",
                focusedSnapshot.summary
            )
            return
        }

        state.lastProbeSummary = nil
        let outcome = fixTextUseCase.execute(
            excludingApplicationBundleIdentifiers: state.configuration.excludedApplicationBundleIdentifiers
        )
        state.lastFixOutcome = outcome == .excluded ? nil : outcome
    }

    private func refreshFrontmostExcludableApplication() {
        let resolved = resolveFrontmostExcludableApplication()
        guard resolved != lastObservedFrontmostExcludableApplication else {
            return
        }
        objectWillChange.send()
        lastObservedFrontmostExcludableApplication = resolved
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

        let excluded = Set(state.configuration.excludedApplicationBundleIdentifiers)
        guard !exceptionMatcher.contains(application, in: excluded),
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
