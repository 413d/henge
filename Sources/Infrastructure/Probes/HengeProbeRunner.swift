import Foundation

/// Command-line probe harness used to validate the native macOS API spikes
/// in an interactive GUI session.
///
/// The probes are intentionally read-only with respect to user data: the
/// clipboard probe restores the original pasteboard contents, and the
/// Accessibility probes never print selection or field text.
enum HengeProbeRunner {
    enum ProbeCommand: String, Equatable, CaseIterable {
        case layout
        case clipboard
        case ax
        case hotkey
        case all
        case help

        init(argument: String) {
            self = ProbeCommand(rawValue: argument.lowercased()) ?? .help
        }
    }

    /// Extracts the probe command from a full process argument list.
    ///
    /// - Parameter arguments: The process arguments, typically `CommandLine.arguments`.
    /// - Returns: The requested probe command, or `.help` when none was supplied.
    static func probeCommand(from arguments: [String]) -> ProbeCommand {
        guard let flagIndex = arguments.firstIndex(of: "--probe") else {
            return .help
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard valueIndex < arguments.endIndex else {
            return .help
        }

        return ProbeCommand(argument: arguments[valueIndex])
    }

    /// Runs the requested probe and returns a process exit code.
    static func run(arguments: [String]) -> Int32 {
        run(command: probeCommand(from: arguments))
    }

    static func run(command: ProbeCommand) -> Int32 {
        switch command {
        case .layout:
            print(runLayoutProbe(mapper: NativeKeyboardLayoutMapper()))
        case .clipboard:
            print(runClipboardProbe(manager: AppKitClipboardManager()))
        case .ax:
            print(runAccessibilityProbe(runtime: LiveAppRuntime()))
        case .hotkey:
            print(runHotkeyProbe(runtime: LiveAppRuntime()))
        case .all:
            print(runLayoutProbe(mapper: NativeKeyboardLayoutMapper()))
            print("")
            print(runClipboardProbe(manager: AppKitClipboardManager()))
            print("")
            print(runAccessibilityProbe(runtime: LiveAppRuntime()))
        case .help:
            print(helpText())
        }

        return 0
    }

    // MARK: - Layout probe

    static func runLayoutProbe(mapper: LayoutMapping) -> String {
        let samples: [(label: String, text: String)] = [
            ("RU -> EN", "привет"),
            ("EN -> RU", "ghbdtn"),
            ("RU -> EN", "руддщ цщкдв"),
            ("EN -> RU", "hello world"),
            ("EN -> RU", "Ghbdtn, Rfr Ltkf?"),
            ("RU -> EN", "Руддщ, Цщкдв!")
        ]

        var lines: [String] = []
        lines.append("Henge layout probe")
        lines.append("==================")

        for sample in samples {
            let source: Layout = sample.label.hasPrefix("RU") ? .russian : .english
            let target: Layout = source == .russian ? .english : .russian
            let converted = mapper.map(text: sample.text, from: source, to: target)
            lines.append("[\(sample.label)] \(sample.text) -> \(converted)")
        }

        lines.append("")
        lines.append("Case and punctuation preservation:")
        let caseSample = mapper.map(text: "Ghbdtn!", from: .english, to: .russian)
        lines.append("Ghbdtn! -> \(caseSample)")

        return lines.joined(separator: "\n")
    }

    // MARK: - Clipboard probe

    static func runClipboardProbe(manager: ClipboardManaging) -> String {
        var lines: [String] = []
        lines.append("Henge clipboard probe")
        lines.append("=====================")

        let original = manager.snapshot()
        lines.append("Captured \(original.items.count) item(s), changeCount \(original.changeCount).")

        for (index, item) in original.items.enumerated() {
            let types = item.representations.keys.sorted().joined(separator: ", ")
            lines.append("  item[\(index)] types: [\(types)]")
        }

        guard original.isRestorable else {
            lines.append("Clipboard snapshot contains oversized representations and is not restorable; skipping test marker write to protect user data.")
            return lines.joined(separator: "\n")
        }

        let marker = ClipboardSnapshot(
            changeCount: original.changeCount + 1,
            items: [PasteboardItemSnapshot(representations: ["public.utf8-plain-text": Data("henge-probe-marker".utf8)])]
        )
        _ = manager.restore(marker)
        lines.append("Wrote probe marker over the clipboard.")

        let restoreSucceeded = manager.restore(original)
        lines.append(restoreSucceeded ? "Clipboard snapshot restored." : "Clipboard restore FAILED.")
        lines.append("Restored changeCount \(manager.snapshot().changeCount).")

        return lines.joined(separator: "\n")
    }

    // MARK: - Accessibility probe

    static func runAccessibilityProbe(runtime: AppRuntime) -> String {
        var lines: [String] = []
        lines.append("Henge Accessibility probe")
        lines.append("=========================")
        lines.append("AXIsProcessTrusted: \(runtime.hasAccessibilityPermission)")

        guard runtime.hasAccessibilityPermission else {
            lines.append("Accessibility permission is required for the remaining checks.")
            lines.append("Grant it in System Settings › Privacy & Security › Accessibility, then re-run.")
            return lines.joined(separator: "\n")
        }

        switch runtime.inspectFocusedElement() {
        case let .unavailable(reason):
            lines.append("Focused element: unavailable — \(reason.description)")
        case let .available(snapshot) where snapshot.isSecure:
            // Safety invariant: a secure field is a complete no-op.
            // Report only the non-sensitive role markers and stop; never touch the selection.
            lines.append("Focused element role: \(snapshot.role ?? "<none>")")
            lines.append("Focused element subrole: \(snapshot.subrole ?? "<none>")")
            lines.append("Secure field detected: true")
            lines.append("Selection: skipped (secure field).")
        case let .available(snapshot):
            lines.append("Focused element role: \(snapshot.role ?? "<none>")")
            lines.append("Focused element subrole: \(snapshot.subrole ?? "<none>")")
            lines.append("Secure field detected: false")

            switch runtime.inspectSelection() {
            case let .available(selection):
                lines.append("Selection: \(selection.text.count) chars at [\(selection.range.location), \(selection.range.length)]")
            case let .unavailable(reason):
                lines.append("Selection: unavailable — \(reason.description)")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Hotkey probe

    /// Mutable flag shared between the Carbon hotkey callback and the run loop below.
    private final class HotkeyFlag {
        var fired = false
    }

    /// Registers `⌥X` and pumps the main run loop for up to 10 seconds.
    ///
    /// Carbon delivers `kEventHotKeyPressed` on the main run loop, so the probe must
    /// run the loop rather than block the main thread on a semaphore.
    static func runHotkeyProbe(runtime: AppRuntime, timeout: TimeInterval = 10) -> String {
        var lines: [String] = []
        lines.append("Henge hotkey probe")
        lines.append("==================")
        lines.append("Registering ⌥X for \(Int(timeout)) seconds. Press ⌥X to confirm the global hotkey fires.")

        let flag = HotkeyFlag()

        do {
            try runtime.registerFixTextHotkey(Shortcut(key: "x", modifiers: [.option])) {
                flag.fired = true
            }
        } catch {
            lines.append("Hotkey registration FAILED: \(error.localizedDescription)")
            return lines.joined(separator: "\n")
        }

        let deadline = Date().addingTimeInterval(timeout)
        while !flag.fired && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        runtime.unregisterFixTextHotkey()

        lines.append(flag.fired ? "Hotkey event received." : "No hotkey event received within \(Int(timeout)) seconds.")

        return lines.joined(separator: "\n")
    }

    // MARK: - Help

    static func helpText() -> String {
        """
        Henge native API probe harness

        Usage:
          swift run Henge --probe layout      Validate RU <-> EN layout mapping
          swift run Henge --probe clipboard   Validate full-fidelity pasteboard preservation
          swift run Henge --probe ax          Inspect Accessibility focused element and selection
          swift run Henge --probe hotkey      Register ⌥X and wait up to 10s for a key event
          swift run Henge --probe all         Run layout, clipboard, and ax probes
          swift run Henge --probe help        Show this message

        Notes:
          - Run from a GUI session with Accessibility permission for full results.
          - The clipboard probe restores the original pasteboard contents.
          - No probe logs user text, passwords, or clipboard contents.
        """
    }
}
