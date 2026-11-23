import OSLog
import Testing
@testable import Henge

struct DiagnosticsTests {
    @Test
    func lengthBucketBoundaries() {
        #expect(Diagnostics.lengthBucket(-1) == .empty)
        #expect(Diagnostics.lengthBucket(0) == .empty)
        #expect(Diagnostics.lengthBucket(1) == .short)
        #expect(Diagnostics.lengthBucket(64) == .short)
        #expect(Diagnostics.lengthBucket(65) == .medium)
        #expect(Diagnostics.lengthBucket(1024) == .medium)
        #expect(Diagnostics.lengthBucket(1025) == .long)
        #expect(Diagnostics.lengthBucket(65_536) == .long)
        #expect(Diagnostics.lengthBucket(65_537) == .huge)
    }

    @Test
    func bundleIdentifierValidationRejectsUserText() {
        #expect(Diagnostics.bundleIdentifier("привет") == nil)
        #expect(Diagnostics.bundleIdentifier("hello world") == nil)
        #expect(Diagnostics.bundleIdentifier("ghbdtn привет") == nil)
        #expect(Diagnostics.bundleIdentifier("") == nil)
        #expect(Diagnostics.bundleIdentifier("com.apple.Safari\n") == nil)
        #expect(Diagnostics.bundleIdentifier(String(repeating: "a", count: 256)) == nil)

        #expect(Diagnostics.bundleIdentifier("com.apple.Safari") == "com.apple.Safari")
        #expect(Diagnostics.bundleIdentifier("io.github.413d.Henge") == "io.github.413d.Henge")
        #expect(Diagnostics.bundleIdentifier(String(repeating: "a", count: 255)) == String(repeating: "a", count: 255))
    }

    @Test
    func pasteboardTypeNamesValidationRejectsUserText() {
        #expect(Diagnostics.pasteboardTypeNames(["привет"]) == nil)
        #expect(Diagnostics.pasteboardTypeNames(["public.utf8 plain"]) == nil)
        #expect(Diagnostics.pasteboardTypeNames([""]) == nil)
        #expect(Diagnostics.pasteboardTypeNames(["public.utf8-plain-text", "bad value"]) == nil)
        #expect(Diagnostics.pasteboardTypeNames([String(repeating: "a", count: 129)]) == nil)

        let validTypes = ["public.utf8-plain-text", "com.adobe.pdf"]
        #expect(Diagnostics.pasteboardTypeNames(validTypes) == validTypes)
        #expect(Diagnostics.pasteboardTypeNames([]) == [])
        #expect(Diagnostics.pasteboardTypeNames([String(repeating: "a", count: 128)]) == [String(repeating: "a", count: 128)])
    }

    @Test
    func categoriesCoverAllLoggers() {
        #expect(DiagnosticsCategory.allCases.count == 5)
        #expect(DiagnosticsCategory.hotkey.rawValue == "hotkey")
        #expect(DiagnosticsCategory.text.rawValue == "text")
        #expect(DiagnosticsCategory.clipboard.rawValue == "clipboard")
        #expect(DiagnosticsCategory.config.rawValue == "config")
        #expect(DiagnosticsCategory.loginItem.rawValue == "login-item")
        #expect(Diagnostics.subsystem == "io.github.413d.Henge")

        for category in DiagnosticsCategory.allCases {
            let logger = Diagnostics.logger(category)
            _ = logger
        }
    }
}
