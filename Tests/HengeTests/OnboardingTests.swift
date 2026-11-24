import AppKit
import Foundation
import Testing
@testable import Henge

@MainActor
struct OnboardingTests {
    @Test
    func decodesMissingHasCompletedOnboardingAsFalseAndPreservesTrueValue() throws {
        let legacyJSON = """
        {
          "excludedApplicationBundleIdentifiers": ["com.apple.Terminal"],
          "isEnabled": true,
          "launchAtLogin": false,
          "schemaVersion": 1,
          "shortcut": {
            "key": "X",
            "modifiers": {
              "rawValue": 2
            }
          }
        }
        """

        let legacyConfig = try JSONDecoder().decode(
            AppConfiguration.self,
            from: Data(legacyJSON.utf8)
        )
        #expect(legacyConfig.hasCompletedOnboarding == false)

        let updatedConfig = AppConfiguration(
            isEnabled: true,
            launchAtLogin: false,
            shortcut: .defaultFixText,
            excludedApplicationBundleIdentifiers: ["com.apple.Terminal"],
            hasCompletedOnboarding: true
        )
        let encoded = try JSONEncoder().encode(updatedConfig)
        let roundTripped = try JSONDecoder().decode(AppConfiguration.self, from: encoded)
        #expect(roundTripped.hasCompletedOnboarding == true)
    }

    @Test
    func startOnboardingIfNeededPresentsWhenFirstLaunchWithoutAccessibility() {
        let store = OnboardingInMemoryStore()
        let runtime = OnboardingTestRuntime(hasAccessibilityPermission: false)
        var presentCount = 0

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: runtime,
                loginItemManager: OnboardingTestLoginItemManager(status: .disabled)
            ),
            presentOnboarding: {
                presentCount += 1
            }
        )

        coordinator.startOnboardingIfNeeded()

        #expect(presentCount == 1)
        #expect(coordinator.state.configuration.hasCompletedOnboarding == false)
        #expect(store.load().hasCompletedOnboarding == false)
    }

    @Test
    func startOnboardingIfNeededSkipsAndPersistsCompletionWhenAccessibilityAlreadyGranted() {
        let store = OnboardingInMemoryStore()
        let runtime = OnboardingTestRuntime(hasAccessibilityPermission: true)
        var presentCount = 0

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: runtime,
                loginItemManager: OnboardingTestLoginItemManager(status: .disabled)
            ),
            presentOnboarding: {
                presentCount += 1
            }
        )

        coordinator.startOnboardingIfNeeded()

        #expect(presentCount == 0)
        #expect(coordinator.state.configuration.hasCompletedOnboarding == true)
        #expect(store.load().hasCompletedOnboarding == true)
    }

    @Test
    func startOnboardingIfNeededDoesNotPresentWhenAlreadyCompletedEvenWithoutAccessibility() {
        let store = OnboardingInMemoryStore(
            initialConfiguration: AppConfiguration(hasCompletedOnboarding: true)
        )
        let runtime = OnboardingTestRuntime(hasAccessibilityPermission: false)
        var presentCount = 0

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: runtime,
                loginItemManager: OnboardingTestLoginItemManager(status: .disabled)
            ),
            presentOnboarding: {
                presentCount += 1
            }
        )

        coordinator.startOnboardingIfNeeded()

        #expect(presentCount == 0)
        #expect(coordinator.state.configuration.hasCompletedOnboarding == true)
    }

    @Test
    func completeOnboardingPersistsCompletionAndDismissesOncePerChange() {
        let store = OnboardingInMemoryStore()
        let runtime = OnboardingTestRuntime(hasAccessibilityPermission: false)
        var dismissCount = 0

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: runtime,
                loginItemManager: OnboardingTestLoginItemManager(status: .disabled)
            ),
            dismissOnboarding: {
                dismissCount += 1
            }
        )

        let savesBefore = store.saveCount
        coordinator.completeOnboarding()

        #expect(coordinator.state.configuration.hasCompletedOnboarding == true)
        #expect(store.load().hasCompletedOnboarding == true)
        #expect(store.saveCount == savesBefore + 1)
        #expect(dismissCount == 1)

        coordinator.completeOnboarding()
        #expect(store.saveCount == savesBefore + 1)
        #expect(dismissCount == 2)
    }

    @Test
    func resetConfigurationToDefaultsPreservesCompletedOnboardingFlag() {
        let store = OnboardingInMemoryStore(
            initialConfiguration: AppConfiguration(
                isEnabled: false,
                launchAtLogin: false,
                shortcut: Shortcut(key: "Z", modifiers: [.option]),
                excludedApplicationBundleIdentifiers: ["com.example.App"],
                hasCompletedOnboarding: true
            )
        )
        let runtime = OnboardingTestRuntime(hasAccessibilityPermission: false)
        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: runtime,
                loginItemManager: OnboardingTestLoginItemManager(status: .disabled)
            )
        )

        coordinator.resetConfigurationToDefaults()

        #expect(coordinator.state.configuration.hasCompletedOnboarding == true)
        #expect(store.load().hasCompletedOnboarding == true)
        #expect(store.load().shortcut == .defaultFixText)
        #expect(store.load().excludedApplicationBundleIdentifiers.isEmpty)
    }

    @Test
    func requestAccessibilityPermissionDelegatesToRuntime() {
        let store = OnboardingInMemoryStore()
        let runtime = OnboardingTestRuntime(hasAccessibilityPermission: false)
        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: runtime,
                loginItemManager: OnboardingTestLoginItemManager(status: .disabled)
            )
        )

        coordinator.requestAccessibilityPermission()

        #expect(runtime.requestAccessibilityPermissionCallCount == 1)
    }

    @Test
    func onboardingWindowControllerReusesSingleWindowAndCompletesOnClose() {
        let store = OnboardingInMemoryStore()
        let runtime = OnboardingTestRuntime(hasAccessibilityPermission: false)
        var activationCount = 0
        var presentedWindows: [NSWindow] = []

        let controller = OnboardingWindowController(
            activateApplication: {
                activationCount += 1
            },
            presentWindow: { window in
                presentedWindows.append(window)
            }
        )

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: runtime,
                loginItemManager: OnboardingTestLoginItemManager(status: .disabled)
            ),
            presentOnboarding: {
                controller.showWindow()
            },
            dismissOnboarding: {
                controller.closeWindow()
            }
        )
        controller.bind(coordinator: coordinator)

        coordinator.startOnboardingIfNeeded()
        defer { presentedWindows.first?.orderOut(nil) }

        #expect(presentedWindows.count == 1)
        let firstWindow = presentedWindows[0]
        #expect(firstWindow.title == "Welcome to Henge")
        #expect(firstWindow.isReleasedWhenClosed == false)
        #expect(firstWindow.styleMask.contains(.titled))
        #expect(firstWindow.styleMask.contains(.closable))
        #expect(activationCount == 1)
        #expect(coordinator.state.configuration.hasCompletedOnboarding == false)

        firstWindow.close()

        #expect(coordinator.state.configuration.hasCompletedOnboarding == true)
        #expect(store.load().hasCompletedOnboarding == true)

        let reopenedWindow = controller.showWindow()
        #expect(reopenedWindow === firstWindow)
        #expect(activationCount == 2)
        #expect(presentedWindows.count == 2)
    }
}

private final class OnboardingInMemoryStore: ConfigurationStore {
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

private final class OnboardingTestLoginItemManager: LoginItemManaging, @unchecked Sendable {
    var status: LoginItemStatus

    init(status: LoginItemStatus) {
        self.status = status
    }

    func setEnabled(_ enabled: Bool) throws {
        status = enabled ? .enabled : .disabled
    }

    func openLoginItemSettings() {}
}

private final class OnboardingTestRuntime: AppRuntime {
    var hasAccessibilityPermission: Bool
    var activeApplication: ApplicationIdentity?
    let layoutMapper: LayoutMapping = NativeKeyboardLayoutMapper()
    let clipboardManager: ClipboardManaging = MockClipboardManager()
    private(set) var requestAccessibilityPermissionCallCount = 0

    init(hasAccessibilityPermission: Bool) {
        self.hasAccessibilityPermission = hasAccessibilityPermission
    }

    func openAccessibilitySettings() {}

    func requestAccessibilityPermission() {
        requestAccessibilityPermissionCallCount += 1
    }

    func registerFixTextHotkey(_ shortcut: Shortcut, handler: @escaping () -> Void) throws {}
    func unregisterFixTextHotkey() {}

    func inspectFocusedElement() -> FocusedElementProbe {
        .unavailable(.noFocusedElement)
    }

    func inspectTextContext(in application: ApplicationIdentity) -> TextContextProbe {
        .unavailable(.noSelection)
    }

    func replaceText(
        _ target: TextTarget,
        range: SelectionRangeSnapshot,
        context: SelectionSnapshot,
        expectedText: String,
        with text: String
    ) -> SelectionWriteResult {
        .unavailable(.unsupported)
    }
}
