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
                    ShortcutRecorder { shortcut in
                        isRecordingShortcut = false
                        guard let shortcut else {
                            shortcutCaptureMessage = L10n.string(
                                "settings.shortcut.error_modifiers",
                                defaultValue: "Use a key together with ⌘, ⌥, ⌃, or ⇧."
                            )
                            return
                        }
                        coordinator.setShortcut(shortcut)
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
        switch coordinator.fixTextAvailability {
        case .available:
            return L10n.string(
                "settings.text_correction.available",
                defaultValue: "Text correction is available."
            )
        case let .deferred(message):
            return message
        }
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let onCapture: (Shortcut?) -> Void

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
    var onCapture: ((Shortcut?) -> Void)?

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
        if event.keyCode == 53 {
            onCapture?(nil)
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: Shortcut.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }

        let keyCode = UInt32(event.keyCode)
        guard !modifiers.isEmpty,
              let key = CarbonHotkey.displayKey(forKeyCode: keyCode) else {
            onCapture?(nil)
            return
        }

        let shortcut = Shortcut(key: key, modifiers: modifiers, keyCode: keyCode)
        guard CarbonHotkey.isSupported(shortcut: shortcut) else {
            onCapture?(nil)
            return
        }

        onCapture?(shortcut)
    }
}

@MainActor
final class SettingsWindowController {
    private weak var coordinator: HengeCoordinator?
    private var window: NSWindow?
    private let activateApplication: @MainActor () -> Void
    private let presentWindow: @MainActor (NSWindow) -> Void

    init(
        coordinator: HengeCoordinator? = nil,
        activateApplication: (@MainActor () -> Void)? = nil,
        presentWindow: (@MainActor (NSWindow) -> Void)? = nil
    ) {
        self.coordinator = coordinator
        self.activateApplication = activateApplication ?? {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        self.presentWindow = presentWindow ?? { window in
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    func bind(coordinator: HengeCoordinator) {
        self.coordinator = coordinator
    }

    @discardableResult
    func showWindow() -> NSWindow? {
        guard let coordinator else {
            return nil
        }

        let targetWindow: NSWindow
        if let existingWindow = window {
            targetWindow = existingWindow
        } else {
            let hostingController = NSHostingController(
                rootView: SettingsView().environmentObject(coordinator)
            )
            let createdWindow = NSWindow(contentViewController: hostingController)
            createdWindow.title = L10n.string("settings.window.title", defaultValue: "Henge Settings")
            createdWindow.styleMask = [.titled, .closable, .miniaturizable]
            createdWindow.isReleasedWhenClosed = false
            createdWindow.setContentSize(NSSize(width: 520, height: 460))
            createdWindow.center()
            window = createdWindow
            targetWindow = createdWindow
        }

        bringCurrentWindowToFront()

        if RunLoop.main.currentMode == .eventTracking {
            RunLoop.main.perform(inModes: [.default]) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.bringCurrentWindowToFront()
                }
            }
        }

        return targetWindow
    }

    private func bringCurrentWindowToFront() {
        guard let window else {
            return
        }

        activateApplication()
        presentWindow(window)
    }
}

