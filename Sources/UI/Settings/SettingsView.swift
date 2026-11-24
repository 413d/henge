import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var coordinator: HengeCoordinator
    @State private var isChoosingApplication = false
    @State private var isRecordingShortcut = false
    @State private var shortcutCaptureMessage: String?
    @State private var isConfirmingReset = false

    var body: some View {
        Form {
            Section(L10n.string("settings.section.general", defaultValue: "General")) {
                Toggle(
                    L10n.string("settings.toggle.enable_henge", defaultValue: "Enable Henge"),
                    isOn: enabledBinding
                )
                Toggle(
                    L10n.string("settings.toggle.launch_at_login", defaultValue: "Launch at Login"),
                    isOn: launchAtLoginBinding
                )

                LabeledContent(L10n.string("settings.label.global_shortcut", defaultValue: "Global shortcut")) {
                    HStack {
                        Text(coordinator.shortcutDescription)
                            .monospaced()
                        Button(
                            isRecordingShortcut
                                ? L10n.string("settings.shortcut.press", defaultValue: "Press shortcut…")
                                : L10n.string("settings.shortcut.change", defaultValue: "Change…")
                        ) {
                            shortcutCaptureMessage = nil
                            isRecordingShortcut = true
                        }
                    }
                }

                if isRecordingShortcut {
                    ShortcutRecorder { result in
                        isRecordingShortcut = false
                        switch result {
                        case let .captured(shortcut):
                            shortcutCaptureMessage = nil
                            coordinator.setShortcut(shortcut)
                        case .cancelled:
                            shortcutCaptureMessage = nil
                        case .missingModifiers:
                            shortcutCaptureMessage = L10n.string(
                                "settings.shortcut.error_modifiers",
                                defaultValue: "Use a key together with ⌘, ⌥, ⌃, or ⇧."
                            )
                        case let .unsupportedKey(keyLabel):
                            shortcutCaptureMessage = L10n.format(
                                "hotkey.error.unsupported_shortcut",
                                defaultValue: "The shortcut key %@ is not supported by the current global hotkey backend.",
                                keyLabel
                            )
                        }
                    }
                    .frame(height: 30)
                    Text(
                        L10n.string(
                            "settings.shortcut.hint",
                            defaultValue: "Press a key with at least one modifier. Escape cancels."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if let shortcutCaptureMessage {
                    Text(shortcutCaptureMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
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

                if coordinator.state.launchAtLoginStatus == .requiresApproval || coordinator.state.launchAtLoginError != nil {
                    Button(L10n.string("settings.action.open_login_items", defaultValue: "Open Login Items…")) {
                        coordinator.openLoginItemSettings()
                    }
                }
            }

            Section(L10n.string("settings.section.permissions", defaultValue: "Permissions")) {
                Text(
                    coordinator.state.accessibilityGranted
                        ? L10n.string("settings.permissions.accessibility_granted", defaultValue: "Accessibility permission is available.")
                        : L10n.string("settings.permissions.accessibility_missing", defaultValue: "Accessibility permission is not granted yet.")
                )

                if !coordinator.state.accessibilityGranted {
                    Button(L10n.string("action.open_accessibility_settings", defaultValue: "Open Accessibility Settings")) {
                        coordinator.openAccessibilitySettings()
                    }
                }
            }

            Section(L10n.string("settings.section.exceptions", defaultValue: "Exceptions")) {
                if coordinator.state.configuration.excludedApplicationBundleIdentifiers.isEmpty {
                    Text(L10n.string("settings.exceptions.empty", defaultValue: "No excluded applications."))
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
                            Button(L10n.string("settings.exceptions.remove", defaultValue: "Remove")) {
                                coordinator.removeApplicationException(bundleIdentifier: bundleIdentifier)
                            }
                        }
                    }
                }

                Button(L10n.string("settings.exceptions.add", defaultValue: "Add Application…")) {
                    isChoosingApplication = true
                }
            }

            Section(L10n.string("section.text_correction", defaultValue: "Text correction")) {
                Text(fixTextStatusText)
                    .foregroundStyle(.secondary)

                if let lastProbeStatusText = coordinator.lastProbeStatusText {
                    Text(lastProbeStatusText)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button(
                    L10n.string("settings.reset.button", defaultValue: "Reset Settings to Defaults…"),
                    role: .destructive
                ) {
                    isConfirmingReset = true
                }
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 420)
        .onAppear {
            coordinator.refreshPermissions()
        }
        .confirmationDialog(
            L10n.string("settings.reset.dialog_title", defaultValue: "Reset all Henge settings?"),
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button(
                L10n.string("settings.reset.confirm", defaultValue: "Reset Settings"),
                role: .destructive
            ) {
                coordinator.resetConfigurationToDefaults()
            }
        } message: {
            Text(
                L10n.string(
                    "settings.reset.dialog_message",
                    defaultValue: "This restores the default shortcut and removes application exceptions."
                )
            )
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
        L10n.string(
            "settings.text_correction.available",
            defaultValue: "Text correction is available."
        )
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let onCapture: (ShortcutCaptureResult) -> Void

    func makeNSView(context: Context) -> ShortcutCaptureView {
        let view = ShortcutCaptureView()
        view.onCapture = onCapture
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureView, context: Context) {
        nsView.onCapture = onCapture
    }
}

private final class ShortcutCaptureView: NSView {
    var onCapture: ((ShortcutCaptureResult) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        let text = L10n.string(
            "settings.shortcut.placeholder",
            defaultValue: "Type the new shortcut…"
        )
        (text as NSString).draw(at: NSPoint(x: 8, y: 6), withAttributes: [.foregroundColor: NSColor.secondaryLabelColor])
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: Shortcut.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }

        let result = ShortcutCaptureEvaluator.evaluate(
            keyCode: event.keyCode,
            modifiers: modifiers,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers
        )
        onCapture?(result)
    }
}

@MainActor
final class SettingsWindowController {
    private let windowController: SingletonWindowController<SettingsView>

    init(
        coordinator: HengeCoordinator? = nil,
        activateApplication: (@MainActor () -> Void)? = nil,
        presentWindow: (@MainActor (NSWindow) -> Void)? = nil
    ) {
        windowController = SingletonWindowController(
            coordinator: coordinator,
            title: L10n.string("settings.window.title", defaultValue: "Henge Settings"),
            styleMask: [.titled, .closable, .miniaturizable],
            contentSize: NSSize(width: 520, height: 460),
            activateApplication: activateApplication,
            presentWindow: presentWindow,
            makeContent: { SettingsView() }
        )
    }

    func bind(coordinator: HengeCoordinator) {
        windowController.bind(coordinator: coordinator)
    }

    @discardableResult
    func showWindow() -> NSWindow? {
        windowController.showWindow()
    }
}

