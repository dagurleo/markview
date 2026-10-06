import AppKit

/// Colours and sizes of a rendered document, after GitHub's.
enum Theme {
    static func color(_ light: UInt32, _ dark: UInt32) -> NSColor {
        func rgb(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                    blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        }
        return NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? rgb(dark) : rgb(light) }
    }

    static let background = color(0xffffff, 0x1c1c1e)
    static let text = color(0x1f2328, 0xe4e4e7)
    static let muted = color(0x656d76, 0x9b9ba3)
    static let border = color(0xd8dee4, 0x3a3a40)
    static let subtle = color(0xf6f8fa, 0x27272b)
    static let link = color(0x0969da, 0x58a6ff)
    static let alerts: [String: (title: String, color: NSColor)] = [
        "NOTE": ("Note", color(0x0969da, 0x58a6ff)), "TIP": ("Tip", color(0x1a7f37, 0x3fb950)),
        "IMPORTANT": ("Important", color(0x8250df, 0xa371f7)), "WARNING": ("Warning", color(0x9a6700, 0xd29922)),
        "CAUTION": ("Caution", color(0xcf222e, 0xf85149)),
    ]
    static let mark = color(0xfff8c5, 0x5a4a00)

    /// A callout's title and colour: GitHub's five alerts, plus the kinds Obsidian adds.
    static func callout(_ kind: String) -> (title: String, color: NSColor) {
        let key = kind.uppercased()
        if let alert = alerts[key] { return alert }
        let title = kind.prefix(1).uppercased() + kind.dropFirst().lowercased()
        switch key {
        case "ABSTRACT", "SUMMARY", "TLDR": return ("Abstract", color(0x0e7490, 0x22d3ee))
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

    static let keyword = color(0xcf222e, 0xff7b72)
    static let title = color(0x8250df, 0xd2a8ff)
    static let literal = color(0x0550ae, 0x79c0ff)
    static let string = color(0x0a3069, 0xa5d6ff)
    static let comment = color(0x6e7781, 0x8b949e)
    static let builtin = color(0x953800, 0xffa657)
    static let tag = color(0x116329, 0x7ee787)

    static let bodySize: CGFloat = 16
    static let columnWidth: CGFloat = 736
    /// The widest a formula or diagram may be drawn: the column, less the 5 points the text
    /// container keeps clear on either side. Wider ones are scaled down.
    static let figureWidth = columnWidth - 10
    static let headingSizes: [CGFloat] = [32, 24, 20, 16, 14, 13.6]

    private static var fonts: [String: NSFont] = [:]
    private static let fontsLock = NSLock()

    /// Called from the background thread that renders large documents as well as the main one.
    static func font(size: CGFloat, bold: Bool = false, italic: Bool = false, mono: Bool = false) -> NSFont {
        let key = "\(size)-\(bold)-\(italic)-\(mono)"
        fontsLock.lock()
        defer { fontsLock.unlock() }
        if let cached = fonts[key] { return cached }
        let weight: NSFont.Weight = bold ? .semibold : .regular
        var font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
        if italic, let slanted = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.italic), size: size) { font = slanted }
        fonts[key] = font
        return font
    }
}
