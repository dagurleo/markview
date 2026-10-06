import AppKit
import SwaTex
import SwaTexRender

/// TeX math, laid out by SwaTex (Vendor/SwaTex): KaTeX's layout rules and fonts in Swift,
/// so formulas look as they do on a KaTeX page, with no web view and no script. A formula
/// takes about 25 µs to lay out, so math is drawn as the document is rendered, on
/// whichever thread renders it.
enum Math {
    /// KaTeX sets math at 1.21 times the size of the text around it.
    private static let scale: CGFloat = 1.21
    /// Formulas are laid out in this colour where they take the page's, and drawn in the
    /// page's text colour of the moment, light or dark. Colours a formula sets stay its own.
    private static let ink = SwaTex.Color(r: 0.01, g: 0.02, b: 0.03, a: 1)

    /// A formula as a vector image that draws itself in the colours of wherever it is drawn,
    /// with how far it reaches below the baseline, or nil if SwaTex cannot read it.
    /// A wider one than `width` is scaled down to it. A display formula with an equation
    /// number takes the whole width, the formula centred in it and the number at its right.
    /// Equations are numbered on from `equations`, which is left at the last number used.
    static func image(_ tex: String, display: Bool, size: CGFloat, width: CGFloat,
                      equations: inout Int) -> (image: NSImage, depth: CGFloat)? {
        let em = size * scale
        guard let list = try? SwaTexEngine.displayList(for: tex, style: display ? .display : .text, color: ink,
                                                       displayWidth: display ? Double(width / em) : nil, equations: &equations),
              list.width > 0 else { return nil }
        let fitted = min(1, width / (CGFloat(list.width) * em))
        let options = RenderOptions(fontSize: em * fitted, padding: 0)
        let metrics = DisplayListRenderer.metrics(for: list, options: options)
        // Taller than a few screens is no formula anyone wrote to read; it shows as written.
        guard metrics.height < 4000 else { return nil }
        let image = NSImage(size: NSSize(width: metrics.width, height: metrics.height), flipped: false) { destination in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.translateBy(x: destination.minX, y: destination.minY)
            context.scaleBy(x: destination.width / metrics.width, y: destination.height / metrics.height)
            DisplayListRenderer.draw(inked(list), in: context, options: options)
            context.restoreGState()
            return true
        }
        // Drawn each time rather than kept as a bitmap, so it follows the appearance and stays sharp at any zoom.
        image.cacheMode = .never
        return (image, display ? 0 : metrics.height - metrics.baseline)
    }

    /// The formula in the text colour of the appearance it is being drawn in.
    private static func inked(_ list: DisplayList) -> DisplayList {
        guard let text = Theme.text.usingColorSpace(.sRGB) else { return list }
        let color = SwaTex.Color(r: Float(text.redComponent), g: Float(text.greenComponent), b: Float(text.blueComponent),
                                 a: Float(text.alphaComponent))
        var inked = list
        inked.items = list.items.map { item in
            switch item {
            case let .glyphPath(x, y, scale, font, charCode, ink) where ink == Self.ink:
                .glyphPath(x: x, y: y, scale: scale, font: font, charCode: charCode, color: color)
            case let .line(x, y, width, thickness, ink, dashed) where ink == Self.ink:
                .line(x: x, y: y, width: width, thickness: thickness, color: color, dashed: dashed)
            case let .rect(x, y, width, height, ink) where ink == Self.ink:
                .rect(x: x, y: y, width: width, height: height, color: color)
            case let .path(x, y, commands, fill, ink) where ink == Self.ink:
                .path(x: x, y: y, commands: commands, fill: fill, color: color)
            default:
                item
            }
        }
        return inked
    }
}
