import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var coordinator: HengeCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enabled", isOn: enabledBinding)

            VStack(alignment: .leading, spacing: 4) {
                Text("Shortcut")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(coordinator.shortcutDescription)
                    .font(.system(.body, design: .rounded).weight(.semibold))

                Text(coordinator.hotkeyStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(coordinator.state.accessibilityGranted ? "Accessibility access granted" : "Accessibility access required")
                    .font(.callout)

                if !coordinator.state.accessibilityGranted {
                    Button("Open Accessibility Settings") {
                        coordinator.openAccessibilitySettings()
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Text correction")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(fixTextStatusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let lastProbeStatusText = coordinator.lastProbeStatusText {
                    Text(lastProbeStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Button("Fix Text") {
                coordinator.triggerFixText()
            }
            .disabled(!coordinator.canTriggerFixText)

            Button("Settings…") {
                coordinator.openSettings()
            }

            Button("Quit Henge") {
                coordinator.quitApplication()
            }
        }
        .padding(12)
        .frame(width: 240)
        .onAppear {
            coordinator.refreshPermissions()
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { coordinator.isEnabled },
            set: { coordinator.setEnabled($0) }
        )
    }

    private var fixTextStatusText: String {
        switch coordinator.fixTextAvailability {
        case .available:
            return "Ready to run with the current focused text context."
        case let .deferred(message):
            return message
        }
    }
}

@MainActor
final class MenuBarLifecycleObserver {
    private let menuNotificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter
    private weak var coordinator: HengeCoordinator?
    nonisolated(unsafe) private var menuToken: NSObjectProtocol?
    nonisolated(unsafe) private var workspaceToken: NSObjectProtocol?

    init(
        menuNotificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.menuNotificationCenter = menuNotificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
    }

    deinit {
        if let menuToken {
            menuNotificationCenter.removeObserver(menuToken)
        }
        if let workspaceToken {
            workspaceNotificationCenter.removeObserver(workspaceToken)
        }
    }

    func bind(coordinator: HengeCoordinator) {
        self.coordinator = coordinator
        if let menuToken {
            menuNotificationCenter.removeObserver(menuToken)
        }
        if let workspaceToken {
            workspaceNotificationCenter.removeObserver(workspaceToken)
        }

        menuToken = menuNotificationCenter.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: nil
        ) { [weak coordinator] _ in
            Task { @MainActor in
                coordinator?.refreshPermissions()
            }
        }

        workspaceToken = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak coordinator] _ in
            Task { @MainActor in
                coordinator?.refreshPermissions()
            }
        }
    }
}
