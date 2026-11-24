import Foundation
import Testing
@testable import Henge

@MainActor
struct HengeCoordinatorTests {
    @Test
    func coordinatorLoadsConfigurationFromStore() {
        let store = InMemoryConfigurationStore()
        store.save(AppConfiguration(isEnabled: false, shortcut: .defaultFixText))
        let runtime = StubRuntime(hasAccessibilityPermission: true)

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: runtime
            )
        )

        #expect(coordinator.isEnabled == false)
        #expect(runtime.registeredShortcuts.isEmpty)
    }

    @Test
    func coordinatorPersistsEnablementChanges() {
        let store = InMemoryConfigurationStore()
        let runtime = StubRuntime(hasAccessibilityPermission: false)
        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: runtime
            )
        )

        coordinator.setEnabled(false)

        #expect(store.load().isEnabled == false)
        #expect(runtime.unregisterCount == 1)
    }

    @Test
    func coordinatorPersistsLaunchAtLoginChanges() {
        let store = InMemoryConfigurationStore()
        let runtime = StubRuntime(hasAccessibilityPermission: true)
        let loginItemManager = FakeLoginItemManager(currentStatus: .enabled)
        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: runtime,
                loginItemManager: loginItemManager
            )
        )

        coordinator.setLaunchAtLogin(false)

        #expect(store.load().launchAtLogin == false)
        #expect(loginItemManager.setEnabledCalls == [false])
    }

    @Test
    func coordinatorResetToDefaultsRestoresCanonicalSettings() {
        let store = InMemoryConfigurationStore()
        let runtime = StubRuntime(hasAccessibilityPermission: true)
        store.save(AppConfiguration(
            schemaVersion: 1,
            isEnabled: false,
            launchAtLogin: false,
            shortcut: Shortcut(key: "Z", modifiers: [.option]),
            excludedApplicationBundleIdentifiers: ["com.example.Editor", "com.example.Editor"]
        ))

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: runtime
            )
        )

        coordinator.resetConfigurationToDefaults()

        #expect(store.load() == AppConfiguration.default)
        #expect(coordinator.state.configuration == AppConfiguration.default)
        #expect(runtime.registeredShortcuts == [.defaultFixText])
    }

    @Test
    func resetMirrorsSystemLaunchAtLoginState() {
        let store = InMemoryConfigurationStore()
        store.save(AppConfiguration(isEnabled: true, launchAtLogin: true, shortcut: .defaultFixText))

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: StubRuntime(hasAccessibilityPermission: true),
                loginItemManager: FakeLoginItemManager(currentStatus: .disabled)
            )
        )

        coordinator.resetConfigurationToDefaults()

        #expect(store.load().launchAtLogin == false)
        #expect(coordinator.state.launchAtLoginEnabled == false)
        #expect(store.load().isEnabled == AppConfiguration.default.isEnabled)
        #expect(store.load().shortcut == AppConfiguration.default.shortcut)
    }

    @Test
    func statusItemSymbolShowsDisabledState() {
        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: InMemoryConfigurationStore(),
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: StubRuntime(hasAccessibilityPermission: true)
            )
        )

        coordinator.setEnabled(false)

        #expect(coordinator.statusItemState == .disabled)
        #expect(coordinator.statusItemSymbolName == "cloud")
    }

    @Test
    func statusItemSymbolShowsHealthyState() {
        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: InMemoryConfigurationStore(),
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: StubRuntime(hasAccessibilityPermission: true)
            )
        )

        #expect(coordinator.statusItemState == .active)
        #expect(coordinator.statusItemSymbolName == "cloud.fill")
    }

    @Test
    func statusItemSymbolShowsDegradedStateWithoutAccessibility() {
        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: InMemoryConfigurationStore(),
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: StubRuntime(hasAccessibilityPermission: false)
            )
        )

        #expect(coordinator.statusItemState == .permissionRequired)
        #expect(coordinator.statusItemSymbolName == "exclamationmark.cloud")
    }

    @Test
    func statusItemSymbolShowsDegradedStateWhenHotkeyFails() {
        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: InMemoryConfigurationStore(),
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: StubRuntime(
                    hasAccessibilityPermission: true,
                    registrationError: HotkeyRegistrationError.unsupportedShortcut("X")
                )
            )
        )

        #expect(coordinator.statusItemState == .degraded)
        #expect(coordinator.statusItemSymbolName == "exclamationmark.cloud")
    }

    @Test
    func statusItemStateDisabledTakesPrecedenceOverPermissionAndHotkeyIssues() {
        let store = InMemoryConfigurationStore()
        store.save(AppConfiguration(isEnabled: false, shortcut: .defaultFixText))

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: StubRuntime(
                    hasAccessibilityPermission: false,
                    registrationError: HotkeyRegistrationError.unsupportedShortcut("X")
                )
            )
        )

        #expect(coordinator.statusItemState == .disabled)
        #expect(coordinator.statusItemSymbolName == "cloud")
    }

    @Test
    func exceptionChangesArePersistedImmediatelyAndDeduplicated() {
        let store = InMemoryConfigurationStore()
        let runtime = StubRuntime(hasAccessibilityPermission: true)
        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: runtime
            )
        )
        let application = ApplicationIdentity(bundleIdentifier: "com.example.Editor", displayName: "Editor")!

        coordinator.addApplicationException(application)
        coordinator.addApplicationException(application)
        #expect(store.load().excludedApplicationBundleIdentifiers == ["com.example.Editor"])

        coordinator.removeApplicationException(bundleIdentifier: "com.example.Editor")
        #expect(store.load().excludedApplicationBundleIdentifiers.isEmpty)
    }

    @Test
    func reEnablingHotkeyRegistersAgain() {
        let runtime = StubRuntime(hasAccessibilityPermission: true)
        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: InMemoryConfigurationStore(),
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: runtime
            )
        )

        coordinator.setEnabled(false)
        coordinator.setEnabled(true)

        #expect(runtime.unregisterCount == 1)
        #expect(runtime.registeredShortcuts == [.defaultFixText, .defaultFixText])
    }

    @Test
    func deferredFixTextCannotBeTriggeredFromSkeleton() {
        let store = InMemoryConfigurationStore()
        let runtime = StubRuntime(hasAccessibilityPermission: true)
        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: runtime
            )
        )

        #expect(coordinator.canTriggerFixText == false)
        #expect(runtime.registeredShortcuts == [.defaultFixText])
    }

    @Test
    func coordinatorRegistersDefaultHotkeyWhenEnabled() {
        let runtime = StubRuntime(hasAccessibilityPermission: true)

        _ = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: InMemoryConfigurationStore(),
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: runtime
            )
        )

        #expect(runtime.registeredShortcuts == [.defaultFixText])
    }

    @Test
    func hotkeyCallbackExecutesUseCaseWhenFired() async {
        let runtime = StubRuntime(
            hasAccessibilityPermission: true,
            selectionProbe: .available(
                SelectionSnapshot(
                    text: "ghbdtn",
                    range: SelectionRangeSnapshot(location: 6, length: 6)
                )
            )
        )
        let useCase = SpyFixTextUseCase(availability: .available)

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: InMemoryConfigurationStore(),
                fixTextUseCase: useCase,
                runtime: runtime
            )
        )

        #expect(coordinator.canTriggerFixText == true)

        runtime.fireHotkey()
        await Task.yield()

        #expect(useCase.executionCount == 1)
        _ = coordinator
    }

    @Test
    func disabledHotkeyDoesNotExecuteUseCaseWhenFired() async {
        let runtime = StubRuntime(hasAccessibilityPermission: true)
        let useCase = SpyFixTextUseCase(availability: .deferred("Still spiking native integrations."))

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: InMemoryConfigurationStore(),
                fixTextUseCase: useCase,
                runtime: runtime
            )
        )

        coordinator.setEnabled(false)
        runtime.fireHotkey()
        await Task.yield()

        #expect(useCase.executionCount == 0)
        _ = coordinator
    }

    @Test
    func revokedAccessibilityPermissionBlocksHotkeyExecution() async {
        let runtime = StubRuntime(hasAccessibilityPermission: true)
        let useCase = SpyFixTextUseCase(availability: .deferred("Still spiking native integrations."))

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: InMemoryConfigurationStore(),
                fixTextUseCase: useCase,
                runtime: runtime
            )
        )

        runtime.hasAccessibilityPermission = false
        runtime.fireHotkey()
        await Task.yield()

        #expect(useCase.executionCount == 0)
        #expect(coordinator.state.accessibilityGranted == false)
        #expect(coordinator.hotkeyStatusText.contains("Accessibility access is still required"))
        _ = coordinator
    }

    @Test
    func coordinatorExposesRegistrationErrorWhenHotkeyFails() {
        let runtime = StubRuntime(
            hasAccessibilityPermission: true,
            registrationError: HotkeyRegistrationError.unsupportedShortcut("😶")
        )

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: InMemoryConfigurationStore(),
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: runtime
            )
        )

        #expect(coordinator.state.hotkeyRegistered == false)
        #expect(coordinator.hotkeyStatusText.contains("not supported"))
    }

    @Test
    func invalidShortcutIsRejectedBeforeRuntimeRegistration() {
        let store = InMemoryConfigurationStore()
        store.save(AppConfiguration(isEnabled: true, shortcut: Shortcut(key: "🙂", modifiers: [.option])))
        let runtime = StubRuntime(hasAccessibilityPermission: true)

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: runtime
            )
        )

        #expect(coordinator.state.hotkeyRegistered == false)
        #expect(runtime.registeredShortcuts.isEmpty)
        #expect(coordinator.hotkeyStatusText.contains("not supported"))
    }

    @Test
    func secureFocusedElementBlocksExecutionAndUpdatesProbeStatus() async {
        let runtime = StubRuntime(
            hasAccessibilityPermission: true,
            focusedElementProbe: .available(
                FocusedElementSnapshot(role: "AXTextField", subrole: "AXSecureTextField", isSecure: true)
            )
        )
        let useCase = SpyFixTextUseCase(availability: .available)

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: InMemoryConfigurationStore(),
                fixTextUseCase: useCase,
                runtime: runtime
            )
        )

        runtime.fireHotkey()
        await Task.yield()

        #expect(useCase.executionCount == 0)
        #expect(coordinator.lastProbeStatusText?.contains("secure text field") == true)
        _ = coordinator
    }

    @Test
    func missingFocusedElementBlocksExecutionAndUpdatesProbeStatus() async {
        let runtime = StubRuntime(
            hasAccessibilityPermission: true,
            focusedElementProbe: .unavailable(.noFocusedElement)
        )
        let useCase = SpyFixTextUseCase(availability: .available)

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: InMemoryConfigurationStore(),
                fixTextUseCase: useCase,
                runtime: runtime
            )
        )

        runtime.fireHotkey()
        await Task.yield()

        #expect(useCase.executionCount == 0)
        #expect(coordinator.lastProbeStatusText?.contains("No focused text element") == true)
        _ = coordinator
    }

    @Test
    func statusReportsFocusedElementWithoutUserText() async {
        let runtime = StubRuntime(
            hasAccessibilityPermission: true,
            selectionProbe: .available(
                SelectionSnapshot(
                    text: "ghbdtn",
                    range: SelectionRangeSnapshot(location: 6, length: 6)
                )
            )
        )
        let useCase = SpyFixTextUseCase(availability: .deferred("Still spiking native integrations."))

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: InMemoryConfigurationStore(),
                fixTextUseCase: useCase,
                runtime: runtime
            )
        )

        runtime.fireHotkey()
        await Task.yield()

        #expect(coordinator.lastProbeStatusText?.contains("Focused element resolved") == true)
        #expect(coordinator.lastProbeStatusText?.contains("ghbdtn") == false)
        #expect(useCase.executionCount == 0)
        _ = coordinator
    }

    @Test
    func coordinatorDelegatesMissingSelectionHandlingToUseCase() async {
        let runtime = StubRuntime(
            hasAccessibilityPermission: true,
            selectionProbe: .unavailable(.noSelection)
        )
        let useCase = SpyFixTextUseCase(availability: .available, returnedOutcome: .nothingToFix)

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: InMemoryConfigurationStore(),
                fixTextUseCase: useCase,
                runtime: runtime
            )
        )

        runtime.fireHotkey()
        await Task.yield()

        #expect(coordinator.state.lastFixOutcome == .nothingToFix)
        #expect(coordinator.lastProbeStatusText == HengeCoordinator.statusText(for: .nothingToFix))
        #expect(useCase.executionCount == 1)
        _ = coordinator
    }

    @Test
    func coordinatorDelegatesUnsupportedSelectionHandlingToUseCase() async {
        let runtime = StubRuntime(
            hasAccessibilityPermission: true,
            selectionProbe: .unavailable(.unsupported)
        )
        let useCase = SpyFixTextUseCase(availability: .available, returnedOutcome: .unsupported)

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: InMemoryConfigurationStore(),
                fixTextUseCase: useCase,
                runtime: runtime
            )
        )

        runtime.fireHotkey()
        await Task.yield()

        #expect(useCase.executionCount == 1)
        #expect(coordinator.state.lastFixOutcome == .unsupported)
        #expect(coordinator.lastProbeStatusText == HengeCoordinator.statusText(for: .unsupported))
        _ = coordinator
    }

    @Test
    func availableUseCaseExecutesWhenSelectionIsAvailable() async {
        let runtime = StubRuntime(
            hasAccessibilityPermission: true,
            selectionProbe: .available(
                SelectionSnapshot(
                    text: "ghbdtn",
                    range: SelectionRangeSnapshot(location: 6, length: 6)
                )
            )
        )
        let useCase = SpyFixTextUseCase(availability: .available)

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: InMemoryConfigurationStore(),
                fixTextUseCase: useCase,
                runtime: runtime
            )
        )

        #expect(coordinator.canTriggerFixText == true)

        runtime.fireHotkey()
        await Task.yield()

        #expect(useCase.executionCount == 1)
        #expect(coordinator.state.lastFixOutcome == .fixed(viaClipboard: false))
        #expect(coordinator.lastProbeStatusText == "Text corrected.")
        _ = coordinator
    }

    @Test
    func deferredUseCaseIsNotExecutedEvenWithResolvedSelection() async {
        let runtime = StubRuntime(
            hasAccessibilityPermission: true,
            selectionProbe: .available(
                SelectionSnapshot(
                    text: "ghbdtn",
                    range: SelectionRangeSnapshot(location: 6, length: 6)
                )
            )
        )
        let useCase = SpyFixTextUseCase(availability: .deferred("Still spiking native integrations."))

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: InMemoryConfigurationStore(),
                fixTextUseCase: useCase,
                runtime: runtime
            )
        )

        #expect(coordinator.canTriggerFixText == false)

        runtime.fireHotkey()
        await Task.yield()

        #expect(useCase.executionCount == 0)
        #expect(coordinator.lastProbeStatusText?.contains("Focused element resolved") == true)
        _ = coordinator
    }

    @Test
    func coordinatorSyncsLaunchAtLoginStateFromSystemReality() {
        let store = InMemoryConfigurationStore()
        store.save(AppConfiguration(isEnabled: true, launchAtLogin: true))

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: StubRuntime(hasAccessibilityPermission: true),
                loginItemManager: FakeLoginItemManager(currentStatus: .disabled)
            )
        )

        #expect(coordinator.state.launchAtLoginEnabled == false)
        #expect(coordinator.state.configuration.launchAtLogin == false)
    }

    @Test
    func coordinatorRollsBackLaunchAtLoginStateOnFailure() {
        let store = InMemoryConfigurationStore()
        store.save(AppConfiguration(isEnabled: true, launchAtLogin: true))

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: StubRuntime(hasAccessibilityPermission: true),
                loginItemManager: FailingLoginItemManager(currentStatus: .enabled)
            )
        )

        coordinator.setLaunchAtLogin(false)

        #expect(coordinator.state.launchAtLoginEnabled == true)
        #expect(coordinator.state.configuration.launchAtLogin == true)
        #expect(coordinator.state.launchAtLoginError != nil)
    }

    @Test
    func coordinatorRejectsUnverifiedLaunchAtLoginStateChanges() {
        let store = InMemoryConfigurationStore()
        store.save(AppConfiguration(isEnabled: true, launchAtLogin: true))
        let loginItemManager = NonMutatingLoginItemManager(currentStatus: .enabled)

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: StubRuntime(hasAccessibilityPermission: true),
                loginItemManager: loginItemManager
            )
        )

        coordinator.setLaunchAtLogin(false)

        #expect(loginItemManager.setEnabledCalls == [false])
        #expect(coordinator.state.launchAtLoginEnabled == true)
        #expect(coordinator.state.configuration.launchAtLogin == true)
        #expect(coordinator.state.launchAtLoginError?.contains("could not be verified") == true)
    }

    @Test
    func refreshPermissionsResyncsLaunchAtLoginStateFromSystemReality() {
        let store = InMemoryConfigurationStore()
        let loginItemManager = FakeLoginItemManager(currentStatus: .enabled)

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: StubRuntime(hasAccessibilityPermission: true),
                loginItemManager: loginItemManager
            )
        )

        loginItemManager.updateStatus(.disabled)

        coordinator.refreshPermissions()

        #expect(coordinator.state.launchAtLoginEnabled == false)
        #expect(store.load().launchAtLogin == false)
    }

    @Test
    func coordinatorStatusRefreshDoesNotWriteWhenStateMatches() {
        let store = CountingConfigurationStore(
            initialConfiguration: AppConfiguration(isEnabled: true, launchAtLogin: true)
        )
        let loginItemManager = FakeLoginItemManager(currentStatus: .enabled)

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: StubRuntime(hasAccessibilityPermission: true),
                loginItemManager: loginItemManager
            )
        )

        #expect(store.saveCount == 0)

        for _ in 0..<5 {
            coordinator.refreshPermissions()
        }

        #expect(store.saveCount == 0)
    }

    @Test
    func coordinatorStatusRefreshWritesOnceWhenStateMismatches() {
        let store = CountingConfigurationStore(
            initialConfiguration: AppConfiguration(isEnabled: true, launchAtLogin: true)
        )
        let loginItemManager = FakeLoginItemManager(currentStatus: .disabled)

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: StubRuntime(hasAccessibilityPermission: true),
                loginItemManager: loginItemManager
            )
        )

        // Initial mismatch is normalized once during init.
        #expect(store.saveCount == 1)
        #expect(store.load().launchAtLogin == false)

        for _ in 0..<5 {
            coordinator.refreshPermissions()
        }
        #expect(store.saveCount == 1)

        // Subsequent system-state drift triggers a single corrective write.
        loginItemManager.updateStatus(.enabled)
        for _ in 0..<5 {
            coordinator.refreshPermissions()
        }
        #expect(store.saveCount == 2)
        #expect(store.load().launchAtLogin == true)
    }

    @Test
    func syncLaunchAtLoginStatePreservesConfigurationWhenRequiresApproval() {
        let store = CountingConfigurationStore(
            initialConfiguration: AppConfiguration(isEnabled: true, launchAtLogin: true)
        )
        let loginItemManager = FakeLoginItemManager(currentStatus: .requiresApproval)

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: StubRuntime(hasAccessibilityPermission: true),
                loginItemManager: loginItemManager
            )
        )

        #expect(coordinator.state.launchAtLoginStatus == .requiresApproval)
        #expect(coordinator.state.launchAtLoginEnabled == false)
        #expect(coordinator.state.configuration.launchAtLogin == true)
        #expect(store.load().launchAtLogin == true)
        #expect(store.saveCount == 0)
        #expect(coordinator.launchAtLoginStatusText == "Approval required in System Settings → Login Items.")

        // Refreshing while still awaiting approval keeps config intact and avoids writes.
        coordinator.refreshPermissions()
        #expect(coordinator.state.launchAtLoginStatus == .requiresApproval)
        #expect(coordinator.state.configuration.launchAtLogin == true)
        #expect(store.saveCount == 0)

        // Transitioning from enabled to requiresApproval on refresh also preserves configuration.
        loginItemManager.updateStatus(.enabled)
        coordinator.refreshPermissions()
        #expect(coordinator.state.launchAtLoginStatus == .enabled)
        #expect(coordinator.state.launchAtLoginEnabled == true)
        #expect(coordinator.state.configuration.launchAtLogin == true)

        loginItemManager.updateStatus(.requiresApproval)
        coordinator.refreshPermissions()
        #expect(coordinator.state.launchAtLoginStatus == .requiresApproval)
        #expect(coordinator.state.launchAtLoginEnabled == false)
        #expect(coordinator.state.configuration.launchAtLogin == true)
        #expect(store.load().launchAtLogin == true)
        #expect(store.saveCount == 0)
    }

    @Test
    func setLaunchAtLoginTrueAcceptsRequiresApprovalStatus() {
        let store = InMemoryConfigurationStore()
        store.save(AppConfiguration(isEnabled: true, launchAtLogin: false))
        let loginItemManager = FakeLoginItemManager(
            currentStatus: .disabled,
            enableResultStatus: .requiresApproval
        )

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: StubRuntime(hasAccessibilityPermission: true),
                loginItemManager: loginItemManager
            )
        )

        coordinator.setLaunchAtLogin(true)

        #expect(loginItemManager.setEnabledCalls == [true])
        #expect(coordinator.state.launchAtLoginStatus == .requiresApproval)
        #expect(coordinator.state.launchAtLoginEnabled == false)
        #expect(coordinator.state.configuration.launchAtLogin == true)
        #expect(store.load().launchAtLogin == true)
        #expect(coordinator.state.launchAtLoginError == nil)
        #expect(coordinator.launchAtLoginStatusText == "Approval required in System Settings → Login Items.")

        loginItemManager.updateStatus(.enabled)
        coordinator.refreshPermissions()

        #expect(coordinator.state.launchAtLoginStatus == .enabled)
        #expect(coordinator.state.launchAtLoginEnabled == true)
        #expect(coordinator.launchAtLoginStatusText == "Launch at Login is enabled.")
    }

    @Test
    func openLoginItemSettingsForwardsToLoginItemManager() {
        let loginItemManager = FakeLoginItemManager(currentStatus: .requiresApproval)
        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: InMemoryConfigurationStore(),
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: StubRuntime(hasAccessibilityPermission: true),
                loginItemManager: loginItemManager
            )
        )

        coordinator.openLoginItemSettings()

        #expect(loginItemManager.openLoginItemSettingsCallCount == 1)
    }

    @Test
    func quitApplicationUnregistersHotkeyBeforeTermination() {
        let store = InMemoryConfigurationStore()
        let runtime = StubRuntime(hasAccessibilityPermission: true)
        var terminateCallCount = 0

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: runtime,
                loginItemManager: FakeLoginItemManager(currentStatus: .enabled)
            ),
            terminateApplication: {
                terminateCallCount += 1
            }
        )

        let configurationBeforeQuit = store.load()

        coordinator.quitApplication()

        #expect(runtime.unregisterCount == 1)
        #expect(terminateCallCount == 1)
        #expect(store.load() == configurationBeforeQuit)
    }

    @Test
    func coordinatorShowsReportedOutcome() async {
        let runtime = StubRuntime(
            hasAccessibilityPermission: true,
            selectionProbe: .available(
                SelectionSnapshot(
                    text: "ghbdtn",
                    range: SelectionRangeSnapshot(location: 0, length: 6)
                )
            )
        )
        let useCase = SpyFixTextUseCase(
            availability: .available,
            returnedOutcome: .fixed(viaClipboard: true)
        )
        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: InMemoryConfigurationStore(),
                fixTextUseCase: useCase,
                runtime: runtime,
                loginItemManager: InMemoryLoginItemManager(initialEnabled: true)
            )
        )

        coordinator.triggerFixText()
        for _ in 0..<20 where useCase.executionCount == 0 {
            await Task.yield()
        }
        await Task.yield()

        #expect(useCase.executionCount == 1)
        #expect(coordinator.state.lastFixOutcome == .fixed(viaClipboard: true))
        #expect(coordinator.lastProbeStatusText == "Text corrected using the clipboard fallback.")
    }

    @Test
    func coordinatorLeavesStateCleanWhenUseCaseReturnsExcluded() async {
        let runtime = StubRuntime(
            hasAccessibilityPermission: true,
            selectionProbe: .available(
                SelectionSnapshot(
                    text: "ghbdtn",
                    range: SelectionRangeSnapshot(location: 0, length: 6)
                )
            )
        )
        let useCase = SpyFixTextUseCase(
            availability: .available,
            returnedOutcome: .excluded
        )
        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: InMemoryConfigurationStore(),
                fixTextUseCase: useCase,
                runtime: runtime
            )
        )

        runtime.fireHotkey()
        await Task.yield()

        #expect(useCase.executionCount == 1)
        #expect(coordinator.state.lastFixOutcome == nil)
        #expect(coordinator.lastProbeStatusText == nil)
    }

    @Test
    func statusTextFormatsAllFixOutcomesWithoutExposingUserText() {
        #expect(HengeCoordinator.statusText(for: .fixed(viaClipboard: false)) == "Text corrected.")
        #expect(HengeCoordinator.statusText(for: .fixed(viaClipboard: true)) == "Text corrected using the clipboard fallback.")
        #expect(HengeCoordinator.statusText(for: .nothingToFix) == "Nothing to fix in the current text.")
        #expect(HengeCoordinator.statusText(for: .secureField)?.contains("secure text field") == true)
        #expect(HengeCoordinator.statusText(for: .excluded) == nil)
        #expect(HengeCoordinator.statusText(for: .unsupported)?.isEmpty == false)
        #expect(HengeCoordinator.statusText(for: .pasteUnverified) == SelectionWriteFailure.pasteUnverified.description)
        #expect(HengeCoordinator.statusText(for: .failed(.noActiveApplication))?.contains("active application") == true)
        #expect(HengeCoordinator.statusText(for: .failed(.missingPermission)) == FocusedElementProbeFailure.missingPermission.description)
        #expect(HengeCoordinator.statusText(for: .failed(.noFocusedElement)) == FocusedElementProbeFailure.noFocusedElement.description)
        #expect(HengeCoordinator.statusText(for: .failed(.accessibilityError(-25204)))?.contains("-25204") == true)
        #expect(HengeCoordinator.statusText(for: .failed(.clipboardRestoreFailed)) == SelectionWriteFailure.clipboardRestoreFailed.description)
        #expect(HengeCoordinator.statusText(for: .failed(.clipboardSuperseded)) == SelectionWriteFailure.clipboardSuperseded.description)
        #expect(HengeCoordinator.statusText(for: .failed(.focusLost(applicationName: "Notes")))?.contains("Notes") == true)
    }

    @Test
    func frontmostExcludableApplicationReturnsExternalAppWhenNotExcluded() {
        let notes = ApplicationIdentity(bundleIdentifier: "com.apple.Notes", displayName: "Notes")!
        let runtime = StubRuntime(hasAccessibilityPermission: true)
        runtime.activeApplication = notes

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: InMemoryConfigurationStore(),
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: runtime
            )
        )

        #expect(coordinator.frontmostExcludableApplication == notes)
    }

    @Test
    func frontmostExcludableApplicationSkipsExcludedEmptyAndOwnBundleIdentifiers() {
        let store = InMemoryConfigurationStore()
        store.save(
            AppConfiguration(
                isEnabled: true,
                excludedApplicationBundleIdentifiers: ["com.1password.1password"]
            )
        )
        let runtime = StubRuntime(hasAccessibilityPermission: true)
        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: runtime
            ),
            selfBundleIdentifier: "com.custom.Henge"
        )

        runtime.activeApplication = ApplicationIdentity(bundleIdentifier: "com.1password.1password", displayName: "1Password")
        #expect(coordinator.frontmostExcludableApplication == nil)

        runtime.activeApplication = ApplicationIdentity(bundleIdentifier: "io.github.413d.Henge", displayName: "Henge")
        #expect(coordinator.frontmostExcludableApplication == nil)

        runtime.activeApplication = ApplicationIdentity(bundleIdentifier: "com.custom.Henge", displayName: "Henge")
        #expect(coordinator.frontmostExcludableApplication == nil)

        runtime.activeApplication = ApplicationIdentity(bundleIdentifier: "   ", displayName: "Blank")
        #expect(coordinator.frontmostExcludableApplication == nil)

        runtime.activeApplication = nil
        #expect(coordinator.frontmostExcludableApplication == nil)
    }

    @Test
    func excludeFrontmostApplicationPersistsAndClearsFrontmostExcludableApplication() {
        let notes = ApplicationIdentity(bundleIdentifier: "com.apple.Notes", displayName: "Notes")!
        let store = InMemoryConfigurationStore()
        let runtime = StubRuntime(hasAccessibilityPermission: true)
        runtime.activeApplication = notes

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: runtime
            )
        )

        #expect(coordinator.frontmostExcludableApplication == notes)

        let didExclude = coordinator.excludeFrontmostApplication()
        #expect(didExclude == true)
        #expect(store.load().excludedApplicationBundleIdentifiers == ["com.apple.Notes"])
        #expect(coordinator.state.configuration.excludedApplicationBundleIdentifiers == ["com.apple.Notes"])
        #expect(coordinator.frontmostExcludableApplication == nil)

        #expect(coordinator.excludeFrontmostApplication() == false)
    }

    @Test
    func refreshPermissionsNotifiesWhenFrontmostExcludableApplicationChanges() {
        let notes = ApplicationIdentity(bundleIdentifier: "com.apple.Notes", displayName: "Notes")!
        let safari = ApplicationIdentity(bundleIdentifier: "com.apple.Safari", displayName: "Safari")!
        let runtime = StubRuntime(hasAccessibilityPermission: true)
        runtime.activeApplication = notes

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: InMemoryConfigurationStore(),
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: runtime
            )
        )

        var changeNotifications = 0
        let cancellable = coordinator.objectWillChange.sink { _ in
            changeNotifications += 1
        }
        defer { cancellable.cancel() }

        coordinator.refreshPermissions()
        #expect(changeNotifications == 0)

        runtime.activeApplication = safari
        coordinator.refreshPermissions()
        #expect(changeNotifications == 1)
        #expect(coordinator.frontmostExcludableApplication == safari)
    }
}

private extension AppEnvironment {
    init(
        configurationStore: ConfigurationStore,
        fixTextUseCase: FixTextUseCaseProtocol,
        runtime: AppRuntime
    ) {
        self.init(
            configurationStore: configurationStore,
            fixTextUseCase: fixTextUseCase,
            runtime: runtime,
            loginItemManager: InMemoryLoginItemManager(initialEnabled: true)
        )
    }
}

private final class CountingConfigurationStore: ConfigurationStore {
    private var configuration: AppConfiguration
    private(set) var saveCount = 0

    init(initialConfiguration: AppConfiguration = .default) {
        configuration = initialConfiguration
    }

    func load() -> AppConfiguration {
        configuration
    }

    func save(_ configuration: AppConfiguration) {
        saveCount += 1
        self.configuration = configuration
    }
}

private final class FakeLoginItemManager: LoginItemManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var currentStatus: LoginItemStatus
    private let enableResultStatus: LoginItemStatus
    private(set) var setEnabledCalls: [Bool] = []
    private(set) var openLoginItemSettingsCallCount = 0

    init(currentStatus: LoginItemStatus, enableResultStatus: LoginItemStatus = .enabled) {
        self.currentStatus = currentStatus
        self.enableResultStatus = enableResultStatus
    }

    var status: LoginItemStatus {
        lock.lock(); defer { lock.unlock() }
        return currentStatus
    }

    func setEnabled(_ enabled: Bool) throws {
        lock.lock(); defer { lock.unlock() }
        setEnabledCalls.append(enabled)
        currentStatus = enabled ? enableResultStatus : .disabled
    }

    func openLoginItemSettings() {
        lock.lock(); defer { lock.unlock() }
        openLoginItemSettingsCallCount += 1
    }

    func updateStatus(_ status: LoginItemStatus) {
        lock.lock(); defer { lock.unlock() }
        currentStatus = status
    }
}

private final class FailingLoginItemManager: LoginItemManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var currentStatus: LoginItemStatus

    init(currentStatus: LoginItemStatus) {
        self.currentStatus = currentStatus
    }

    var status: LoginItemStatus {
        lock.lock(); defer { lock.unlock() }
        return currentStatus
    }

    func setEnabled(_ enabled: Bool) throws {
        throw LoginItemUpdateError.updateFailed("Launch at Login update failed.")
    }

    func openLoginItemSettings() {}
}

private final class NonMutatingLoginItemManager: LoginItemManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var currentStatus: LoginItemStatus
    private(set) var setEnabledCalls: [Bool] = []

    init(currentStatus: LoginItemStatus) {
        self.currentStatus = currentStatus
    }

    var status: LoginItemStatus {
        lock.lock(); defer { lock.unlock() }
        return currentStatus
    }

    func setEnabled(_ enabled: Bool) throws {
        lock.lock(); defer { lock.unlock() }
        setEnabledCalls.append(enabled)
    }

    func openLoginItemSettings() {}
}

private final class StubRuntime: AppRuntime {
    var hasAccessibilityPermission: Bool
    var activeApplication: ApplicationIdentity? = ApplicationIdentity(bundleIdentifier: "test.application", displayName: "Test Application")
    let layoutMapper: LayoutMapping
    let clipboardManager: ClipboardManaging
    private let registrationError: Error?
    private let focusedElementProbe: FocusedElementProbe
    private let selectionProbe: SelectionProbe

    private(set) var registeredShortcuts: [Shortcut] = []
    private(set) var unregisterCount = 0
    private var hotkeyHandler: (() -> Void)?

    init(
        hasAccessibilityPermission: Bool,
        registrationError: Error? = nil,
        focusedElementProbe: FocusedElementProbe = .available(
            FocusedElementSnapshot(role: "AXTextField", subrole: nil, isSecure: false)
        ),
        selectionProbe: SelectionProbe = .unavailable(.noSelection),
        layoutMapper: LayoutMapping = NativeKeyboardLayoutMapper(),
        clipboardManager: ClipboardManaging = MockClipboardManager()
    ) {
        self.hasAccessibilityPermission = hasAccessibilityPermission
        self.registrationError = registrationError
        self.focusedElementProbe = focusedElementProbe
        self.selectionProbe = selectionProbe
        self.layoutMapper = layoutMapper
        self.clipboardManager = clipboardManager
    }

    func openAccessibilitySettings() {
    }

    func registerFixTextHotkey(_ shortcut: Shortcut, handler: @escaping () -> Void) throws {
        if let registrationError {
            throw registrationError
        }

        guard CarbonHotkey.isSupported(shortcut: shortcut) else {
            throw HotkeyRegistrationError.unsupportedShortcut(shortcut.key)
        }

        registeredShortcuts.append(shortcut)
        hotkeyHandler = handler
    }

    func unregisterFixTextHotkey() {
        unregisterCount += 1
        hotkeyHandler = nil
    }

    func inspectFocusedElement() -> FocusedElementProbe {
        focusedElementProbe
    }

    func inspectTextContext(in application: ApplicationIdentity) -> TextContextProbe {
        makeTestTextContext(selectionProbe, in: application)
    }

    func replaceText(
        _ target: TextTarget,
        range: SelectionRangeSnapshot,
        context: SelectionSnapshot,
        expectedText: String,
        with text: String
    ) -> SelectionWriteResult {
        switch selectionProbe {
        case let .available(snapshot):
            return .success(snapshot.range)
        case let .unavailable(reason):
            return .unavailable(.init(from: reason))
        }
    }

    func fireHotkey() {
        hotkeyHandler?()
    }
}

private final class SpyFixTextUseCase: FixTextUseCaseProtocol {
    let availability: FixTextAvailability
    private let returnedOutcome: FixOutcome
    private(set) var executionCount = 0

    init(
        availability: FixTextAvailability,
        returnedOutcome: FixOutcome = .fixed(viaClipboard: false)
    ) {
        self.availability = availability
        self.returnedOutcome = returnedOutcome
    }

    @discardableResult
    func execute(excludingApplicationBundleIdentifiers: [String]) -> FixOutcome {
        executionCount += 1
        return returnedOutcome
    }
}
