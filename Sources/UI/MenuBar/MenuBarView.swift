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
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
