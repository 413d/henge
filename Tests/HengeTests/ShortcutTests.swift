import Testing
@testable import Henge

struct ShortcutTests {
    @Test
    func defaultShortcutUsesOptionX() {
        #expect(Shortcut.defaultFixText.displayString == "⌥X")
    }

    @Test
    func shortcutDisplayOrdersModifiersConsistently() {
        let shortcut = Shortcut(key: "k", modifiers: [.command, .control, .shift])

        #expect(shortcut.displayString == "⌃⇧⌘K")
    }
}
