import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var coordinator: HengeCoordinator

    var body: some View {
        Form {
            Section("General") {
                Toggle("Enable Henge", isOn: enabledBinding)

                LabeledContent("Default shortcut") {
                    Text(coordinator.shortcutDescription)
                }

                Text(coordinator.hotkeyStatusText)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                Text(coordinator.state.accessibilityGranted ? "Accessibility permission is available." : "Accessibility permission is not granted yet.")

                if !coordinator.state.accessibilityGranted {
                    Button("Open Accessibility Settings") {
                        coordinator.openAccessibilitySettings()
                    }
                }
            }

            Section("Milestone status") {
                Text("Project skeleton and configuration persistence are in place. Global hotkey registration is now wired for native validation, while text extraction and replacement remain in progress.")
                    .foregroundStyle(.secondary)
            }

            Section("Text correction") {
                Text(fixTextStatusText)
                    .foregroundStyle(.secondary)

                if let lastProbeStatusText = coordinator.lastProbeStatusText {
                    Text(lastProbeStatusText)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 280)
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
            return "Text correction is available."
        case let .deferred(message):
            return message
        }
    }
}
