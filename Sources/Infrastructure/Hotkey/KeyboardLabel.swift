import Carbon
import Foundation

struct CarbonHotkey {
    let keyCode: UInt32
    let modifiers: UInt32

    private static let specialKeyLabels: [UInt32: String] = [
        UInt32(kVK_Return): "↩",
        UInt32(kVK_ANSI_KeypadEnter): "↩",
        UInt32(kVK_Space): "Space",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_F1): "F1",
        UInt32(kVK_F2): "F2",
        UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5",
        UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7",
        UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10",
        UInt32(kVK_F11): "F11",
        UInt32(kVK_F12): "F12",
    ]

    private static let ansiKeyLabels: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A",
        UInt32(kVK_ANSI_B): "B",
        UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E",
        UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G",
        UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J",
        UInt32(kVK_ANSI_K): "K",
        UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M",
        UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q",
        UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S",
        UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_W): "W",
        UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y",
        UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0",
        UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4",
        UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6",
        UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_ANSI_Minus): "-",
        UInt32(kVK_ANSI_Equal): "=",
        UInt32(kVK_ANSI_LeftBracket): "[",
        UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_Semicolon): ";",
        UInt32(kVK_ANSI_Quote): "'",
        UInt32(kVK_ANSI_Comma): ",",
        UInt32(kVK_ANSI_Period): ".",
        UInt32(kVK_ANSI_Slash): "/",
        UInt32(kVK_ANSI_Grave): "`",
        UInt32(kVK_ANSI_Backslash): "\\",
    ]

    /// Carbon HIToolbox key codes are a platform concern, so support for a
    /// shortcut key is decided here rather than in the domain model.
    static func isSupported(key: String) -> Bool {
        keyCode(for: key) != nil
    }

    static func isSupported(keyCode: UInt32) -> Bool {
        specialKeyLabels[keyCode] != nil || ansiKeyLabels[keyCode] != nil
    }

    static func isSupported(shortcut: Shortcut) -> Bool {
        if let explicitKeyCode = shortcut.keyCode {
            return isSupported(keyCode: explicitKeyCode)
        }
        return keyCode(for: shortcut.key) != nil
    }

    static func displayKey(
        forKeyCode keyCode: UInt32,
        asciiLabel: ((UInt16) -> String?)? = nil
    ) -> String? {
        if let special = specialKeyLabels[keyCode] {
            return special
        }

        guard let fallback = ansiKeyLabels[keyCode] else {
            return nil
        }

        return asciiLabel?(UInt16(keyCode)) ?? fallback
    }

    init(shortcut: Shortcut) throws {
        let resolvedKeyCode: UInt32
        if let explicitKeyCode = shortcut.keyCode {
            guard Self.isSupported(keyCode: explicitKeyCode) else {
                throw HotkeyRegistrationError.unsupportedShortcut(shortcut.key)
            }
            resolvedKeyCode = explicitKeyCode
        } else if let mappedKeyCode = Self.keyCode(for: shortcut.key) {
            resolvedKeyCode = mappedKeyCode
        } else {
            throw HotkeyRegistrationError.unsupportedShortcut(shortcut.key)
        }

        self.keyCode = resolvedKeyCode
        modifiers = Self.modifiers(for: shortcut.modifiers)
    }

    static func systemASCIICapableLabel(forKeyCode keyCode: UInt16) -> String? {
        guard Thread.isMainThread else {
            return nil
        }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let dataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let cfData = Unmanaged<CFData>.fromOpaque(dataPtr).takeUnretainedValue()
        guard let layoutBytes = CFDataGetBytePtr(cfData) else {
            return nil
        }
        let keyboardLayout = UnsafeRawPointer(layoutBytes).bindMemory(to: UCKeyboardLayout.self, capacity: 1)
        var deadKeyState: UInt32 = 0
        let maxLength = 4
        var actualLength = 0
        var unicodeString = [UniChar](repeating: 0, count: maxLength)

        let status = UCKeyTranslate(
            keyboardLayout,
            keyCode,
            UInt16(kUCKeyActionDown),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            maxLength,
            &actualLength,
            &unicodeString
        )

        guard status == noErr, actualLength > 0 else {
            return nil
        }

        let translated = String(utf16CodeUnits: unicodeString, count: actualLength)
        guard translated.count == 1,
              let scalar = translated.unicodeScalars.first,
              scalar.value >= 0x21 && scalar.value <= 0x7E else {
            return nil
        }

        return translated.uppercased()
    }

    private static func modifiers(for modifiers: Shortcut.Modifiers) -> UInt32 {
        var carbonModifiers: UInt32 = 0

        if modifiers.contains(.command) {
            carbonModifiers |= UInt32(cmdKey)
        }

        if modifiers.contains(.option) {
            carbonModifiers |= UInt32(optionKey)
        }

        if modifiers.contains(.control) {
            carbonModifiers |= UInt32(controlKey)
        }

        if modifiers.contains(.shift) {
            carbonModifiers |= UInt32(shiftKey)
        }

        return carbonModifiers
    }

    private static func keyCode(for key: String) -> UInt32? {
        if key.count == 1 {
            switch key.uppercased() {
            case "A": return UInt32(kVK_ANSI_A)
            case "B": return UInt32(kVK_ANSI_B)
            case "C": return UInt32(kVK_ANSI_C)
            case "D": return UInt32(kVK_ANSI_D)
            case "E": return UInt32(kVK_ANSI_E)
            case "F": return UInt32(kVK_ANSI_F)
            case "G": return UInt32(kVK_ANSI_G)
            case "H": return UInt32(kVK_ANSI_H)
            case "I": return UInt32(kVK_ANSI_I)
            case "J": return UInt32(kVK_ANSI_J)
            case "K": return UInt32(kVK_ANSI_K)
            case "L": return UInt32(kVK_ANSI_L)
            case "M": return UInt32(kVK_ANSI_M)
            case "N": return UInt32(kVK_ANSI_N)
            case "O": return UInt32(kVK_ANSI_O)
            case "P": return UInt32(kVK_ANSI_P)
            case "Q": return UInt32(kVK_ANSI_Q)
            case "R": return UInt32(kVK_ANSI_R)
            case "S": return UInt32(kVK_ANSI_S)
            case "T": return UInt32(kVK_ANSI_T)
            case "U": return UInt32(kVK_ANSI_U)
            case "V": return UInt32(kVK_ANSI_V)
            case "W": return UInt32(kVK_ANSI_W)
            case "X": return UInt32(kVK_ANSI_X)
            case "Y": return UInt32(kVK_ANSI_Y)
            case "Z": return UInt32(kVK_ANSI_Z)
            case "0": return UInt32(kVK_ANSI_0)
            case "1": return UInt32(kVK_ANSI_1)
            case "2": return UInt32(kVK_ANSI_2)
            case "3": return UInt32(kVK_ANSI_3)
            case "4": return UInt32(kVK_ANSI_4)
            case "5": return UInt32(kVK_ANSI_5)
            case "6": return UInt32(kVK_ANSI_6)
            case "7": return UInt32(kVK_ANSI_7)
            case "8": return UInt32(kVK_ANSI_8)
            case "9": return UInt32(kVK_ANSI_9)
            case "-": return UInt32(kVK_ANSI_Minus)
            case "=": return UInt32(kVK_ANSI_Equal)
            case "[": return UInt32(kVK_ANSI_LeftBracket)
            case "]": return UInt32(kVK_ANSI_RightBracket)
            case ";": return UInt32(kVK_ANSI_Semicolon)
            case "'": return UInt32(kVK_ANSI_Quote)
            case ",": return UInt32(kVK_ANSI_Comma)
            case ".": return UInt32(kVK_ANSI_Period)
            case "/": return UInt32(kVK_ANSI_Slash)
            case "`": return UInt32(kVK_ANSI_Grave)
            case "\\": return UInt32(kVK_ANSI_Backslash)
            case " ": return UInt32(kVK_Space)
            case "↩": return UInt32(kVK_Return)
            case "←": return UInt32(kVK_LeftArrow)
            case "→": return UInt32(kVK_RightArrow)
            case "↑": return UInt32(kVK_UpArrow)
            case "↓": return UInt32(kVK_DownArrow)
            default: return nil
            }
        }

        switch key.lowercased() {
        case "space": return UInt32(kVK_Space)
        case "return", "enter": return UInt32(kVK_Return)
        case "left", "leftarrow": return UInt32(kVK_LeftArrow)
        case "right", "rightarrow": return UInt32(kVK_RightArrow)
        case "up", "uparrow": return UInt32(kVK_UpArrow)
        case "down", "downarrow": return UInt32(kVK_DownArrow)
        case "f1": return UInt32(kVK_F1)
        case "f2": return UInt32(kVK_F2)
        case "f3": return UInt32(kVK_F3)
        case "f4": return UInt32(kVK_F4)
        case "f5": return UInt32(kVK_F5)
        case "f6": return UInt32(kVK_F6)
        case "f7": return UInt32(kVK_F7)
        case "f8": return UInt32(kVK_F8)
        case "f9": return UInt32(kVK_F9)
        case "f10": return UInt32(kVK_F10)
        case "f11": return UInt32(kVK_F11)
        case "f12": return UInt32(kVK_F12)
        default: return nil
        }
    }
}
