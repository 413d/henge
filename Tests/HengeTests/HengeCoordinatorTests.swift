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

        #expect(coordinator.lastProbeStatusText?.contains("Correction attempted") == true)
        #expect(useCase.executionCount == 1)
        _ = coordinator
    }

    @Test
    func coordinatorDelegatesUnsupportedSelectionHandlingToUseCase() async {
        let runtime = StubRuntime(
            hasAccessibilityPermission: true,
            selectionProbe: .unavailable(.unsupported)
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

        #expect(useCase.executionCount == 1)
        #expect(coordinator.lastProbeStatusText?.contains("Correction attempted") == true)
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
        #expect(coordinator.lastProbeStatusText?.contains("Correction attempted") == true)
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

        guard CarbonHotkey.isSupported(key: shortcut.key) else {
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

    func inspectSelection() -> SelectionProbe {
        selectionProbe
    }

    func replaceSelection(with text: String) -> SelectionWriteResult {
        switch selectionProbe {
        case let .available(snapshot):
            return .success(snapshot.range)
        case let .unavailable(reason):
            switch reason {
            case .missingPermission:
                return .unavailable(.missingPermission)
            case .noFocusedElement:
                return .unavailable(.noFocusedElement)
            case .secureField:
                return .unavailable(.secureField)
            case .noSelection:
                return .unavailable(.noSelection)
            case .unsupported:
                return .unavailable(.unsupported)
            case let .accessibilityError(error):
                return .unavailable(.accessibilityError(error))
            }
        }
    }

    func fireHotkey() {
        hotkeyHandler?()
    }
}

private final class SpyFixTextUseCase: FixTextUseCaseProtocol {
    let availability: FixTextAvailability
    private(set) var executionCount = 0

    init(availability: FixTextAvailability) {
        self.availability = availability
    }

    func execute(excludingApplicationBundleIdentifiers: Set<String>) {
        executionCount += 1
    }
}
