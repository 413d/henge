import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var coordinator: HengeCoordinator
    @State private var isChoosingApplication = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Enable Henge", isOn: enabledBinding)
                Toggle("Launch at Login", isOn: launchAtLoginBinding)

                LabeledContent("Default shortcut") {
                    Text(coordinator.shortcutDescription)
                }

                Text(coordinator.hotkeyStatusText)
                    .foregroundStyle(.secondary)

                if coordinator.state.launchAtLoginError == nil {
                    Text(coordinator.launchAtLoginStatusText)
                        .foregroundStyle(.secondary)
                } else {
                    Text(coordinator.launchAtLoginStatusText)
                        .foregroundStyle(.red)
                }
            }

            Section("Permissions") {
                Text(coordinator.state.accessibilityGranted ? "Accessibility permission is available." : "Accessibility permission is not granted yet.")

                if !coordinator.state.accessibilityGranted {
                    Button("Open Accessibility Settings") {
                        coordinator.openAccessibilitySettings()
                    }
                }
            }

            Section("Exceptions") {
                if coordinator.state.configuration.excludedApplicationBundleIdentifiers.isEmpty {
                    Text("No excluded applications.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(coordinator.state.configuration.excludedApplicationBundleIdentifiers, id: \.self) { bundleIdentifier in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(coordinator.applicationDisplayName(for: bundleIdentifier))
                                Text(bundleIdentifier)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Remove") {
                                coordinator.removeApplicationException(bundleIdentifier: bundleIdentifier)
                            }
                        }
                    }
                }

                Button("Add Application…") {
                    isChoosingApplication = true
                }
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
        .frame(minWidth: 460, minHeight: 420)
        .onAppear {
            coordinator.refreshPermissions()
        }
        .fileImporter(isPresented: $isChoosingApplication, allowedContentTypes: [.applicationBundle], allowsMultipleSelection: false) { result in
            guard case let .success(urls) = result,
                  let url = urls.first else {
                return
            }
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            guard let bundle = Bundle(url: url),
                  let bundleIdentifier = bundle.bundleIdentifier else {
                return
            }
            let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            if let application = ApplicationIdentity(bundleIdentifier: bundleIdentifier, displayName: displayName) {
                coordinator.addApplicationException(application)
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { coordinator.isEnabled },
            set: { coordinator.setEnabled($0) }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { coordinator.state.launchAtLoginEnabled },
            set: { coordinator.setLaunchAtLogin($0) }
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
