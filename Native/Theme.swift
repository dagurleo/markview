import AppKit

/// The colours, fonts and sizes of a rendered document. The default is after GitHub's
/// page; the Settings window changes the palette, the fonts, the text size, the line
/// length and the line spacing (see Settings).
///
/// A theme is a value, read once for each render: large documents render on a
/// background thread, and a render must not see the settings change halfway.
struct Theme: Equatable {
    let palette: Palette
    /// The size of body text. Everything else on the page is sized in proportion to it,
    /// from GitHub's page with 16-point text.
    let bodySize: CGFloat
    /// A font family for text, "" for the system font, or "New York" for the system's serif.
    let textFont: String
    /// A font family for code, or "" for SF Mono.
    let codeFont: String
    /// The widest the text column grows.
    let columnWidth: CGFloat
    /// The line height of paragraphs, as a multiple of their font's.
    let lineSpacing: CGFloat

    init(palette: Palette = .github, bodySize: CGFloat = 16, textFont: String = "", codeFont: String = "",
         columnWidth: CGFloat = 736, lineSpacing: CGFloat = 1.3) {
        self.palette = palette
        self.bodySize = bodySize
        self.textFont = textFont
        self.codeFont = codeFont
        self.columnWidth = columnWidth
        self.lineSpacing = lineSpacing
        func color(_ pair: Palette.Pair) -> NSColor { Theme.color(pair.light, pair.dark) }
        background = color(palette.background)
        text = color(palette.text)
        muted = color(palette.muted)
        border = color(palette.border)
        subtle = color(palette.subtle)
        link = color(palette.link)
        mark = color(palette.mark)
        abstract = color(palette.abstract)
        alerts = [
            "NOTE": ("Note", color(palette.note)), "TIP": ("Tip", color(palette.tip)),
            "IMPORTANT": ("Important", color(palette.important)), "WARNING": ("Warning", color(palette.warning)),
            "CAUTION": ("Caution", color(palette.caution)),
        ]
        keyword = color(palette.keyword)
        title = color(palette.title)
        literal = color(palette.literal)
        string = color(palette.string)
        comment = color(palette.comment)
        builtin = color(palette.builtin)
        tag = color(palette.tag)
    }

    static func == (a: Theme, b: Theme) -> Bool {
        a.palette.id == b.palette.id && a.bodySize == b.bodySize && a.textFont == b.textFont && a.codeFont == b.codeFont
            && a.columnWidth == b.columnWidth && a.lineSpacing == b.lineSpacing
    }

    /// A colour that takes its light or dark version from the appearance it is drawn in.
    static func color(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? rgb(dark) : rgb(light) }
    }

    static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }

    let background, text, muted, border, subtle, link, mark: NSColor
    let alerts: [String: (title: String, color: NSColor)]
    private let abstract: NSColor

    /// A callout's title and colour: GitHub's five alerts, plus the kinds Obsidian adds.
    func callout(_ kind: String) -> (title: String, color: NSColor) {
        let key = kind.uppercased()
        if let alert = alerts[key] { return alert }
        let title = kind.prefix(1).uppercased() + kind.dropFirst().lowercased()
        switch key {
        case "ABSTRACT", "SUMMARY", "TLDR": return ("Abstract", abstract)
        case "HINT": return alerts["TIP"]!
        case "SUCCESS", "CHECK", "DONE": return (title, alerts["TIP"]!.color)
        case "QUESTION", "HELP", "FAQ": return (title, alerts["WARNING"]!.color)
        case "ATTENTION": return alerts["WARNING"]!
        case "FAILURE", "FAIL", "MISSING", "DANGER", "ERROR", "BUG": return (title, alerts["CAUTION"]!.color)
        case "EXAMPLE": return (title, alerts["IMPORTANT"]!.color)
        case "QUOTE", "CITE": return (title, muted)
        default: return (title, alerts["NOTE"]!.color)
        }
    }

    let keyword, title, literal, string, comment, builtin, tag: NSColor

    /// How much larger than GitHub's page this one is.
    var scale: CGFloat { bodySize / 16 }
    /// A length on GitHub's page, on this one.
    func scaled(_ points: CGFloat) -> CGFloat { points * scale }
    /// The widest a formula or diagram may be drawn: the column, less the 5 points the text
    /// container keeps clear on either side. Wider ones are scaled down.
    var figureWidth: CGFloat { columnWidth - 10 }
    var headingSizes: [CGFloat] { [32, 24, 20, 16, 14, 13.6].map(scaled) }

    private static var fonts: [String: NSFont] = [:]
    private static let fontsLock = NSLock()

    /// Called from the background thread that renders large documents as well as the main one.
    func font(size: CGFloat, bold: Bool = false, italic: Bool = false, mono: Bool = false) -> NSFont {
        Theme.font(family: mono ? codeFont : textFont, size: size, bold: bold, italic: italic, mono: mono)
    }

    /// Drawings (see NativeRenderer.drawing) are always in SF Mono: their lines only join, and
    /// the characters it lacks only line up, in the font they were measured for.
    static func drawingFont(size: CGFloat) -> NSFont { font(family: "", size: size, bold: false, italic: false, mono: true) }

    private static func font(family: String, size: CGFloat, bold: Bool, italic: Bool, mono: Bool) -> NSFont {
        let key = "\(family)-\(size)-\(bold)-\(italic)-\(mono)"
        fontsLock.lock()
        defer { fontsLock.unlock() }
        if let cached = fonts[key] { return cached }
        let weight: NSFont.Weight = bold ? .semibold : .regular
        var font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
        if family == "New York", let serif = font.fontDescriptor.withDesign(.serif) {
            font = NSFont(descriptor: serif, size: size) ?? font
        } else if !family.isEmpty {
            // A family without a bold or an italic face goes without; one that is not installed gives way to the system font.
            let manager = NSFontManager.shared
            let traits: [NSFontTraitMask] = [[bold ? .boldFontMask : [], italic ? .italicFontMask : []], bold ? .boldFontMask : [], []]
            if let found = traits.lazy.compactMap({ manager.font(withFamily: family, traits: $0, weight: $0.contains(.boldFontMask) ? 9 : 5, size: size) }).first {
                fonts[key] = found
                return found
            }
        }
        if italic, let slanted = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.italic), size: size) { font = slanted }
        fonts[key] = font
        return font
    }
}
