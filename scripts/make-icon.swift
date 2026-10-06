// Draws the app icon and the document icon Finder shows on Markdown files, and
// writes Resources/AppIcon.icns and Resources/Document.icns.
// Run from the project root: swift scripts/make-icon.swift
import AppKit

// Everything below is laid out on Apple's 1024pt icon grid.

func drawAppIcon() {
    let plate = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
                             xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(srgbRed: 0.24, green: 0.26, blue: 0.32, alpha: 1),
               ending: NSColor(srgbRed: 0.09, green: 0.10, blue: 0.13, alpha: 1))!
        .draw(in: plate, angle: -90)

    let mark = NSAttributedString(string: "M↓", attributes: [
        .font: NSFont.systemFont(ofSize: 380, weight: .heavy),
        .foregroundColor: NSColor.white,
        .kern: -8,
    ])
    let size = mark.size()
    mark.draw(at: NSPoint(x: 512 - size.width / 2, y: 512 - size.height / 2))
}

/// A sheet of paper with a folded corner, carrying the app icon. `pixel` is the
/// size of one output pixel on the grid, so outlines stay visible at 16px.
func drawDocumentIcon(pixel: CGFloat) {
    let page = NSRect(x: 184, y: 72, width: 656, height: 880)
    let radius: CGFloat = 44, fold: CGFloat = 230

    let sheet = NSBezierPath()
    sheet.move(to: NSPoint(x: page.minX + radius, y: page.minY))
    sheet.appendArc(from: NSPoint(x: page.maxX, y: page.minY), to: NSPoint(x: page.maxX, y: page.maxY), radius: radius)
    sheet.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
    sheet.line(to: NSPoint(x: page.maxX - fold, y: page.maxY))
    sheet.appendArc(from: NSPoint(x: page.minX, y: page.maxY), to: NSPoint(x: page.minX, y: page.minY), radius: radius)
    sheet.appendArc(from: NSPoint(x: page.minX, y: page.minY), to: NSPoint(x: page.maxX, y: page.minY), radius: radius)
    sheet.close()

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor.white.setFill()
    sheet.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(white: 0.99, alpha: 1), ending: NSColor(white: 0.91, alpha: 1))!
        .draw(in: sheet, angle: -90)

    let flap = NSBezierPath()
    flap.move(to: NSPoint(x: page.maxX - fold, y: page.maxY))
    flap.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
    flap.appendArc(from: NSPoint(x: page.maxX - fold, y: page.maxY - fold),
                   to: NSPoint(x: page.maxX - fold, y: page.maxY), radius: radius)
    flap.close()
    NSGradient(starting: NSColor(white: 0.97, alpha: 1), ending: NSColor(white: 0.80, alpha: 1))!
        .draw(in: flap, angle: -135)

    NSColor.black.withAlphaComponent(0.22).setStroke()
    for outline in [sheet, flap] {
        outline.lineWidth = max(3, pixel * 0.75)
        outline.stroke()
    }

    let scale: CGFloat = 0.46
    let placement = NSAffineTransform()
    placement.translateX(by: 512 - 512 * scale, yBy: 470 - 512 * scale)
    placement.scale(by: scale)
    placement.concat()
    drawAppIcon()
}

func render(pixels: Int, _ draw: (_ pixel: CGFloat) -> Void) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(pixels) / 1024
    NSAffineTransform(transform: AffineTransform(scale: scale)).concat()
    draw(1 / scale)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func write(_ name: String, _ draw: (_ pixel: CGFloat) -> Void) throws {
    let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(name).iconset")
    try? FileManager.default.removeItem(at: iconset)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        try render(pixels: points, draw).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
        try render(pixels: points * 2, draw).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
    }

    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/\(name).icns"]
    try iconutil.run()
    iconutil.waitUntilExit()
    if iconutil.terminationStatus != 0 { exit(iconutil.terminationStatus) }
}

try write("AppIcon") { _ in drawAppIcon() }
try write("Document", drawDocumentIcon)
