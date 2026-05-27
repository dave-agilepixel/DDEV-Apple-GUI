import AppKit
import Foundation

struct IconSize {
    let filename: String
    let pixels: CGFloat
}

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputDirectory = repoRoot
    .appendingPathComponent("Sources/DDEVUIApp/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let sizes = [
    IconSize(filename: "icon_16x16.png", pixels: 16),
    IconSize(filename: "icon_16x16@2x.png", pixels: 32),
    IconSize(filename: "icon_32x32.png", pixels: 32),
    IconSize(filename: "icon_32x32@2x.png", pixels: 64),
    IconSize(filename: "icon_128x128.png", pixels: 128),
    IconSize(filename: "icon_128x128@2x.png", pixels: 256),
    IconSize(filename: "icon_256x256.png", pixels: 256),
    IconSize(filename: "icon_256x256@2x.png", pixels: 512),
    IconSize(filename: "icon_512x512.png", pixels: 512),
    IconSize(filename: "icon_512x512@2x.png", pixels: 1024)
]

for size in sizes {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.pixels),
        pixelsHigh: Int(size.pixels),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: .alphaFirst,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Failed to create bitmap for \(size.filename)")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    let rect = NSRect(x: 0, y: 0, width: size.pixels, height: size.pixels)
    let scale = size.pixels / 1024
    let cornerRadius = 220 * scale

    let background = NSGradient(colors: [
        NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.20, alpha: 1),
        NSColor(calibratedRed: 0.03, green: 0.08, blue: 0.13, alpha: 1),
        NSColor(calibratedRed: 0.00, green: 0.25, blue: 0.24, alpha: 1)
    ])!
    let rounded = NSBezierPath(roundedRect: rect.insetBy(dx: 24 * scale, dy: 24 * scale), xRadius: cornerRadius, yRadius: cornerRadius)
    background.draw(in: rounded, angle: -35)

    NSColor(calibratedWhite: 1, alpha: 0.18).setStroke()
    rounded.lineWidth = 10 * scale
    rounded.stroke()

    let terminalRect = NSRect(x: 190 * scale, y: 235 * scale, width: 644 * scale, height: 515 * scale)
    let terminal = NSBezierPath(roundedRect: terminalRect, xRadius: 70 * scale, yRadius: 70 * scale)
    NSColor(calibratedRed: 0.02, green: 0.05, blue: 0.08, alpha: 0.92).setFill()
    terminal.fill()
    NSColor(calibratedRed: 0.78, green: 0.98, blue: 0.88, alpha: 0.92).setStroke()
    terminal.lineWidth = 38 * scale
    terminal.stroke()

    let prompt = NSBezierPath()
    prompt.move(to: NSPoint(x: 305 * scale, y: 545 * scale))
    prompt.line(to: NSPoint(x: 425 * scale, y: 455 * scale))
    prompt.line(to: NSPoint(x: 305 * scale, y: 365 * scale))
    NSColor(calibratedRed: 0.78, green: 0.98, blue: 0.88, alpha: 1).setStroke()
    prompt.lineWidth = 48 * scale
    prompt.lineCapStyle = .round
    prompt.lineJoinStyle = .round
    prompt.stroke()

    let cursor = NSBezierPath()
    cursor.move(to: NSPoint(x: 510 * scale, y: 365 * scale))
    cursor.line(to: NSPoint(x: 700 * scale, y: 365 * scale))
    cursor.lineWidth = 48 * scale
    cursor.lineCapStyle = .round
    cursor.stroke()

    let activeDot = NSBezierPath(ovalIn: NSRect(x: 725 * scale, y: 690 * scale, width: 135 * scale, height: 135 * scale))
    NSColor(calibratedRed: 0.20, green: 0.83, blue: 0.55, alpha: 1).setFill()
    activeDot.fill()
    NSColor(calibratedWhite: 1, alpha: 0.78).setStroke()
    activeDot.lineWidth = 14 * scale
    activeDot.stroke()

    NSGraphicsContext.restoreGraphicsState()

    guard
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        fatalError("Failed to render \(size.filename)")
    }

    try png.write(to: outputDirectory.appendingPathComponent(size.filename), options: [.atomic])
}
