import Testing
@testable import Henge

struct CarbonHotkeyTests {
    @Test
    func acceptsKeysBackedByCarbonKeyCodes() {
        #expect(CarbonHotkey.isSupported(key: Shortcut.defaultFixText.key))
        #expect(CarbonHotkey.isSupported(key: "k"))
        #expect(CarbonHotkey.isSupported(key: "7"))
        #expect(CarbonHotkey.isSupported(key: "/"))
    }

    @Test
    func rejectsKeysWithoutCarbonKeyCode() {
        #expect(CarbonHotkey.isSupported(key: "😀") == false)
        #expect(CarbonHotkey.isSupported(key: "⌥X") == false)
        #expect(CarbonHotkey.isSupported(key: "F13") == false)
        #expect(CarbonHotkey.isSupported(key: "") == false)
    }
}
