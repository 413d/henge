import Foundation
import Testing
@testable import Henge

struct LocalizationTests {
    private static let repositoryRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // HengeTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
    }()

    private static var enStringsURL: URL {
        repositoryRoot.appendingPathComponent("App/Localization/en.lproj/Localizable.strings")
    }

    private static var ruStringsURL: URL {
        repositoryRoot.appendingPathComponent("App/Localization/ru.lproj/Localizable.strings")
    }

    private static func loadStringsDictionary(from url: URL) throws -> [String: String] {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let dictionary = try #require(plist as? [String: String])
        return dictionary
    }

    private static func formatSpecifiers(in value: String) -> [String] {
        let pattern = #"%(?:\d+\$)?(?:@|d|i|u|x|X|o|ld|lu|lld|llu|f|g|e)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.matches(in: value, range: range).compactMap { match in
            Range(match.range, in: value).map { String(value[$0]) }
        }
    }

    @Test
    func localizationTablesParseCleanlyAndHaveMatchingKeysAndSpecifiers() throws {
        let en = try Self.loadStringsDictionary(from: Self.enStringsURL)
        let ru = try Self.loadStringsDictionary(from: Self.ruStringsURL)

        #expect(!en.isEmpty)
        #expect(Set(en.keys) == Set(ru.keys))

        for key in en.keys.sorted() {
            let enValue = try #require(en[key])
            let ruValue = try #require(ru[key])

            #expect(!enValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty EN value for \(key)")
            #expect(!ruValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty RU value for \(key)")

            let enSpecifiers = Self.formatSpecifiers(in: enValue)
            let ruSpecifiers = Self.formatSpecifiers(in: ruValue)
            #expect(enSpecifiers == ruSpecifiers, "Format specifiers mismatch for \(key): EN=\(enSpecifiers) RU=\(ruSpecifiers)")
        }
    }

    @Test
    func allSourceLocalizationKeysAndDefaultValuesMatchLocalizationTables() throws {
        let en = try Self.loadStringsDictionary(from: Self.enStringsURL)
        let ru = try Self.loadStringsDictionary(from: Self.ruStringsURL)

        let sourcesRoot = Self.repositoryRoot.appendingPathComponent("Sources")
        let enumerator = try #require(
            FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil)
        )

        let callPattern = #"L10n\.(?:string|format)\(\s*"([^"]+)"\s*,\s*defaultValue:\s*"([^"]+)""#
        let regex = try NSRegularExpression(pattern: callPattern)

        var seenKeys = Set<String>()
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let range = NSRange(content.startIndex..<content.endIndex, in: content)
            for match in regex.matches(in: content, range: range) {
                guard let keyRange = Range(match.range(at: 1), in: content),
                      let defaultRange = Range(match.range(at: 2), in: content) else {
                    continue
                }
                let key = String(content[keyRange])
                let defaultValue = String(content[defaultRange])
                seenKeys.insert(key)

                #expect(en[key] == defaultValue, "EN value mismatch for key \(key)")
                #expect(ru[key] != nil, "Missing RU key \(key)")
            }
        }

        #expect(seenKeys == Set(en.keys), "Unused or missing keys between Sources and Localizable.strings")
    }

    @Test
    func l10nResolvesLocalizedStringsFromTemporaryRuLprojBundleAndFallsBackToDefaultValue() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("henge-l10n-test-\(UUID().uuidString)", isDirectory: true)
        let ruLproj = tempRoot.appendingPathComponent("ru.lproj", isDirectory: true)
        try FileManager.default.createDirectory(at: ruLproj, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let targetStrings = ruLproj.appendingPathComponent("Localizable.strings")
        try FileManager.default.copyItem(at: Self.ruStringsURL, to: targetStrings)

        // Loading the .lproj bundle directly (or single-localization bundle) lets us verify
        // Russian lookup deterministically regardless of the host macOS UI language.
        let localizationBundle = try #require(Bundle(url: ruLproj))

        let resolved = L10n.string(
            "menubar.action.fix_text",
            defaultValue: "Fix Text",
            bundle: localizationBundle
        )
        #expect(resolved == "Исправить текст")

        let formatted = L10n.format(
            "fix_outcome.failed.accessibility_error",
            defaultValue: "Henge could not inspect or update the focused element (AXError %d).",
            bundle: localizationBundle,
            Int32(-25204)
        )
        #expect(formatted.contains("-25204"))
        #expect(formatted.contains("Henge не смог"))

        let iconValue = MenuBarIcon.accessibilityValue(for: .permissionRequired, bundle: localizationBundle)
        #expect(iconValue == "Требуется разрешение Универсального доступа")

        let fallback = L10n.string(
            "nonexistent.localization.key",
            defaultValue: "Fallback English Text",
            bundle: localizationBundle
        )
        #expect(fallback == "Fallback English Text")
    }
}
