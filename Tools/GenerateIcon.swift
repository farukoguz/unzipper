import AppKit
import Foundation

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1
                          ? CommandLine.arguments[1]
                          : "Resources", isDirectory: true)
let fileManager = FileManager.default
let iconset = outputDirectory.appendingPathComponent("Unzipper.iconset", isDirectory: true)
try? fileManager.removeItem(at: iconset)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

func drawIcon(size: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: size,
                                     pixelsHigh: size,
                                     bitsPerSample: 8,
                                     samplesPerPixel: 4,
                                     hasAlpha: true,
                                     isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0,
                                     bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: 1024, height: 1024)

    let context = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context?.imageInterpolation = .high
    context?.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    let full = NSRect(x: 0, y: 0, width: 1024, height: 1024)
    let squircle = NSBezierPath(roundedRect: full.insetBy(dx: 46, dy: 46),
                                xRadius: 214, yRadius: 214)

    NSGraphicsContext.saveGraphicsState()
    let backgroundShadow = NSShadow()
    backgroundShadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    backgroundShadow.shadowBlurRadius = 34
    backgroundShadow.shadowOffset = NSSize(width: 0, height: -16)
    backgroundShadow.set()
    color(0x2C4BFF).setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    let gradient = NSGradient(colors: [color(0x436BFF), color(0x5A3BFF), color(0x7B2FE0)])
    gradient?.draw(in: squircle, angle: -58)

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    let glow = NSGradient(colors: [NSColor.white.withAlphaComponent(0.30), .clear])
    glow?.draw(fromCenter: NSPoint(x: 330, y: 800),
               radius: 0,
               toCenter: NSPoint(x: 360, y: 760),
               radius: 520,
               options: [])
    let bottomShade = NSGradient(colors: [.clear, NSColor.black.withAlphaComponent(0.16)])
    bottomShade?.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 420), angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    // Archive box with a zipper down the middle.
    let box = NSBezierPath(roundedRect: NSRect(x: 238, y: 254, width: 548, height: 512),
                           xRadius: 72, yRadius: 72)
    NSGraphicsContext.saveGraphicsState()
    let boxShadow = NSShadow()
    boxShadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    boxShadow.shadowBlurRadius = 28
    boxShadow.shadowOffset = NSSize(width: 0, height: -14)
    boxShadow.set()
    NSColor.white.setFill()
    box.fill()
    NSGraphicsContext.restoreGraphicsState()

    // A soft top highlight.
    let topBand = NSBezierPath(roundedRect: NSRect(x: 250, y: 648, width: 524, height: 106),
                               xRadius: 44, yRadius: 44)
    color(0xEEF2FF).setFill()
    topBand.fill()

    let navy = color(0x1B2559)
    let seam = NSBezierPath(roundedRect: NSRect(x: 505, y: 300, width: 14, height: 430),
                            xRadius: 7, yRadius: 7)
    navy.withAlphaComponent(0.18).setFill()
    seam.fill()

    for index in 0..<13 {
        let y = 330 + CGFloat(index) * 31
        let left = index % 2 == 0
        let tooth = NSBezierPath(roundedRect: NSRect(x: left ? 462 : 500, y: y, width: 62, height: 17),
                                 xRadius: 8, yRadius: 8)
        navy.withAlphaComponent(0.85).setFill()
        tooth.fill()
    }

    // Slider + pull.
    let slider = NSBezierPath(roundedRect: NSRect(x: 446, y: 476, width: 132, height: 116),
                              xRadius: 34, yRadius: 34)
    navy.setFill()
    slider.fill()

    let sliderHole = NSBezierPath(roundedRect: NSRect(x: 482, y: 532, width: 60, height: 26),
                                  xRadius: 13, yRadius: 13)
    NSColor.white.withAlphaComponent(0.92).setFill()
    sliderHole.fill()

    let stem = NSBezierPath(roundedRect: NSRect(x: 502, y: 424, width: 20, height: 62),
                            xRadius: 10, yRadius: 10)
    navy.setFill()
    stem.fill()

    let pull = NSBezierPath(ovalIn: NSRect(x: 456, y: 340, width: 112, height: 96))
    pull.lineWidth = 19
    navy.setStroke()
    pull.stroke()

    // Small zipper stop at the top.
    let stop = NSBezierPath(roundedRect: NSRect(x: 480, y: 714, width: 64, height: 24),
                            xRadius: 12, yRadius: 12)
    navy.setFill()
    stop.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

for variant in variants {
    guard let data = drawIcon(size: variant.pixels) else {
        fatalError("Could not render \(variant.name)")
    }
    try data.write(to: iconset.appendingPathComponent(variant.name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", outputDirectory.appendingPathComponent("Unzipper.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
try? fileManager.removeItem(at: iconset)
print("Wrote \(outputDirectory.appendingPathComponent("Unzipper.icns").path)")
