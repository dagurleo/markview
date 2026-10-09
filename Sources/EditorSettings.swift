import Foundation

/// How the editor behaves (Settings > Editor), kept in the app's defaults like the rest of the
/// settings. The page does not depend on any of it.
struct EditorSettings: Equatable {
    enum Key {
        static let font = "editorFont", lineNumbers = "editorLineNumbers", wraps = "editorWraps", indentWithTabs = "editorIndentWithTabs",
                   indentWidth = "editorIndentWidth", spelling = "editorSpelling", smartQuotes = "editorSmartQuotes",
                   smartDashes = "editorSmartDashes", textReplacement = "editorTextReplacement"
        static let all = [font, lineNumbers, wraps, indentWithTabs, indentWidth, spelling, smartQuotes, smartDashes, textReplacement]
    }

    /// A font family, or "" for the code font the page uses.
    var font = ""
    var lineNumbers = false
    /// Whether long lines wrap at the edge of the editor, or run on and scroll sideways.
    var wraps = true
    var indentWithTabs = false
    var indentWidth = 4
    var spelling = true
    // Markdown is written for code as much as prose, so nothing changes what is typed unless asked.
    var smartQuotes = false
    var smartDashes = false
    var textReplacement = false

    static var current: EditorSettings {
        let defaults = Settings.defaults
        var settings = EditorSettings()
        func flag(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key) }
        settings.font = defaults.string(forKey: Key.font) ?? ""
        settings.lineNumbers = flag(Key.lineNumbers, settings.lineNumbers)
        settings.wraps = flag(Key.wraps, settings.wraps)
        settings.indentWithTabs = flag(Key.indentWithTabs, settings.indentWithTabs)
        let width = defaults.integer(forKey: Key.indentWidth)
        settings.indentWidth = (1...8).contains(width) ? width : settings.indentWidth
        settings.spelling = flag(Key.spelling, settings.spelling)
        settings.smartQuotes = flag(Key.smartQuotes, settings.smartQuotes)
        settings.smartDashes = flag(Key.smartDashes, settings.smartDashes)
        settings.textReplacement = flag(Key.textReplacement, settings.textReplacement)
        return settings
    }

    /// What one step of indentation is: a tab, or so many spaces.
    var indent: String { indentWithTabs ? "\t" : String(repeating: " ", count: indentWidth) }
}
