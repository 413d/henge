import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var coordinator: HengeCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(
                L10n.string("menubar.toggle.enabled", defaultValue: "Enabled"),
                isOn: enabledBinding
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("menubar.section.shortcut", defaultValue: "Shortcut"))
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
                Text(
                    coordinator.state.accessibilityGranted
                        ? L10n.string("menubar.accessibility.granted", defaultValue: "Accessibility access granted")
                        : L10n.string("menubar.accessibility.required", defaultValue: "Accessibility access required")
                )
                    .font(.callout)

                if !coordinator.state.accessibilityGranted {
                    Button(L10n.string("action.open_accessibility_settings", defaultValue: "Open Accessibility Settings")) {
                        coordinator.openAccessibilitySettings()
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("section.text_correction", defaultValue: "Text correction"))
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

            Button(L10n.string("menubar.action.fix_text", defaultValue: "Fix Text")) {
                coordinator.triggerFixText()
            }
            .disabled(!coordinator.canTriggerFixText)

            if let app = coordinator.frontmostExcludableApplication {
                let trimmedDisplayName = app.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                let labelName = trimmedDisplayName.isEmpty ? app.bundleIdentifier : trimmedDisplayName
                Button(
                    L10n.format(
                        "menubar.action.exclude_app",
                        defaultValue: "Exclude %@",
                        labelName
                    )
                ) {
                    coordinator.excludeFrontmostApplication()
                }
            }

            Button(L10n.string("menubar.action.settings", defaultValue: "Settings…")) {
                coordinator.openSettings()
            }

            Button(L10n.string("menubar.action.quit", defaultValue: "Quit Henge")) {
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
        L10n.string(
            "menubar.text_correction.ready",
            defaultValue: "Ready to run with the current focused text context."
        )
    }
}

@MainActor
final class MenuBarLifecycleObserver {
    private let menuNotificationCenter: NotificationCenter
    private weak var coordinator: HengeCoordinator?
    nonisolated(unsafe) private var menuToken: NSObjectProtocol?

    init(
        menuNotificationCenter: NotificationCenter = .default
    ) {
        self.menuNotificationCenter = menuNotificationCenter
    }

    deinit {
        if let menuToken {
            menuNotificationCenter.removeObserver(menuToken)
        }
    }

    func bind(coordinator: HengeCoordinator) {
        self.coordinator = coordinator
        if let menuToken {
            menuNotificationCenter.removeObserver(menuToken)
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
    }
}
