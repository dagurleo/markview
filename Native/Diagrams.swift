import AppKit
import MermaidRender

/// A ```mermaid block in a document. It shows as written until it is drawn, and stays
/// that way if it cannot be.
struct Diagram {
    let source: String
    /// How wide it may be drawn: a wider one is scaled down.
    let width: CGFloat
    /// The page's colours and text size, which the drawing takes.
    let theme: Theme
    /// The paragraph the drawing takes the place of the code with.
    let block: NSParagraphStyle
    /// The Markdown it was written as, which is what copying it gives.
    let written: String

    /// Diagrams with the same key are drawn the same.
    var key: String { "\(theme.palette.id)|\(theme.bodySize)|\(width)|\(source)" }
}

/// Mermaid diagrams, drawn natively by MermaidKit (Vendor/MermaidKit) on a background
/// queue, in the page's own colours. Each comes back as a vector image that draws its
/// light or dark version to suit wherever it is drawn.
///
/// MermaidKit draws all of Mermaid's diagram types in a few milliseconds each with no
/// web view; Mermaid itself took a 180 MB web process and up to a second. Its look is
/// its own rather than Mermaid's.
enum Diagrams {
    /// Attribute key marking a diagram's code until it is drawn, whose value is its index.
    static let placeholder = NSAttributedString.Key("MarkviewDiagram")

    private static let queue = DispatchQueue(label: "com.dagurleo.markview.diagrams", qos: .userInitiated)

    /// Draws the diagrams a few at a time and calls back on the main thread after each few
    /// with the drawings so far, nil for one MermaidKit cannot read. Returning false stops the rest.
    static func draw(_ diagrams: [Diagram], completion: @escaping ([NSImage?]) -> Bool) {
        queue.async {
            var drawings = [NSImage?](repeating: nil, count: diagrams.count)
            for start in stride(from: 0, to: diagrams.count, by: 8) {
                for index in start..<min(start + 8, diagrams.count) { drawings[index] = draw(diagrams[index]) }
                let wanted = DispatchQueue.main.sync { completion(drawings) }
                guard wanted else { return }
            }
        }
    }

    private static func draw(_ diagram: Diagram) -> NSImage? {
        guard let light = page(diagram, dark: false), let dark = page(diagram, dark: true) else { return nil }
        let size = light.page.getBoxRect(.mediaBox).size
        guard size.width > 0, size.height > 0 else { return nil }
        // MermaidKit sets text at 12 points, small beside GitHub's 16; a quarter larger reads alike.
        let scale = min(1.25 * diagram.theme.scale, diagram.width / size.width)
        let image = NSImage(size: NSSize(width: size.width * scale, height: size.height * scale), flipped: false) { destination in
            let isDark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let page = (isDark ? dark : light).page
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let box = page.getBoxRect(.mediaBox)
            context.saveGState()
            context.translateBy(x: destination.minX, y: destination.minY)
            context.scaleBy(x: destination.width / box.width, y: destination.height / box.height)
            context.drawPDFPage(page)
            context.restoreGState()
            return true
        }
        // Kept as a bitmap a diagram would hold 10 MB on a Retina screen; drawn each time it takes a few milliseconds.
        image.cacheMode = .never
        return image
    }

    /// One version of a diagram as a single-page PDF. The document is kept with its page,
    /// which does not keep its document alive.
    private static func page(_ diagram: Diagram, dark: Bool) -> (document: CGPDFDocument, page: CGPDFPage)? {
        guard let data = MermaidRenderer.pdfData(source: diagram.source, theme: theme(diagram.theme, dark: dark)),
              let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider),
              let page = document.page(at: 1) else { return nil }
        return (document, page)
    }

    /// MermaidKit's own theme takes the system accent colour; this one takes the page's
    /// text, link, border and background colours.
    private static func theme(_ page: Theme, dark: Bool) -> DiagramTheme {
        var ink = NSColor.black, link = NSColor.blue, border = NSColor.gray, background = NSColor.white
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            func fixed(_ color: NSColor) -> NSColor { color.usingColorSpace(.sRGB) ?? color }
            ink = fixed(page.text)
            link = fixed(page.link)
            border = fixed(page.border)
            background = fixed(page.background)
        }
        return DiagramTheme(ink: ink, secondaryTextColor: ink.withAlphaComponent(0.55), tertiaryTextColor: ink.withAlphaComponent(0.38),
                            canvas: background, accent: link, hairline: border, prefersDark: dark)
    }
}
