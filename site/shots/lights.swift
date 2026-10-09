// Paints a window snapshot's traffic lights in their active colours. Snapshots are taken
// while another app is active, so the window shows them grey.
// usage: swift site/shots/lights.swift <in.png> <out.png>
import AppKit

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard let snapshot = NSBitmapImageRep(data: try Data(contentsOf: input))?.cgImage else { exit(1) }
// A fresh 8-bit bitmap, drawn in pixels: the snapshot's own format may not take drawing.
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: snapshot.width, pixelsHigh: snapshot.height, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current!.cgContext.draw(snapshot, in: CGRect(x: 0, y: 0, width: snapshot.width, height: snapshot.height))
// The snapshot is at twice the size: buttons 14 pt across, 23 pt apart, 9 pt from the corner.
let height = CGFloat(rep.pixelsHigh)
let lights: [(fill: UInt32, edge: UInt32)] = [(0xff5f57, 0xe14640), (0xfebc2e, 0xdfa023), (0x28c840, 0x1ead2f)]
for (index, light) in lights.enumerated() {
    func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
    let rect = NSRect(x: 18 + CGFloat(index) * 46, y: height - 46, width: 28, height: 28)
    color(light.fill).setFill()
    NSBezierPath(ovalIn: rect).fill()
    color(light.edge).setStroke()
    let edge = NSBezierPath(ovalIn: rect.insetBy(dx: 0.75, dy: 0.75))
    edge.lineWidth = 1.5
    edge.stroke()
}
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: output)
