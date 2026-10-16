import AppKit
import Foundation

// Generates App/Henge.icns (renders PNG sizes, assembles via iconutil).
// Usage: swift scripts/dev/generate-icon.swift

func drawPuff(into context: CGContext, scale: CGFloat) {
    // Anime-style vanishing smoke: overlapping soft circles forming a cloud puff.
    let puffs: [(CGFloat, CGFloat, CGFloat)] = [
        (0.50, 0.52, 0.30),
        (0.32, 0.44, 0.22),
        (0.68, 0.44, 0.22),
        (0.40, 0.62, 0.20),
        (0.60, 0.62, 0.20),
        (0.50, 0.34, 0.18),
        (0.24, 0.58, 0.14),
        (0.76, 0.58, 0.14),
    ]

    let puffColor = NSColor(calibratedRed: 0.93, green: 0.95, blue: 0.97, alpha: 1.0)
    let shadeColor = NSColor(calibratedRed: 0.76, green: 0.80, blue: 0.85, alpha: 1.0)

    context.saveGState()
    context.setBlendMode(.normal)

    // Soft shadow layer slightly offset
    context.setFillColor(shadeColor.withAlphaComponent(0.35).cgColor)
    for (cx, cy, r) in puffs {
        let rect = CGRect(
            x: (cx - r) * scale + 2 * scale / 100,
            y: (cy - r) * scale + 3 * scale / 100,
            width: 2 * r * scale,
            height: 2 * r * scale
        )
        context.fillEllipse(in: rect)
    }

    // Main puffs
    context.setFillColor(puffColor.cgColor)
    for (cx, cy, r) in puffs {
        let rect = CGRect(
            x: (cx - r) * scale,
            y: (cy - r) * scale,
            width: 2 * r * scale,
            height: 2 * r * scale
        )
        context.fillEllipse(in: rect)
    }

    // Small trailing wisp dots (motion of the poof)
    let wisps: [(CGFloat, CGFloat, CGFloat)] = [
        (0.84, 0.30, 0.055),
        (0.89, 0.40, 0.035),
        (0.17, 0.30, 0.045),
        (0.13, 0.42, 0.030),
    ]
    for (cx, cy, r) in wisps {
        let rect = CGRect(
            x: (cx - r) * scale,
            y: (cy - r) * scale,
            width: 2 * r * scale,
            height: 2 * r * scale
        )
        context.fillEllipse(in: rect)
    }

    context.restoreGState()
}

func renderIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    // Background: dark rounded square (macOS icon style)
    let radius = size * 0.22
    let bgPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    let colors = [
        NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.18, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.32, alpha: 1.0).cgColor,
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
        context.saveGState()
        context.addPath(bgPath)
        context.clip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
        context.restoreGState()
    }

    // Smoke puff
    drawPuff(into: context, scale: size * 0.86)

    image.unlockFocus()
    return image
}

let fileManager = FileManager.default
let iconPNGDir = "/tmp/henge-icon-png"
let icnsPath = "App/Henge.icns"

try? fileManager.removeItem(atPath: iconPNGDir)
try fileManager.createDirectory(atPath: iconPNGDir, withIntermediateDirectories: true)

let sizes = [16, 32, 64, 128, 256, 512, 1024]
for size in sizes {
    let image = renderIcon(size: CGFloat(size))
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fputs("failed to render size \(size)\n", stderr)
        exit(1)
    }
    // iconutil requires names like icon_16x16.png, icon_16x16@2x.png (32), etc.
    let name: String
    switch size {
    case 16: name = "icon_16x16.png"
    case 32: name = "icon_32x32.png"
    case 64: name = "icon_16x16@2x.png"
    case 128: name = "icon_128x128.png"
    case 256: name = "icon_256x256.png"
    case 512: name = "icon_512x512.png"
    case 1024: name = "icon_512x512@2x.png"
    default: name = "icon_\(size)x\(size).png"
    }
    try png.write(to: URL(fileURLWithPath: "\(iconPNGDir)/\(name)"))
}

// @2x variants for iconutil: 32x32@2x, 128x128@2x, 256x256@2x
if let data = fileManager.contents(atPath: "\(iconPNGDir)/icon_32x32.png"),
   let rep = NSBitmapImageRep(data: data),
   let big = rep.cgImage {
    let ci = NSCIImageRep(ciImage: CIImage(cgImage: big))
    let out = NSImage(size: NSSize(width: 64, height: 64))
    out.addRepresentation(ci)
    if let tiff = out.tiffRepresentation, let pngRep = NSBitmapImageRep(data: tiff),
       let png = pngRep.representation(using: .png, properties: [:]) {
        try png.write(to: URL(fileURLWithPath: "\(iconPNGDir)/icon_32x32@2x.png"))
    }
}
if let data = fileManager.contents(atPath: "\(iconPNGDir)/icon_128x128.png"),
   let rep = NSBitmapImageRep(data: data),
   let big = rep.cgImage {
    let ci = NSCIImageRep(ciImage: CIImage(cgImage: big))
    let out = NSImage(size: NSSize(width: 256, height: 256))
    out.addRepresentation(ci)
    if let tiff = out.tiffRepresentation, let pngRep = NSBitmapImageRep(data: tiff),
       let png = pngRep.representation(using: .png, properties: [:]) {
        try png.write(to: URL(fileURLWithPath: "\(iconPNGDir)/icon_128x128@2x.png"))
    }
}
if let data = fileManager.contents(atPath: "\(iconPNGDir)/icon_256x256.png"),
   let rep = NSBitmapImageRep(data: data),
   let big = rep.cgImage {
    let ci = NSCIImageRep(ciImage: CIImage(cgImage: big))
    let out = NSImage(size: NSSize(width: 512, height: 512))
    out.addRepresentation(ci)
    if let tiff = out.tiffRepresentation, let pngRep = NSBitmapImageRep(data: tiff),
       let png = pngRep.representation(using: .png, properties: [:]) {
        try png.write(to: URL(fileURLWithPath: "\(iconPNGDir)/icon_256x256@2x.png"))
    }
}

let iconset = "App/Henge.iconset"
try? fileManager.removeItem(atPath: iconset)
try fileManager.createDirectory(atPath: iconset, withIntermediateDirectories: true)
let files = try fileManager.contentsOfDirectory(atPath: iconPNGDir)
for f in files where f.hasSuffix(".png") {
    try fileManager.copyItem(atPath: "\(iconPNGDir)/\(f)", toPath: "\(iconset)/\(f)")
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset, "-o", icnsPath]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    fputs("iconutil failed\n", stderr)
    exit(1)
}
try? fileManager.removeItem(atPath: iconset)
print("wrote \(icnsPath)")
