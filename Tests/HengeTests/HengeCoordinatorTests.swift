import Testing
@testable import Henge

@MainActor
struct HengeCoordinatorTests {
    @Test
    func coordinatorLoadsConfigurationFromStore() {
        let store = InMemoryConfigurationStore()
        store.save(AppConfiguration(isEnabled: false, shortcut: .defaultFixText))

        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: StubRuntime(hasAccessibilityPermission: true)
            )
        )

        #expect(coordinator.isEnabled == false)
    }

    @Test
    func coordinatorPersistsEnablementChanges() {
        let store = InMemoryConfigurationStore()
        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: StubRuntime(hasAccessibilityPermission: false)
            )
        )

        coordinator.setEnabled(false)

        #expect(store.load().isEnabled == false)
    }

    @Test
    func deferredFixTextCannotBeTriggeredFromSkeleton() {
        let store = InMemoryConfigurationStore()
        let coordinator = HengeCoordinator(
            environment: AppEnvironment(
                configurationStore: store,
                fixTextUseCase: DeferredFixTextUseCase(),
                runtime: StubRuntime(hasAccessibilityPermission: true)
            )
        )

        #expect(coordinator.canTriggerFixText == false)
    }
}

private struct StubRuntime: AppRuntime {
    let hasAccessibilityPermission: Bool

    func openAccessibilitySettings() {
    }
}
