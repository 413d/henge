import Foundation
import Carbon

/// Maps characters and text between keyboard layouts by inspecting macOS
/// system keyboard layout data via Carbon TIS and `UCKeyTranslate`.
///
/// When system layout data is not accessible (such as headless test environments
/// or restricted security contexts), a bundled ANSI fallback table is used.
public final class NativeKeyboardLayoutMapper: LayoutMapping, @unchecked Sendable {
    private let enToRu: [Character: Character]
    private let ruToEn: [Character: Character]

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedSystemTables: (enToRu: [Character: Character], ruToEn: [Character: Character])?

    /// Creates a mapper backed by the bundled ANSI fallback tables without
    /// querying Carbon TIS or `UCKeyTranslate`.
    public static func bundled() -> NativeKeyboardLayoutMapper {
        NativeKeyboardLayoutMapper(layoutData: [:])
    }

    /// Creates a mapper with dynamically resolved system layouts, or with injected
    /// layout data for testing.
    ///
    /// - Parameter layoutData: An optional dictionary mapping `Layout` to raw `Data`
    ///   representing `UCKeyboardLayout`. Pass an empty dictionary `[:]` to trigger
    ///   the bundled ANSI fallback.
    public init(layoutData: [Layout: Data]? = nil) {
        if let customData = layoutData {
            if let usData = customData[.english],
               let ruData = customData[.russian],
               let (enRu, ruEn) = Self.buildTables(usData: usData, ruData: ruData) {
                self.enToRu = enRu
                self.ruToEn = ruEn
                return
            }
            let fallback = Self.fallbackTables()
            self.enToRu = fallback.enToRu
            self.ruToEn = fallback.ruToEn
            return
        }

        let systemTables = Self.getOrBuildSystemTables()
        self.enToRu = systemTables.enToRu
        self.ruToEn = systemTables.ruToEn
    }

    private static func getOrBuildSystemTables() -> (enToRu: [Character: Character], ruToEn: [Character: Character]) {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cachedSystemTables {
            return cached
        }

        let tables: (enToRu: [Character: Character], ruToEn: [Character: Character])
        if let usData = loadSystemLayoutData(sourceID: "com.apple.keylayout.US"),
           let ruData = loadSystemLayoutData(sourceID: "com.apple.keylayout.Russian")
                     ?? loadSystemLayoutData(sourceID: "com.apple.keylayout.RussianWin"),
           let built = buildTables(usData: usData, ruData: ruData) {
            tables = built
        } else {
            tables = fallbackTables()
        }

        cachedSystemTables = tables
        return tables
    }

    // MARK: - LayoutMapping

    public func map(_ character: Character, from source: Layout, to target: Layout) -> Character? {
        if source == target {
            return character
        }
        if character.isNumber || character.isWhitespace {
            return character
        }
        switch (source, target) {
        case (.english, .russian):
            return enToRu[character]
        case (.russian, .english):
            return ruToEn[character]
        default:
            return nil
        }
    }

    public func map(text: String, from source: Layout, to target: Layout) -> String {
        if source == target || text.isEmpty {
            return text
        }
        var result = ""
        result.reserveCapacity(text.count)

        let chars = Array(text)
        for i in 0..<chars.count {
            let ch = chars[i]

            // Always preserve whitespace, digits, and underscores during layout mapping:
            if ch.isNumber || ch == "_" || ch.isWhitespace {
                result.append(ch)
                continue
            }

            // In English -> Russian, characters like `,`, `.`, `;`, `'` could either be
            // punctuation or Russian letters (б, ю, ж, э). If followed by whitespace or at
            // the end of the text, they act as punctuation delimiters.
            if source == .english && target == .russian {
                let nextIsWhitespaceOrEnd = (i + 1 >= chars.count) || chars[i + 1].isWhitespace
                let isDelimiterPunctuation = (ch == "," || ch == "." || ch == "!" || ch == "?" || ch == ":" || ch == ";")
                if isDelimiterPunctuation && nextIsWhitespaceOrEnd {
                    result.append(ch)
                    continue
                }
            }

            // In Russian -> English, standard punctuation delimiters followed by whitespace or end are preserved:
            if source == .russian && target == .english {
                let nextIsWhitespaceOrEnd = (i + 1 >= chars.count) || chars[i + 1].isWhitespace
                let isDelimiterPunctuation = (ch == "," || ch == "!" || ch == "?" || ch == ":" || ch == ";")
                if isDelimiterPunctuation && nextIsWhitespaceOrEnd {
                    result.append(ch)
                    continue
                }
            }

            if let mapped = map(ch, from: source, to: target) {
                result.append(mapped)
            } else {
                result.append(ch)
            }
        }
        return result
    }

    // MARK: - System Layout Loading

    private static func loadSystemLayoutData(sourceID: String) -> Data? {
        let properties = [kTISPropertyInputSourceType: kTISTypeKeyboardLayout] as CFDictionary
        guard let list = TISCreateInputSourceList(properties, true)?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }
        for source in list {
            guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
            let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            if id == sourceID {
                if let dataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
                    let cfData = Unmanaged<CFData>.fromOpaque(dataPtr).takeUnretainedValue()
                    return cfData as Data
                }
            }
        }
        return nil
    }

    // MARK: - Dynamic Table Synthesis via UCKeyTranslate

    private static func buildTables(usData: Data, ruData: Data) -> (enToRu: [Character: Character], ruToEn: [Character: Character])? {
        var enToRu: [Character: Character] = [:]
        var ruToEn: [Character: Character] = [:]

        // Standard ANSI typing keycodes 0...52
        for keyCode: UInt16 in 0...52 {
            // Skip non-typing control keys: return (36), tab (48), delete (51)
            if keyCode == 36 || keyCode == 48 || keyCode == 51 {
                continue
            }
            for modifier in [UInt32(0), UInt32(shiftKey >> 8)] {
                if let enChar = translateKey(data: usData, keyCode: keyCode, modifierState: modifier),
                   let ruChar = translateKey(data: ruData, keyCode: keyCode, modifierState: modifier) {
                    enToRu[enChar] = ruChar
                    ruToEn[ruChar] = enChar
                }
            }
        }

        // Also ensure fallback mappings for keys that might differ between Mac and PC Russian
        let fallback = fallbackTables()
        for (k, v) in fallback.enToRu where enToRu[k] == nil {
            enToRu[k] = v
        }
        for (k, v) in fallback.ruToEn where ruToEn[k] == nil {
            ruToEn[k] = v
        }

        guard !enToRu.isEmpty else { return nil }
        return (enToRu, ruToEn)
    }

    private static func translateKey(data: Data, keyCode: UInt16, modifierState: UInt32) -> Character? {
        let cfData = data as CFData
        guard let layoutHeader = CFDataGetBytePtr(cfData) else { return nil }
        let keyboardLayoutPtr = UnsafeRawPointer(layoutHeader).bindMemory(to: UCKeyboardLayout.self, capacity: 1)
        var deadKeyState: UInt32 = 0
        let maxStringLength = 4
        var actualStringLength = 0
        var unicodeString = [UniChar](repeating: 0, count: maxStringLength)

        let result = UCKeyTranslate(
            keyboardLayoutPtr,
            keyCode,
            UInt16(kUCKeyActionDown),
            modifierState,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            maxStringLength,
            &actualStringLength,
            &unicodeString
        )
        guard result == noErr, actualStringLength > 0 else { return nil }
        let str = String(utf16CodeUnits: unicodeString, count: actualStringLength)
        return str.first
    }

    // MARK: - Bundled Fallback Tables

    private static func fallbackTables() -> (enToRu: [Character: Character], ruToEn: [Character: Character]) {
        let pairs: [(Character, Character)] = [
            ("q", "й"), ("w", "ц"), ("e", "у"), ("r", "к"), ("t", "е"),
            ("y", "н"), ("u", "г"), ("i", "ш"), ("o", "щ"), ("p", "з"),
            ("[", "х"), ("]", "ъ"), ("a", "ф"), ("s", "ы"), ("d", "в"),
            ("f", "а"), ("g", "п"), ("h", "р"), ("j", "о"), ("k", "л"),
            ("l", "д"), (";", "ж"), ("'", "э"), ("z", "я"), ("x", "ч"),
            ("c", "с"), ("v", "м"), ("b", "и"), ("n", "т"), ("m", "ь"),
            (",", "б"), (".", "ю"), ("`", "ё"),

            ("Q", "Й"), ("W", "Ц"), ("E", "У"), ("R", "К"), ("T", "Е"),
            ("Y", "Н"), ("U", "Г"), ("I", "Ш"), ("O", "Щ"), ("P", "З"),
            ("{", "Х"), ("}", "Ъ"), ("A", "Ф"), ("S", "Ы"), ("D", "В"),
            ("F", "А"), ("G", "П"), ("H", "Р"), ("J", "О"), ("K", "Л"),
            ("L", "Д"), (":", "Ж"), ("\"", "Э"), ("Z", "Я"), ("X", "Ч"),
            ("C", "С"), ("V", "М"), ("B", "И"), ("N", "Т"), ("M", "Ь"),
            ("<", "Б"), (">", "Ю"), ("~", "Ё")
        ]

        var enToRu: [Character: Character] = [:]
        var ruToEn: [Character: Character] = [:]
        for (en, ru) in pairs {
            enToRu[en] = ru
            ruToEn[ru] = en
        }
        return (enToRu, ruToEn)
    }
}
