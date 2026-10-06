import Foundation
import SwiftUI

@MainActor
final class HengeCoordinator: ObservableObject {
    @Published private(set) var state: ApplicationState

    private let configurationStore: ConfigurationStore
    private let fixTextUseCase: FixTextUseCaseProtocol
    private let runtime: AppRuntime

    init(environment: AppEnvironment) {
        configurationStore = environment.configurationStore
        fixTextUseCase = environment.fixTextUseCase
        runtime = environment.runtime
        state = ApplicationState(
            configuration: environment.configurationStore.load(),
            accessibilityGranted: environment.runtime.hasAccessibilityPermission
        )
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

    var statusItemSymbolName: String {
        state.configuration.isEnabled ? "keyboard" : "keyboard.badge.ellipsis"
    }

    func setEnabled(_ isEnabled: Bool) {
        state.configuration.isEnabled = isEnabled
        configurationStore.save(state.configuration)
    }

    func triggerFixText() {
        guard canTriggerFixText else {
            return
        }

        fixTextUseCase.execute()
    }

    func refreshPermissions() {
        state.accessibilityGranted = runtime.hasAccessibilityPermission
    }

    func openAccessibilitySettings() {
        runtime.openAccessibilitySettings()
    }
}
