#!/usr/bin/env swift

import AppKit
import Foundation

// Icon sizes required for macOS .icns
let sizes = [16, 32, 64, 128, 256, 512, 1024]

let iconsetDir = "AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconsetDir)
try! FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

func renderIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext

    // Rounded rect background — canary yellow
    let radius = s * 0.22
    let bgPath = CGMutablePath()
    bgPath.addRoundedRect(in: CGRect(x: 0, y: 0, width: s, height: s), cornerWidth: radius, cornerHeight: radius)
    ctx.setFillColor(CGColor(red: 0.984, green: 0.780, blue: 0.082, alpha: 1)) // #FBCE15 canary yellow
    ctx.addPath(bgPath)
    ctx.fillPath()

    // Subtle gradient overlay
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.18),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.00)
        ] as CFArray,
        locations: [0.0, 1.0])!
    ctx.addPath(bgPath)
    ctx.clip()
    ctx.drawLinearGradient(gradient,
        start: CGPoint(x: s * 0.5, y: s),
        end: CGPoint(x: s * 0.5, y: s * 0.4),
        options: [])
    ctx.resetClip()

    // Black bird symbol
    let padding = s * 0.15
    let symbolRect = CGRect(x: padding, y: padding, width: s - padding * 2, height: s - padding * 2)
    let fontSize = s * 0.60
    let cfg = NSImage.SymbolConfiguration(pointSize: fontSize, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.black]))
    if let symbol = NSImage(systemSymbolName: "bird.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, path: String) {
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: path))
}

// Generate all sizes (1x and 2x)
let sizeNames: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (size, name) in sizeNames {
    print("Rendering \(name)...")
    let img = renderIcon(size: size)
    savePNG(img, path: "\(iconsetDir)/\(name)")
}

print("Running iconutil...")
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetDir, "-o", "AppIcon.icns"]
try! proc.run()
proc.waitUntilExit()

try? FileManager.default.removeItem(atPath: iconsetDir)
print("Done — AppIcon.icns created.")
