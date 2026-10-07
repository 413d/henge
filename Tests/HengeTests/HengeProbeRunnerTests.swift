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
    func helpProbeDescribesUsage() {
        let output = HengeProbeRunner.helpText()
        #expect(output.contains("--probe layout"))
        #expect(output.contains("--probe clipboard"))
        #expect(output.contains("--probe ax"))
        #expect(output.contains("--probe hotkey"))
        #expect(output.contains("--probe all"))
    }
}
