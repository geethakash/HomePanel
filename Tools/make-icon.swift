// Draws the HomePanel app icon at every size into the asset catalog.
//
//   swift Tools/make-icon.swift HomePanel/Assets.xcassets/AppIcon.appiconset

import AppKit

// HomePanel app icon: a deep blue squircle, a frosted glass card, a white house with a warm glow.
let canvas: CGFloat = 1024

func render(size px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    let scale = CGFloat(px) / canvas
    cg.scaleBy(x: scale, y: scale)

    // macOS icon grid: 824 pt squircle centred on the 1024 canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    // Drop shadow under the squircle.
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor(white: 0, alpha: 0.35).cgColor)
    NSColor(red: 0.08, green: 0.11, blue: 0.27, alpha: 1).setFill()
    squircle.fill()
    cg.restoreGState()

    // Background gradient, night blue to indigo.
    cg.saveGState()
    squircle.addClip()
    let bg = NSGradient(colors: [
        NSColor(red: 0.20, green: 0.33, blue: 0.78, alpha: 1),
        NSColor(red: 0.10, green: 0.14, blue: 0.42, alpha: 1),
        NSColor(red: 0.05, green: 0.07, blue: 0.22, alpha: 1),
    ])!
    bg.draw(in: body, angle: -90)

    // Soft light from the top edge.
    let sheen = NSGradient(colors: [NSColor(white: 1, alpha: 0.18), NSColor(white: 1, alpha: 0)])!
    sheen.draw(in: CGRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)

    // Warm glow behind the house.
    let glowCenter = CGPoint(x: 512, y: 470)
    let glow = NSGradient(colors: [
        NSColor(red: 0.55, green: 0.70, blue: 1.0, alpha: 0.30),
        NSColor(red: 0.55, green: 0.70, blue: 1.0, alpha: 0.0),
    ])!
    glow.draw(fromCenter: glowCenter, radius: 0, toCenter: glowCenter, radius: 340, options: [])

    // Frosted glass card.
    let card = CGRect(x: 232, y: 250, width: 560, height: 470)
    let cardPath = NSBezierPath(roundedRect: card, xRadius: 92, yRadius: 92)
    NSColor(white: 1, alpha: 0.14).setFill()
    cardPath.fill()
    let cardSheen = NSGradient(colors: [NSColor(white: 1, alpha: 0.22), NSColor(white: 1, alpha: 0.02)])!
    cardSheen.draw(in: cardPath, angle: -90)
    NSColor(white: 1, alpha: 0.42).setStroke()
    cardPath.lineWidth = 5
    cardPath.stroke()

    // House glyph (SF Symbol), white, with a warm window glow.
    let config = NSImage.SymbolConfiguration(pointSize: 300, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let house = NSImage(systemSymbolName: "house.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config)
    {
        let size = house.size
        let fit = min(330 / size.width, 290 / size.height)
        let w = size.width * fit, h = size.height * fit
        let rect = CGRect(x: 512 - w / 2, y: 485 - h / 2 - 10, width: w, height: h)
        // A lit doorway: amber light behind the house shows through the door cut-out.
        // Just inside the door cut-out (measured on the 1024 canvas, bottom-left origin).
        let door = CGRect(x: 480, y: 380, width: 64, height: 72)
        cg.saveGState()
        cg.setShadow(offset: .zero, blur: 16, color: NSColor(red: 1, green: 0.66, blue: 0.2, alpha: 0.8).cgColor)
        NSColor(red: 1.0, green: 0.74, blue: 0.28, alpha: 1).setFill()
        NSBezierPath(roundedRect: door, xRadius: 8, yRadius: 8).fill()
        cg.restoreGState()
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: NSColor(white: 0, alpha: 0.35).cgColor)
        house.draw(in: rect)
        cg.restoreGState()
    }
    cg.restoreGState()

    // Hairline edge on the squircle.
    NSColor(white: 1, alpha: 0.16).setStroke()
    squircle.lineWidth = 3
    squircle.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
var images: [[String: String]] = []
for base in [16, 32, 128, 256, 512] {
    for scaleFactor in [1, 2] {
        let px = base * scaleFactor
        let name = "icon_\(base)x\(base)\(scaleFactor == 2 ? "@2x" : "").png"
        try render(size: px).representation(using: .png, properties: [:])!.write(to: out.appending(path: name))
        images.append(["idiom": "mac", "size": "\(base)x\(base)", "scale": "\(scaleFactor)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: out.appending(path: "Contents.json"))
print("wrote \(images.count) icons")
