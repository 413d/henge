import Foundation
import Testing
@testable import Henge

struct ShortcutTests {
    @Test
    func defaultShortcutUsesOptionX() {
        #expect(Shortcut.defaultFixText.displayString == "⌥X")
        #expect(Shortcut.defaultFixText.keyCode == 7)
    }

    @Test
    func shortcutDisplayOrdersModifiersConsistently() {
        let shortcut = Shortcut(key: "k", modifiers: [.command, .control, .shift])

        #expect(shortcut.displayString == "⌃⇧⌘K")
    }

    @Test
    func displayStringFormatsSpecialKeysCleanly() {
        #expect(Shortcut(key: "space", modifiers: [.command]).displayString == "⌘Space")
        #expect(Shortcut(key: "Space", modifiers: [.option]).displayString == "⌥Space")
        #expect(Shortcut(key: "return", modifiers: [.command]).displayString == "⌘↩")
        #expect(Shortcut(key: "Enter", modifiers: [.command]).displayString == "⌘↩")
        #expect(Shortcut(key: "↩", modifiers: [.command]).displayString == "⌘↩")
        #expect(Shortcut(key: "f1", modifiers: [.option]).displayString == "⌥F1")
        #expect(Shortcut(key: "F12", modifiers: [.control]).displayString == "⌃F12")
        #expect(Shortcut(key: "←", modifiers: [.option]).displayString == "⌥←")
        #expect(Shortcut(key: "→", modifiers: [.option]).displayString == "⌥→")
        #expect(Shortcut(key: "↑", modifiers: [.option]).displayString == "⌥↑")
        #expect(Shortcut(key: "↓", modifiers: [.option]).displayString == "⌥↓")
    }

    @Test
    func decodesLegacyJSONWithoutKeyCode() throws {
        let scalarModifiersJSON = Data(#"{"key":"X","modifiers":2}"#.utf8)
        let scalarDecoded = try JSONDecoder().decode(Shortcut.self, from: scalarModifiersJSON)
        #expect(scalarDecoded.key == "X")
        #expect(scalarDecoded.modifiers == [.option])
        #expect(scalarDecoded.keyCode == nil)

        let objectModifiersJSON = Data(#"{"key":"X","modifiers":{"rawValue":2}}"#.utf8)
        let objectDecoded = try JSONDecoder().decode(Shortcut.self, from: objectModifiersJSON)
        #expect(objectDecoded.key == "X")
        #expect(objectDecoded.modifiers == [.option])
        #expect(objectDecoded.keyCode == nil)
    }

    @Test
    func encodesAndDecodesKeyCodeWhenPresent() throws {
        let shortcut = Shortcut(key: "X", modifiers: [.option], keyCode: 7)
        let data = try JSONEncoder().encode(shortcut)
        let decoded = try JSONDecoder().decode(Shortcut.self, from: data)

        #expect(decoded == shortcut)
        #expect(decoded.keyCode == 7)
    }

    @Test
    func equatableComparesKeyCode() {
        let withSeven = Shortcut(key: "X", modifiers: [.option], keyCode: 7)
        let withEight = Shortcut(key: "X", modifiers: [.option], keyCode: 8)
        let withoutKeyCode = Shortcut(key: "X", modifiers: [.option])

        #expect(withSeven != withEight)
        #expect(withSeven != withoutKeyCode)
    }

    @Test
    func shortcutCaptureEvaluatorHandlesEscapeMissingModifiersUnsupportedAndValidKeys() {
        #expect(
            ShortcutCaptureEvaluator.evaluate(
                keyCode: 53,
                modifiers: [],
                charactersIgnoringModifiers: "\u{1B}",
                asciiLabel: { _ in nil }
            ) == .cancelled
        )
        #expect(
            ShortcutCaptureEvaluator.evaluate(
                keyCode: 53,
                modifiers: [.option],
                charactersIgnoringModifiers: "\u{1B}",
                asciiLabel: { _ in nil }
            ) == .cancelled
        )
        #expect(
            ShortcutCaptureEvaluator.evaluate(
                keyCode: 7,
                modifiers: [],
                charactersIgnoringModifiers: "x",
                asciiLabel: { _ in "X" }
            ) == .missingModifiers
        )
        #expect(
            ShortcutCaptureEvaluator.evaluate(
                keyCode: 51,
                modifiers: [.option],
                charactersIgnoringModifiers: "\u{7F}",
                asciiLabel: { _ in nil }
            ) == .unsupportedKey("⌥⌫")
        )
        #expect(
            ShortcutCaptureEvaluator.evaluate(
                keyCode: 48,
                modifiers: [.option],
                charactersIgnoringModifiers: "\t",
                asciiLabel: { _ in nil }
            ) == .unsupportedKey("⌥⇥")
        )
        #expect(
            ShortcutCaptureEvaluator.evaluate(
                keyCode: 7,
                modifiers: [.option],
                charactersIgnoringModifiers: "ч",
                asciiLabel: { _ in "X" }
            ) == .captured(Shortcut(key: "X", modifiers: [.option], keyCode: 7))
        )
    }
}
