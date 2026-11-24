import Testing
import Foundation
@testable import Henge

struct HengeProbeRunnerTests {
    @Test
    func parsesProbeCommandsCorrectly() {
        #expect(HengeProbeRunner.ProbeCommand(argument: "layout") == .layout)
        #expect(HengeProbeRunner.ProbeCommand(argument: "clipboard") == .clipboard)
        #expect(HengeProbeRunner.ProbeCommand(argument: "ax") == .ax)
        #expect(HengeProbeRunner.ProbeCommand(argument: "hotkey") == .hotkey)
        #expect(HengeProbeRunner.ProbeCommand(argument: "all") == .all)
        #expect(HengeProbeRunner.ProbeCommand(argument: "unknown") == .help)
    }

    @Test
    func parsesProbeArgumentsWithFlagPrefix() {
        let command = HengeProbeRunner.probeCommand(from: ["Henge", "--probe", "layout"])
        #expect(command == .layout)
    }

    @Test
    func defaultsToHelpWhenProbeArgumentMissing() {
        let command = HengeProbeRunner.probeCommand(from: ["Henge", "--probe"])
        #expect(command == .help)
    }

    @Test
    func layoutProbeTranslatesRussianToEnglish() {
        let mapper = NativeKeyboardLayoutMapper()
        let output = HengeProbeRunner.runLayoutProbe(mapper: mapper)
        #expect(output.contains("ghbdtn"))
        #expect(output.contains("привет"))
    }

    @Test
    func layoutProbeReportsAllSamples() {
        let mapper = NativeKeyboardLayoutMapper()
        let output = HengeProbeRunner.runLayoutProbe(mapper: mapper)
        #expect(output.contains("RU -> EN"))
        #expect(output.contains("EN -> RU"))
    }

    @Test
    func clipboardProbeRestoresOriginalContents() {
        let manager = MockClipboardManager()
        manager.setMockItem(["public.utf8-plain-text": "original".data(using: .utf8)!])

        let output = HengeProbeRunner.runClipboardProbe(manager: manager)

        #expect(output.contains("restored"))
        #expect(manager.snapshot().items.first?.representations["public.utf8-plain-text"] == "original".data(using: .utf8)!)
    }

    @Test
    func clipboardProbeDoesNotWriteMarkerWhenSnapshotIsNotRestorable() {
        let nonRestorable = ClipboardSnapshot(
            changeCount: 3,
            items: [PasteboardItemSnapshot(representations: ["public.png": Data([0x01, 0x02])])],
            oversizedTypes: ["public.png"]
        )
        let manager = SpyProbeClipboardManager(snapshotToReturn: nonRestorable)

        let output = HengeProbeRunner.runClipboardProbe(manager: manager)

        #expect(output.contains("not restorable"))
        #expect(output.contains("Clipboard snapshot contains oversized representations and is not restorable; skipping test marker write to protect user data."))
        #expect(manager.restoredSnapshots.isEmpty)
    }

    @Test
    func helpProbeDescribesUsage() {
        let output = HengeProbeRunner.helpText()
        #expect(output.contains("--probe layout"))
        #expect(output.contains("--probe clipboard"))
        #expect(output.contains("--probe ax"))
        #expect(output.contains("--probe hotkey"))
        #expect(output.contains("--probe all"))
    }

    @Test
    func hotkeyProbeReportsReceivedEvent() {
        let runtime = ProbeStubRuntime(fireOnRegister: true)
        let output = HengeProbeRunner.runHotkeyProbe(runtime: runtime, timeout: 2)
        #expect(output.contains("Hotkey event received."))
        #expect(runtime.unregisterCount == 1)
    }

    @Test
    func hotkeyProbeReportsTimeoutAndUnregisters() {
        let runtime = ProbeStubRuntime(fireOnRegister: false)
        let output = HengeProbeRunner.runHotkeyProbe(runtime: runtime, timeout: 0.2)
        #expect(output.contains("No hotkey event received"))
        #expect(runtime.unregisterCount == 1)
    }

    @Test
    func hotkeyProbeReportsRegistrationFailure() {
        let runtime = ProbeStubRuntime(fireOnRegister: false, registrationError: ProbeRegistrationError.denied)
        let output = HengeProbeRunner.runHotkeyProbe(runtime: runtime, timeout: 0.2)
        #expect(output.contains("Hotkey registration FAILED"))
        #expect(runtime.unregisterCount == 0)
    }

    @Test
    func accessibilityProbeReportsMissingPermission() {
        let runtime = ProbeStubRuntime(hasAccessibilityPermission: false)
        let output = HengeProbeRunner.runAccessibilityProbe(runtime: runtime)
        #expect(output.contains("AXIsProcessTrusted: false"))
        #expect(output.contains("Accessibility permission is required"))
    }

    @Test
    func accessibilityProbeReportsRoleAndSecureFlagWithoutText() {
        let runtime = ProbeStubRuntime(
            hasAccessibilityPermission: true,
            focusedElementProbe: .available(
                FocusedElementSnapshot(role: "AXSecureTextField", subrole: nil, isSecure: true)
            )
        )
        let output = HengeProbeRunner.runAccessibilityProbe(runtime: runtime)
        #expect(output.contains("Secure field detected: true"))
        #expect(output.contains("Selection: skipped (secure field)."))
        #expect(runtime.selectionInspectionCount == 0)
    }

    @Test
    func accessibilityProbeReadsSelectionForNonSecureField() {
        let runtime = ProbeStubRuntime(
            hasAccessibilityPermission: true,
            focusedElementProbe: .available(
                FocusedElementSnapshot(role: "AXTextField", subrole: nil, isSecure: false)
            )
        )
        let output = HengeProbeRunner.runAccessibilityProbe(runtime: runtime)
        #expect(output.contains("Secure field detected: false"))
        #expect(output.contains("Selection: unavailable"))
        #expect(runtime.selectionInspectionCount == 1)
    }

    @Test
    func accessibilityProbeSkipsSelectionWhenNoActiveApplication() {
        let runtime = ProbeStubRuntime(
            hasAccessibilityPermission: true,
            focusedElementProbe: .available(
                FocusedElementSnapshot(role: "AXTextField", subrole: nil, isSecure: false)
            )
        )
        runtime.activeApplication = nil
        let output = HengeProbeRunner.runAccessibilityProbe(runtime: runtime)
        #expect(output.contains("Secure field detected: false"))
        #expect(!output.contains("Selection:"))
        #expect(runtime.selectionInspectionCount == 0)
    }
}

private enum ProbeRegistrationError: Error {
    case denied
}

private final class ProbeStubRuntime: AppRuntime {
    var hasAccessibilityPermission: Bool
    var activeApplication: ApplicationIdentity? = ApplicationIdentity(bundleIdentifier: "test.application", displayName: "Test Application")
    let layoutMapper: LayoutMapping = NativeKeyboardLayoutMapper()
    let clipboardManager: ClipboardManaging = MockClipboardManager()

    private let fireOnRegister: Bool
    private let registrationError: Error?
    private let focusedElementProbe: FocusedElementProbe
    private(set) var unregisterCount = 0
    private(set) var selectionInspectionCount = 0

    init(
        fireOnRegister: Bool = false,
        registrationError: Error? = nil,
        hasAccessibilityPermission: Bool = true,
        focusedElementProbe: FocusedElementProbe = .unavailable(.noFocusedElement)
    ) {
        self.fireOnRegister = fireOnRegister
        self.registrationError = registrationError
        self.hasAccessibilityPermission = hasAccessibilityPermission
        self.focusedElementProbe = focusedElementProbe
    }

    func openAccessibilitySettings() {
    }

    func registerFixTextHotkey(_ shortcut: Shortcut, handler: @escaping () -> Void) throws {
        if let registrationError {
            throw registrationError
        }

        if fireOnRegister {
            handler()
        }
    }

    func unregisterFixTextHotkey() {
        unregisterCount += 1
    }

    func inspectFocusedElement() -> FocusedElementProbe {
        focusedElementProbe
    }

    func inspectTextContext(in application: ApplicationIdentity) -> TextContextProbe {
        selectionInspectionCount += 1
        return .unavailable(.noSelection)
    }

    func replaceText(
        _ target: TextTarget,
        range: SelectionRangeSnapshot,
        context: SelectionSnapshot,
        expectedText: String,
        with text: String
    ) -> SelectionWriteResult {
        .unavailable(.noSelection)
    }
}

private final class SpyProbeClipboardManager: ClipboardManaging, @unchecked Sendable {
    private let snapshotToReturn: ClipboardSnapshot
    private(set) var restoredSnapshots: [ClipboardSnapshot] = []

    init(snapshotToReturn: ClipboardSnapshot) {
        self.snapshotToReturn = snapshotToReturn
    }

    func snapshot() -> ClipboardSnapshot {
        snapshotToReturn
    }

    func restore(_ snapshot: ClipboardSnapshot) -> Bool {
        restoredSnapshots.append(snapshot)
        return true
    }
}
