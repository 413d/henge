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
