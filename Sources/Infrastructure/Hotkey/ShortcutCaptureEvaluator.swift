import Foundation

enum ShortcutCaptureResult: Equatable {
    case captured(Shortcut)
    case cancelled
    case missingModifiers
    case unsupportedKey(String)
}

enum ShortcutCaptureEvaluator {
    static func evaluate(
        keyCode: UInt16,
        modifiers: Shortcut.Modifiers,
        charactersIgnoringModifiers: String?,
        asciiLabel: @escaping (UInt16) -> String? = CarbonHotkey.systemASCIICapableLabel
    ) -> ShortcutCaptureResult {
        if keyCode == 53 {
            return .cancelled
        }

        if modifiers.isEmpty {
            return .missingModifiers
        }

        let carbonKeyCode = UInt32(keyCode)
        if let key = CarbonHotkey.displayKey(forKeyCode: carbonKeyCode, asciiLabel: asciiLabel) {
            let shortcut = Shortcut(key: key, modifiers: modifiers, keyCode: carbonKeyCode)
            if CarbonHotkey.isSupported(shortcut: shortcut) {
                return .captured(shortcut)
            }
            return .unsupportedKey(Shortcut(key: key, modifiers: modifiers).displayString)
        }

        let rawKey = unsupportedKeyLabel(
            forKeyCode: keyCode,
            charactersIgnoringModifiers: charactersIgnoringModifiers
        )
        return .unsupportedKey(Shortcut(key: rawKey, modifiers: modifiers).displayString)
    }

    private static func unsupportedKeyLabel(
        forKeyCode keyCode: UInt16,
        charactersIgnoringModifiers: String?
    ) -> String {
        switch keyCode {
        case 48:
            return "⇥"
        case 51:
            return "⌫"
        case 117:
            return "⌦"
        default:
            if let chars = charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines),
               !chars.isEmpty,
               !chars.unicodeScalars.contains(where: {
                   CharacterSet.controlCharacters.contains($0) || $0.properties.generalCategory == .privateUse
               }) {
                return chars.uppercased()
            }
            return "#\(keyCode)"
        }
    }
}
