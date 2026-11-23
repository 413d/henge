import AppKit
import Foundation
import Testing
@testable import Henge

@MainActor
struct MenuBarIconTests {
    @Test
    func loadsTemplateMenuBarImageScaledToMenuBarPointSize() throws {
        let sourceIconURL = repositoryRootURL().appendingPathComponent("App/HengeMenuBar.png")
        let bundleURL = try makeTemporaryResourceBundle(iconData: try Data(contentsOf: sourceIconURL))
        defer { try? FileManager.default.removeItem(at: bundleURL) }

        let bundle = try #require(Bundle(url: bundleURL))
        let image = try #require(MenuBarIcon.loadTemplateImage(from: bundle))

        #expect(image.isTemplate)
        #expect(image.size == MenuBarIcon.pointSize)
        #expect(image.accessibilityDescription == "Henge")
        #expect(!image.representations.isEmpty)
        for representation in image.representations {
            #expect(representation.size == MenuBarIcon.pointSize)
            #expect(representation.pixelsWide == 44)
            #expect(representation.pixelsHigh == 44)
        }
    }

    @Test
    func returnsNilWhenMenuBarResourceIsMissing() throws {
        let bundleURL = try makeTemporaryResourceBundle(iconData: nil)
        defer { try? FileManager.default.removeItem(at: bundleURL) }

        let bundle = try #require(Bundle(url: bundleURL))
        #expect(MenuBarIcon.loadTemplateImage(from: bundle) == nil)
    }

    @Test
    func returnsNilWhenMenuBarResourceIsCorrupt() throws {
        let bundleURL = try makeTemporaryResourceBundle(iconData: Data("not a valid png".utf8))
        defer { try? FileManager.default.removeItem(at: bundleURL) }

        let bundle = try #require(Bundle(url: bundleURL))
        #expect(MenuBarIcon.loadTemplateImage(from: bundle) == nil)
    }

    @Test
    func resolvedFallbackSymbolNameRemapsUnavailableSymbolsSafely() {
        #expect(
            MenuBarIcon.resolvedFallbackSymbolName(
                preferred: "cloud.fill",
                symbolExists: { $0 == "cloud.fill" }
            ) == "cloud.fill"
        )

        #expect(
            MenuBarIcon.resolvedFallbackSymbolName(
                preferred: "exclamationmark.cloud",
                symbolExists: { $0 == "exclamationmark.icloud" || $0 == "cloud.fill" }
            ) == "exclamationmark.icloud"
        )

        #expect(
            MenuBarIcon.resolvedFallbackSymbolName(
                preferred: "nonexistent.symbol",
                symbolExists: { _ in false }
            ) == MenuBarIcon.fallbackSystemSymbolName
        )
    }

    @Test
    func rendersDistinctTemplateImagesForAllStates() throws {
        let sourceIconURL = repositoryRootURL().appendingPathComponent("App/HengeMenuBar.png")
        let bundleURL = try makeTemporaryResourceBundle(iconData: try Data(contentsOf: sourceIconURL))
        defer { try? FileManager.default.removeItem(at: bundleURL) }

        let bundle = try #require(Bundle(url: bundleURL))
        let states: [MenuBarIconState] = [.active, .disabled, .permissionRequired, .degraded]
        var bitmapsByState: [MenuBarIconState: NSBitmapImageRep] = [:]

        for state in states {
            let image = try #require(MenuBarIcon.templateImage(for: state, in: bundle))
            #expect(image.isTemplate)
            #expect(image.size == MenuBarIcon.pointSize)
            #expect(image.accessibilityDescription == "Henge")
            #expect(!image.representations.isEmpty)
            for representation in image.representations {
                #expect(representation.size == MenuBarIcon.pointSize)
                #expect(representation.pixelsWide == 44)
                #expect(representation.pixelsHigh == 44)
            }
            let bitmap = try #require(image.representations.compactMap { $0 as? NSBitmapImageRep }.first)
            bitmapsByState[state] = bitmap
        }

        let activeBitmap = try #require(bitmapsByState[.active])
        let disabledBitmap = try #require(bitmapsByState[.disabled])
        let permissionBitmap = try #require(bitmapsByState[.permissionRequired])
        let degradedBitmap = try #require(bitmapsByState[.degraded])

        #expect(maxAlpha(in: activeBitmap) > 0.9)
        let disabledMaxAlpha = maxAlpha(in: disabledBitmap)
        #expect(disabledMaxAlpha > 0.25 && disabledMaxAlpha < 0.55)

        // Bottom-right badge center in 44x44 top-left pixel coordinates is (36, 37).
        #expect(alpha(in: activeBitmap, x: 36, y: 37) < 0.1)
        #expect(alpha(in: permissionBitmap, x: 36, y: 37) > 0.9)

        // Degraded state renders a hollow ring badge: cleared center, opaque perimeter.
        #expect(alpha(in: degradedBitmap, x: 36, y: 37) < 0.1)
        #expect(maxAlpha(in: degradedBitmap, xRange: 31...41, yRange: 32...42) > 0.7)
    }

    @Test
    func returnsNilForAllStatesWhenMenuBarResourceIsMissing() throws {
        let bundleURL = try makeTemporaryResourceBundle(iconData: nil)
        defer { try? FileManager.default.removeItem(at: bundleURL) }

        let bundle = try #require(Bundle(url: bundleURL))
        for state in [MenuBarIconState.active, .disabled, .permissionRequired, .degraded] {
            #expect(MenuBarIcon.templateImage(for: state, in: bundle) == nil)
        }
    }

    @Test
    func mapsFallbackSymbolsAndAccessibilityValuesForAllStates() {
        #expect(MenuBarIcon.fallbackSymbolName(for: .active) == "cloud.fill")
        #expect(MenuBarIcon.fallbackSymbolName(for: .disabled) == "cloud")
        #expect(MenuBarIcon.fallbackSymbolName(for: .permissionRequired) == "exclamationmark.cloud")
        #expect(MenuBarIcon.fallbackSymbolName(for: .degraded) == "exclamationmark.cloud")

        #expect(MenuBarIcon.accessibilityValue(for: .active) == "Active")
        #expect(MenuBarIcon.accessibilityValue(for: .disabled) == "Disabled")
        #expect(MenuBarIcon.accessibilityValue(for: .permissionRequired) == "Accessibility permission required")
        #expect(MenuBarIcon.accessibilityValue(for: .degraded) == "Shortcut registration degraded")
    }

    private func alpha(in bitmap: NSBitmapImageRep, x: Int, y: Int) -> CGFloat {
        bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
    }

    private func maxAlpha(
        in bitmap: NSBitmapImageRep,
        xRange: ClosedRange<Int> = 0...43,
        yRange: ClosedRange<Int> = 0...43
    ) -> CGFloat {
        var maximum: CGFloat = 0
        for y in yRange {
            for x in xRange {
                maximum = max(maximum, alpha(in: bitmap, x: x, y: y))
            }
        }
        return maximum
    }

    private func repositoryRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func makeTemporaryResourceBundle(iconData: Data?) throws -> URL {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("henge-menubar-icon-test-\(UUID().uuidString).bundle")
        let contentsURL = bundleURL.appendingPathComponent("Contents")
        let resourcesURL = contentsURL.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        let infoPlist: [String: Any] = [
            "CFBundleIdentifier": "io.github.413d.Henge.MenuBarIconTests.\(UUID().uuidString)",
            "CFBundleName": "MenuBarIconTests",
            "CFBundlePackageType": "BNDL",
            "CFBundleVersion": "1"
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
        try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))

        if let iconData {
            try iconData.write(to: resourcesURL.appendingPathComponent("HengeMenuBar.png"))
        }

        return bundleURL
    }
}
