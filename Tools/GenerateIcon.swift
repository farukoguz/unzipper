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

func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func paint(_ path: NSBezierPath, _ colors: [NSColor], angle: CGFloat) {
    guard let gradient = NSGradient(colors: colors) else { return }
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    gradient.draw(in: path.bounds, angle: angle)
    NSGraphicsContext.restoreGraphicsState()
}

/// One volume in the stack. `rect` is the cover; the spine sits on the left and
/// the page block on the right so the pile reads as bound books rather than bars.
func drawBook(_ rect: NSRect,
              cover: (light: UInt32, dark: UInt32, spine: UInt32),
              gold: NSColor) {
    let body = rounded(rect, 26)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.34)
    shadow.shadowBlurRadius = 26
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color(cover.dark).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()

    paint(body, [color(cover.light), color(cover.dark)], angle: -90)

    NSGraphicsContext.saveGraphicsState()
    body.addClip()

    // Page block on the fore-edge.
    let pageRect = NSRect(x: rect.maxX - 62, y: rect.minY + 13,
                          width: 49, height: rect.height - 26)
    paint(rounded(pageRect, 9), [color(0xFFF9E9), color(0xE2D2AA)], angle: -90)

    color(0xBBA97F, alpha: 0.75).setStroke()
    let pageStep = (pageRect.height - 20) / 6
    for index in 0..<7 {
        let y = pageRect.minY + 11 + CGFloat(index) * pageStep
        let line = NSBezierPath()
        line.move(to: NSPoint(x: pageRect.minX + 8, y: y))
        line.line(to: NSPoint(x: pageRect.maxX - 8, y: y))
        line.lineWidth = 2
        line.stroke()
    }

    // Spine plate.
    let spine = NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY,
                                          width: 78, height: rect.height))
    color(cover.spine).setFill()
    spine.fill()

    // Hinge line and two gold bands.
    color(0xFFFFFF, alpha: 0.14).setFill()
    NSRect(x: rect.minX + 76, y: rect.minY + 10, width: 3, height: rect.height - 20).fill()

    for offset in [28.0, CGFloat(rect.height - 39)] {
        let band = rounded(NSRect(x: rect.minX + 17, y: rect.minY + offset,
                                  width: 44, height: 11),
                           5.5)
        paint(band, [gold, color(0xB07C1C)], angle: -90)
    }

    // Soft sheen along the top of the cover.
    let sheen = NSBezierPath(rect: NSRect(x: rect.minX + 88, y: rect.maxY - 22,
                                          width: rect.width - 166, height: 7))
    color(0xFFFFFF, alpha: 0.16).setFill()
    sheen.fill()
    NSGraphicsContext.restoreGraphicsState()
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

    let full = NSRect(x: 0, y: 0, width: 1024, height: 1024)
    let squircle = rounded(full.insetBy(dx: 46, dy: 46), 214)

    NSGraphicsContext.saveGraphicsState()
    let backgroundShadow = NSShadow()
    backgroundShadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
    backgroundShadow.shadowBlurRadius = 34
    backgroundShadow.shadowOffset = NSSize(width: 0, height: -16)
    backgroundShadow.set()
    color(0x1B2233).setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    paint(squircle, [color(0x3A4A72), color(0x232D47), color(0x121826)], angle: -90)

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()

    // Warm spot behind the pile, and a cool rim light at the top.
    let glow = NSGradient(colors: [color(0xF3C85C, alpha: 0.20), .clear])
    glow?.draw(fromCenter: NSPoint(x: 512, y: 540), radius: 0,
               toCenter: NSPoint(x: 512, y: 540), radius: 470, options: [])
    let rim = NSGradient(colors: [NSColor.white.withAlphaComponent(0.20), .clear])
    rim?.draw(fromCenter: NSPoint(x: 400, y: 900), radius: 0,
              toCenter: NSPoint(x: 450, y: 850), radius: 480, options: [])
    let bottomShade = NSGradient(colors: [.clear, NSColor.black.withAlphaComponent(0.24)])
    bottomShade?.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 460), angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    let gold = color(0xF4CD66)
    let deepGold = color(0xB57E1B)
    let darkBronze = color(0x6B470F)

    // Three bound archive volumes, widest in the middle like a hand-made pile.
    drawBook(NSRect(x: 232, y: 258, width: 560, height: 148),
             cover: (light: 0x4263E0, dark: 0x26399C, spine: 0x1D2C7E), gold: gold)
    drawBook(NSRect(x: 206, y: 398, width: 612, height: 148),
             cover: (light: 0xDE5A64, dark: 0xA52F3D, spine: 0x7D2330), gold: gold)
    drawBook(NSRect(x: 248, y: 538, width: 528, height: 148),
             cover: (light: 0x42AC8D, dark: 0x237861, spine: 0x1A5B49), gold: gold)

    // Strap that binds the pile; it doubles as the zipper.
    let strapRect = NSRect(x: 466, y: 242, width: 92, height: 476)
    let strap = rounded(strapRect, 26)
    NSGraphicsContext.saveGraphicsState()
    let strapShadow = NSShadow()
    strapShadow.shadowColor = NSColor.black.withAlphaComponent(0.38)
    strapShadow.shadowBlurRadius = 24
    strapShadow.shadowOffset = NSSize(width: 0, height: -10)
    strapShadow.set()
    deepGold.setFill()
    strap.fill()
    NSGraphicsContext.restoreGraphicsState()

    paint(strap, [color(0xFFE9A6), color(0xE0AD43), color(0xA9741B)], angle: -90)
    deepGold.setStroke()
    strap.lineWidth = 3
    strap.stroke()

    // Stitching down both edges of the strap.
    color(0x8A5E12, alpha: 0.55).setStroke()
    for x in [480.0, 544.0] {
        let stitch = NSBezierPath()
        stitch.move(to: NSPoint(x: x, y: 276))
        stitch.line(to: NSPoint(x: x, y: 684))
        stitch.lineWidth = 3
        stitch.setLineDash([10, 9], count: 2, phase: 0)
        stitch.stroke()
    }

    // Interlocking teeth beside a recessed seam.
    let seam = rounded(NSRect(x: 500, y: 272, width: 24, height: 416),
                       12)
    color(0x5E3E0C, alpha: 0.85).setFill()
    seam.fill()

    for index in 0..<17 {
        let y = 280 + CGFloat(index) * 23.5
        let left = index % 2 == 0
        let tooth = rounded(NSRect(x: left ? 477 : 523, y: y, width: 25, height: 12),
                            5)
        darkBronze.setFill()
        tooth.fill()
        color(0xFFE7A3, alpha: 0.85).setFill()
        NSRect(x: tooth.bounds.minX + 4, y: tooth.bounds.maxY - 4,
               width: tooth.bounds.width - 8, height: 2.5).fill()
    }

    // Slider and pull, seated over the middle of the pile.
    NSGraphicsContext.saveGraphicsState()
    let sliderShadow = NSShadow()
    sliderShadow.shadowColor = NSColor.black.withAlphaComponent(0.40)
    sliderShadow.shadowBlurRadius = 18
    sliderShadow.shadowOffset = NSSize(width: 0, height: -8)
    sliderShadow.set()
    let slider = rounded(NSRect(x: 462, y: 566, width: 100, height: 96),
                         24)
    paint(slider, [color(0xFFF0B8), color(0xE8B84F), color(0xB47C1C)], angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    deepGold.setStroke()
    slider.lineWidth = 3
    slider.stroke()

    let slot = rounded(NSRect(x: 500, y: 584, width: 24, height: 46),
                       11)
    color(0x5E3E0C, alpha: 0.9).setFill()
    slot.fill()

    let stem = NSBezierPath(rect: NSRect(x: 502, y: 526, width: 20, height: 58))
    paint(stem, [color(0xF0C058), color(0xA9741B)], angle: -90)

    let ringRect = NSRect(x: 470, y: 436, width: 84, height: 100)

    // The strap runs behind the pull, so the opening needs its own shadowed
    // interior or the ring would read as a solid gold blob.
    let ringHole = NSBezierPath(ovalIn: ringRect.insetBy(dx: 9, dy: 9))
    color(0x3B2A0C).setFill()
    ringHole.fill()

    let ring = NSBezierPath(ovalIn: ringRect)
    ring.lineWidth = 17
    color(0x8A5E12).setStroke()
    ring.stroke()

    let innerRing = NSBezierPath(ovalIn: ringRect.insetBy(dx: 2.5, dy: 2.5))
    innerRing.lineWidth = 12
    gold.setStroke()
    innerRing.stroke()

    let glint = NSBezierPath()
    glint.appendArc(withCenter: NSPoint(x: 512, y: 486), radius: 38,
                    startAngle: 100, endAngle: 190)
    glint.lineWidth = 4
    color(0xFFF4CE).setStroke()
    glint.stroke()

    // Thin inner rim keeps the squircle crisp at large sizes.
    let rimPath = rounded(full.insetBy(dx: 49, dy: 49), 211)
    color(0xFFFFFF, alpha: 0.10).setStroke()
    rimPath.lineWidth = 3
    rimPath.stroke()

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
