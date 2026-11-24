import AppKit
import SwiftUI

enum MenuBarIcon {
    static let resourceName = "HengeMenuBar"
    static let resourceExtension = "png"
    static let pointSize = NSSize(width: 22, height: 22)
    static let pixelScale = 2
    static let disabledAlpha: CGFloat = 0.40
    static let fallbackSystemSymbolName = "cloud.fill"

    @MainActor
    private static var mainBundleImages: [MenuBarIconState: NSImage] = [:]

    @MainActor
    static func templateImage(in bundle: Bundle = .main) -> NSImage? {
        templateImage(for: .active, in: bundle)
    }

    @MainActor
    static func templateImage(for state: MenuBarIconState, in bundle: Bundle = .main) -> NSImage? {
        if bundle === Bundle.main {
            if let cached = mainBundleImages[state] {
                return cached
            }
            guard let rendered = loadTemplateImage(for: state, from: bundle) else {
                return nil
            }
            mainBundleImages[state] = rendered
            return rendered
        }

        return loadTemplateImage(for: state, from: bundle)
    }

    static func loadTemplateImage(from bundle: Bundle) -> NSImage? {
        loadTemplateImage(for: .active, from: bundle)
    }

    static func loadTemplateImage(for state: MenuBarIconState, from bundle: Bundle) -> NSImage? {
        guard let baseImage = loadBaseTemplateImage(from: bundle) else {
            return nil
        }

        switch state {
        case .active:
            return baseImage
        case .disabled:
            return renderImage(from: baseImage, alpha: disabledAlpha, badge: nil)
        case .permissionRequired:
            return renderImage(from: baseImage, alpha: 1.0, badge: .solidDot)
        case .degraded:
            return renderImage(from: baseImage, alpha: 1.0, badge: .ring)
        }
    }

    private static func loadBaseTemplateImage(from bundle: Bundle) -> NSImage? {
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
        image.accessibilityDescription = L10n.string("app.name", defaultValue: "Henge", bundle: bundle)
        return image
    }

    private enum BadgeStyle {
        case solidDot
        case ring
    }

    private static func renderImage(
        from baseImage: NSImage,
        alpha: CGFloat,
        badge: BadgeStyle?
    ) -> NSImage? {
        let pixelsWide = Int(pointSize.width) * pixelScale
        let pixelsHigh = Int(pointSize.height) * pixelScale
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        bitmap.size = pointSize

        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }

        let targetRect = NSRect(origin: .zero, size: pointSize)
        baseImage.draw(
            in: targetRect,
            from: .zero,
            operation: .sourceOver,
            fraction: alpha
        )

        if let badge {
            drawBadge(badge, in: context)
        }

        let image = NSImage(size: pointSize)
        image.addRepresentation(bitmap)
        image.isTemplate = true
        image.accessibilityDescription = baseImage.accessibilityDescription ?? "Henge"
        return image
    }

    private static func drawBadge(_ style: BadgeStyle, in context: NSGraphicsContext) {
        let center = NSPoint(x: 18.0, y: 3.5)
        let haloRadius: CGFloat = 3.5
        let haloRect = NSRect(
            x: center.x - haloRadius,
            y: center.y - haloRadius,
            width: haloRadius * 2,
            height: haloRadius * 2
        )

        context.compositingOperation = .clear
        NSColor.clear.setFill()
        NSBezierPath(ovalIn: haloRect).fill()

        context.compositingOperation = .sourceOver
        NSColor.black.setFill()
        NSColor.black.setStroke()

        switch style {
        case .solidDot:
            let dotRadius: CGFloat = 2.5
            let dotRect = NSRect(
                x: center.x - dotRadius,
                y: center.y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )
            NSBezierPath(ovalIn: dotRect).fill()
        case .ring:
            let ringRadius: CGFloat = 2.25
            let ringRect = NSRect(
                x: center.x - ringRadius,
                y: center.y - ringRadius,
                width: ringRadius * 2,
                height: ringRadius * 2
            )
            let path = NSBezierPath(ovalIn: ringRect)
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    static func fallbackSymbolName(for state: MenuBarIconState) -> String {
        switch state {
        case .disabled:
            return "cloud"
        case .permissionRequired, .degraded:
            return "exclamationmark.cloud"
        case .active:
            return fallbackSystemSymbolName
        }
    }

    static func accessibilityValue(for state: MenuBarIconState, bundle: Bundle = .main) -> String {
        switch state {
        case .active:
            return L10n.string(
                "menubar.icon.accessibility.active",
                defaultValue: "Active",
                bundle: bundle
            )
        case .disabled:
            return L10n.string(
                "menubar.icon.accessibility.disabled",
                defaultValue: "Disabled",
                bundle: bundle
            )
        case .permissionRequired:
            return L10n.string(
                "menubar.icon.accessibility.permission_required",
                defaultValue: "Accessibility permission required",
                bundle: bundle
            )
        case .degraded:
            return L10n.string(
                "menubar.icon.accessibility.degraded",
                defaultValue: "Shortcut registration degraded",
                bundle: bundle
            )
        }
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
    let state: MenuBarIconState
    let symbolName: String
    let bundle: Bundle

    init(
        state: MenuBarIconState = .active,
        symbolName: String? = nil,
        bundle: Bundle = .main
    ) {
        self.state = state
        self.symbolName = symbolName ?? MenuBarIcon.fallbackSymbolName(for: state)
        self.bundle = bundle
    }

    var body: some View {
        if let image = MenuBarIcon.templateImage(for: state, in: bundle) {
            Image(nsImage: image)
                .renderingMode(.template)
                .accessibilityLabel(Text(L10n.string("app.name", defaultValue: "Henge", bundle: bundle)))
                .accessibilityValue(Text(MenuBarIcon.accessibilityValue(for: state, bundle: bundle)))
        } else {
            Image(systemName: MenuBarIcon.resolvedFallbackSymbolName(preferred: symbolName))
                .accessibilityLabel(Text(L10n.string("app.name", defaultValue: "Henge", bundle: bundle)))
                .accessibilityValue(Text(MenuBarIcon.accessibilityValue(for: state, bundle: bundle)))
        }
    }
}
