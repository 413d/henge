import Carbon
import Testing
@testable import Henge

struct CarbonHotkeyTests {
    @Test
    func acceptsKeysBackedByCarbonKeyCodes() {
        #expect(CarbonHotkey.isSupported(key: Shortcut.defaultFixText.key))
        #expect(CarbonHotkey.isSupported(key: "k"))
        #expect(CarbonHotkey.isSupported(key: "7"))
        #expect(CarbonHotkey.isSupported(key: "/"))
        #expect(CarbonHotkey.isSupported(key: "Space"))
        #expect(CarbonHotkey.isSupported(key: "Return"))
        #expect(CarbonHotkey.isSupported(key: "Enter"))
        #expect(CarbonHotkey.isSupported(key: "↩"))
        #expect(CarbonHotkey.isSupported(key: "←"))
        #expect(CarbonHotkey.isSupported(key: "→"))
        #expect(CarbonHotkey.isSupported(key: "↑"))
        #expect(CarbonHotkey.isSupported(key: "↓"))

        for index in 1...12 {
            #expect(CarbonHotkey.isSupported(key: "F\(index)"))
        }
    }

    @Test
    func rejectsKeysWithoutCarbonKeyCode() {
        #expect(CarbonHotkey.isSupported(key: "😀") == false)
        #expect(CarbonHotkey.isSupported(key: "⌥X") == false)
        #expect(CarbonHotkey.isSupported(key: "F13") == false)
        #expect(CarbonHotkey.isSupported(key: "") == false)
        #expect(CarbonHotkey.isSupported(keyCode: UInt32(kVK_F13)) == false)
        #expect(CarbonHotkey.isSupported(keyCode: UInt32(kVK_Escape)) == false)
        #expect(CarbonHotkey.isSupported(keyCode: 999) == false)
    }

    @Test
    func layoutIndependentKeyCodeTakesPrecedenceDuringRegistration() throws {
        let russianLabelWithAnsiXKeyCode = Shortcut(key: "Ч", modifiers: [.option], keyCode: UInt32(kVK_ANSI_X))
        #expect(CarbonHotkey.isSupported(shortcut: russianLabelWithAnsiXKeyCode))

        let hotkey = try CarbonHotkey(shortcut: russianLabelWithAnsiXKeyCode)
        #expect(hotkey.keyCode == UInt32(kVK_ANSI_X))

        let russianLabelWithoutKeyCode = Shortcut(key: "Ч", modifiers: [.option])
        #expect(CarbonHotkey.isSupported(shortcut: russianLabelWithoutKeyCode) == false)
        #expect(throws: HotkeyRegistrationError.self) {
            _ = try CarbonHotkey(shortcut: russianLabelWithoutKeyCode)
        }

        let invalidExplicitKeyCode = Shortcut(key: "X", modifiers: [.option], keyCode: 999)
        #expect(CarbonHotkey.isSupported(shortcut: invalidExplicitKeyCode) == false)
        #expect(throws: HotkeyRegistrationError.self) {
            _ = try CarbonHotkey(shortcut: invalidExplicitKeyCode)
        }
    }

    @Test
    func specialKeysResolveExpectedCarbonKeyCodes() throws {
        let cases: [(String, Int)] = [
            ("F1", kVK_F1),
            ("F2", kVK_F2),
            ("F3", kVK_F3),
            ("F4", kVK_F4),
            ("F5", kVK_F5),
            ("F6", kVK_F6),
            ("F7", kVK_F7),
            ("F8", kVK_F8),
            ("F9", kVK_F9),
            ("F10", kVK_F10),
            ("F11", kVK_F11),
            ("F12", kVK_F12),
            ("←", kVK_LeftArrow),
            ("→", kVK_RightArrow),
            ("↑", kVK_UpArrow),
            ("↓", kVK_DownArrow),
            ("Space", kVK_Space),
            ("Return", kVK_Return),
            ("Enter", kVK_Return),
            ("↩", kVK_Return),
        ]

        for (key, expectedCode) in cases {
            let hotkey = try CarbonHotkey(shortcut: Shortcut(key: key, modifiers: [.command]))
            #expect(hotkey.keyCode == UInt32(expectedCode))
        }
    }

    @Test
    func displayKeyMapsSpecialAndAnsiKeyCodes() {
        #expect(CarbonHotkey.displayKey(forKeyCode: UInt32(kVK_ANSI_X)) == "X")
        #expect(CarbonHotkey.displayKey(forKeyCode: UInt32(kVK_Space)) == "Space")
        #expect(CarbonHotkey.displayKey(forKeyCode: UInt32(kVK_Return)) == "↩")
        #expect(CarbonHotkey.displayKey(forKeyCode: UInt32(kVK_ANSI_KeypadEnter)) == "↩")
        #expect(CarbonHotkey.displayKey(forKeyCode: UInt32(kVK_LeftArrow)) == "←")
        #expect(CarbonHotkey.displayKey(forKeyCode: UInt32(kVK_RightArrow)) == "→")
        #expect(CarbonHotkey.displayKey(forKeyCode: UInt32(kVK_UpArrow)) == "↑")
        #expect(CarbonHotkey.displayKey(forKeyCode: UInt32(kVK_DownArrow)) == "↓")
        #expect(CarbonHotkey.displayKey(forKeyCode: UInt32(kVK_F1)) == "F1")
        #expect(CarbonHotkey.displayKey(forKeyCode: UInt32(kVK_F12)) == "F12")
        #expect(CarbonHotkey.displayKey(forKeyCode: UInt32(kVK_F13)) == nil)
        #expect(CarbonHotkey.displayKey(forKeyCode: UInt32(kVK_Escape)) == nil)
    }

    @Test
    func displayKeyUsesInjectedAsciiLabelAndFallsBackToAnsi() {
        var calledWith: [UInt16] = []
        let resolved = CarbonHotkey.displayKey(forKeyCode: UInt32(kVK_ANSI_Z)) { code in
            calledWith.append(code)
            return "Y"
        }
        #expect(resolved == "Y")
        #expect(calledWith == [UInt16(kVK_ANSI_Z)])

        let fallback = CarbonHotkey.displayKey(forKeyCode: UInt32(kVK_ANSI_X)) { _ in nil }
        #expect(fallback == "X")

        var specialCalled = false
        let special = CarbonHotkey.displayKey(forKeyCode: UInt32(kVK_Space)) { _ in
            specialCalled = true
            return "SPACE"
        }
        #expect(special == "Space")
        #expect(specialCalled == false)
    }
}
