import AppKit
import SwiftUI

enum MenuBarIcon {
    static let resourceName = "HengeMenuBar"
    static let resourceExtension = "png"
    static let pointSize = NSSize(width: 22, height: 22)
    static let fallbackSystemSymbolName = "cloud.fill"

    @MainActor
    private static let mainBundleTemplateImage: NSImage? = loadTemplateImage(from: .main)

    @MainActor
    static func templateImage(in bundle: Bundle = .main) -> NSImage? {
        if bundle === Bundle.main {
            return mainBundleTemplateImage
        }

        return loadTemplateImage(from: bundle)
    }

    static func loadTemplateImage(from bundle: Bundle) -> NSImage? {
        let loadedImage: NSImage?
        if let url = bundle.url(forResource: resourceName, withExtension: resourceExtension) {
            loadedImage = NSImage(contentsOf: url)
        } else {
            loadedImage = bundle.image(forResource: NSImage.Name(resourceName))?.copy() as? NSImage
        }

        guard let image = loadedImage,
              image.isValid,
              !image.representations.isEmpty else {
            return nil
        }

        image.size = pointSize
        for representation in image.representations {
            representation.size = pointSize
        }
        image.isTemplate = true
        image.accessibilityDescription = "Henge"
        return image
    }

    @MainActor
    static func resolvedFallbackSymbolName(
        preferred: String,
        symbolExists: (String) -> Bool = { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }
    ) -> String {
        if symbolExists(preferred) {
            return preferred
        }

        if preferred == "exclamationmark.cloud", symbolExists("exclamationmark.icloud") {
            return "exclamationmark.icloud"
        }

        return fallbackSystemSymbolName
    }
}

struct MenuBarIconLabel: View {
    let symbolName: String
    let bundle: Bundle

    init(symbolName: String, bundle: Bundle = .main) {
        self.symbolName = symbolName
        self.bundle = bundle
    }

    var body: some View {
        if let image = MenuBarIcon.templateImage(in: bundle) {
            Image(nsImage: image)
                .renderingMode(.template)
                .accessibilityLabel(Text("Henge"))
        } else {
            Image(systemName: MenuBarIcon.resolvedFallbackSymbolName(preferred: symbolName))
                .accessibilityLabel(Text("Henge"))
        }
    }
}
