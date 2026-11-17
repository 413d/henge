import AppKit
import Foundation

// Generates the colorful app icon and the monochrome, template-ready menu bar mark.
// Usage: swift scripts/dev/generate-icon.swift

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha)
}

func path(_ context: CGContext, _ points: [CGPoint], close: Bool = true) {
    guard let first = points.first else { return }
    context.beginPath()
    context.move(to: first)
    for point in points.dropFirst() { context.addLine(to: point) }
    if close { context.closePath() }
}

func render(_ size: Int, template: Bool = false) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let c = NSGraphicsContext.current!.cgContext
    c.scaleBy(x: CGFloat(size), y: CGFloat(size))
    c.setLineCap(.round)
    c.setLineJoin(.round)

    if !template {
        let bg = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                        cornerWidth: 0.22, cornerHeight: 0.22, transform: nil)
        c.addPath(bg)
        let colors = [color(0x17152e), color(0x42316e), color(0x216f92)] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                                  locations: [0, 0.55, 1])!
        c.saveGState(); c.clip(); c.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 1),
                                                       end: CGPoint(x: 1, y: 0), options: [])
        c.restoreGState()
        // Subtle warm halo behind the transformation.
        c.setFillColor(color(0xf7a75c, alpha: 0.20))
        c.fillEllipse(in: CGRect(x: 0.19, y: 0.16, width: 0.62, height: 0.62))
    }

    // An energetic cloud silhouette with a rising curl, echoing the attached smoke reference.
    let silhouette: [CGPoint] = [
        (0.22,0.28),(0.13,0.31),(0.10,0.39),(0.12,0.47),(0.08,0.53),
        (0.10,0.63),(0.18,0.67),(0.20,0.75),(0.29,0.79),(0.36,0.76),
        (0.43,0.84),(0.54,0.82),(0.60,0.76),(0.71,0.79),(0.79,0.73),
        (0.80,0.66),(0.89,0.63),(0.92,0.55),(0.88,0.48),(0.91,0.42),
        (0.87,0.34),(0.79,0.32),(0.76,0.24),(0.66,0.20),(0.59,0.24),
        (0.52,0.18),(0.42,0.19),(0.36,0.24),(0.29,0.21)
    ].map { CGPoint(x: $0.0, y: $0.1) }
    path(c, silhouette)
    c.setFillColor(template ? color(0x000000) : color(0xffd6a2))
    c.saveGState(); c.setShadow(offset: CGSize(width: 0, height: -0.018), blur: 0.035,
                                color: template ? nil : color(0x100d26, alpha: 0.65))
    c.fillPath(); c.restoreGState()

    if !template {
        // Warm cream-to-coral volume across the cloud.
        path(c, silhouette)
        let fill = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [color(0xfff6dc), color(0xffc58c), color(0xf47b78)] as CFArray,
                              locations: [0, 0.52, 1])!
        c.saveGState(); c.clip(); c.drawLinearGradient(fill, start: CGPoint(x: 0.28, y: 0.82),
                                                       end: CGPoint(x: 0.71, y: 0.19), options: [])
        c.restoreGState()

        // Curled vortex cutout and tail: a bold indigo stroke reads as transformation at small sizes.
        c.beginPath()
        c.move(to: CGPoint(x: 0.72, y: 0.61))
        c.addCurve(to: CGPoint(x: 0.41, y: 0.48), control1: CGPoint(x: 0.67, y: 0.72), control2: CGPoint(x: 0.43, y: 0.72))
        c.addCurve(to: CGPoint(x: 0.56, y: 0.36), control1: CGPoint(x: 0.39, y: 0.36), control2: CGPoint(x: 0.53, y: 0.34))
        c.addCurve(to: CGPoint(x: 0.48, y: 0.56), control1: CGPoint(x: 0.62, y: 0.44), control2: CGPoint(x: 0.57, y: 0.57))
        c.setStrokeColor(color(0x6953a2, alpha: 0.88)); c.setLineWidth(0.055); c.strokePath()
        c.beginPath(); c.move(to: CGPoint(x: 0.40, y: 0.47))
        c.addCurve(to: CGPoint(x: 0.31, y: 0.39), control1: CGPoint(x: 0.34, y: 0.48), control2: CGPoint(x: 0.31, y: 0.44))
        c.setStrokeColor(color(0xfff8e8)); c.setLineWidth(0.025); c.strokePath()

        // Little flying puffs and motion streaks make the signature “poof”.
        let accent = color(0xffedc8)
        c.setFillColor(accent)
        for (x,y,r) in [(0.18,0.77,0.038),(0.84,0.78,0.028),(0.88,0.23,0.045)] as [(CGFloat,CGFloat,CGFloat)] {
            c.fillEllipse(in: CGRect(x: x-r, y: y-r, width: r*2, height: r*2))
        }
        c.setStrokeColor(color(0xffe8c0, alpha: 0.9)); c.setLineWidth(0.018)
        for (a,b,d,e) in [(0.18,0.57,0.08,0.60),(0.82,0.45,0.94,0.48),(0.72,0.18,0.78,0.13)] as [(CGFloat,CGFloat,CGFloat,CGFloat)] {
            c.beginPath(); c.move(to: CGPoint(x:a,y:b)); c.addLine(to: CGPoint(x:d,y:e)); c.strokePath()
        }
        // Fine bright highlight along the upper lobes.
        c.beginPath(); c.move(to: CGPoint(x:0.18,y:0.57))
        c.addCurve(to: CGPoint(x:0.43,y:0.77), control1: CGPoint(x:0.13,y:0.68), control2: CGPoint(x:0.29,y:0.81))
        c.setStrokeColor(color(0xffffff, alpha:0.72)); c.setLineWidth(0.014); c.strokePath()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("App/Henge.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, size) in [("icon_16x16.png",16),("icon_16x16@2x.png",32),
                     ("icon_32x32.png",32),("icon_32x32@2x.png",64),
                     ("icon_128x128.png",128),("icon_128x128@2x.png",256),
                     ("icon_256x256.png",256),("icon_256x256@2x.png",512),
                     ("icon_512x512.png",512),("icon_512x512@2x.png",1024)] {
    try writePNG(render(size), to: iconset.appendingPathComponent(name))
}
let iconProcess = Process()
iconProcess.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconProcess.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("App/Henge.icns").path]
try iconProcess.run(); iconProcess.waitUntilExit()
guard iconProcess.terminationStatus == 0 else { fatalError("iconutil failed") }
try FileManager.default.removeItem(at: iconset)
try writePNG(render(44, template: true), to: root.appendingPathComponent("App/HengeMenuBar.png"))
print("wrote App/Henge.icns and App/HengeMenuBar.png")
