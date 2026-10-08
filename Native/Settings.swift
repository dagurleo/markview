import AppKit

/// What the reader chose in the Settings window, kept in the app's defaults. The Quick Look
/// extension reads the app's defaults rather than its own, which its sandbox allows by an
/// exception (QuickLook/QuickLook.entitlements), so previews look like the app's windows.
///
/// For one launch any of them can be given after the file, as `-textSize 20`.
enum Settings {
    static let domain = "com.dagurleo.markview"
    static let defaults = Bundle.main.bundleIdentifier == domain ? UserDefaults.standard : UserDefaults(suiteName: domain) ?? .standard

    enum Key {
        static let theme = "theme", appearance = "appearance", textSize = "textSize", textFont = "textFont",
                   codeFont = "codeFont", lineLength = "lineLength", lineSpacing = "lineSpacing"
        static let all = [theme, appearance, textSize, textFont, codeFont, lineLength, lineSpacing]
    }

    static let defaultTheme = Theme()

    /// The theme the settings describe. Values out of range are brought into it.
    static var theme: Theme {
        func number(_ key: String, _ fallback: CGFloat, _ range: ClosedRange<CGFloat>) -> CGFloat {
            guard defaults.object(forKey: key) != nil else { return fallback }
            return min(max(CGFloat(defaults.double(forKey: key)), range.lowerBound), range.upperBound)
        }
        return Theme(palette: Palette.named(defaults.string(forKey: Key.theme)),
                     bodySize: number(Key.textSize, defaultTheme.bodySize, 10...32),
                     textFont: defaults.string(forKey: Key.textFont) ?? "",
                     codeFont: defaults.string(forKey: Key.codeFont) ?? "",
                     columnWidth: number(Key.lineLength, defaultTheme.columnWidth, 400...2000),
                     lineSpacing: number(Key.lineSpacing, defaultTheme.lineSpacing, 1...2.5))
    }

    /// Light or dark whatever the system shows, or nil to follow it.
    static var appearance: NSAppearance? {
        switch defaults.string(forKey: Key.appearance) {
        case "light": NSAppearance(named: .aqua)
        case "dark": NSAppearance(named: .darkAqua)
        default: nil
        }
    }
}
