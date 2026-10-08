import AppKit
import JavaScriptCore

/// Syntax colours from the vendored highlight.js, run by JavaScriptCore inside
/// the app. No web view is involved.
final class HighlightEngine {
    private let tokens: JSValue
    private let theme: Theme

    init?(theme: Theme) {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("vendor/highlight.min.js"),
              let source = try? String(contentsOf: url, encoding: .utf8), let context = JSContext() else { return nil }
        context.evaluateScript(source)
        // Flattens highlight.js's HTML into [text, class, text, class, …].
        context.evaluateScript("""
            function markviewTokens(code, language) {
              if (!hljs.getLanguage(language)) return null;
              const html = hljs.highlight(code, { language, ignoreIllegals: true }).value;
              const entities = { '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#x27;': "'" };
              const out = [], open = [];
              for (const part of html.matchAll(/<span class="([^"]*)">|(<\\/span>)|([^<]+)/g)) {
                if (part[1] !== undefined) open.push(part[1]);
                else if (part[2]) open.pop();
                else out.push(part[3].replace(/&(?:amp|lt|gt|quot|#x27);/g, (entity) => entities[entity]), open[open.length - 1] || '');
              }
              return out;
            }
            """)
        guard let tokens = context.objectForKeyedSubscript("markviewTokens"), tokens.isObject else { return nil }
        self.tokens = tokens
        self.theme = theme
    }

    func highlight(_ code: NSMutableAttributedString, in range: NSRange, language: String?) {
        guard let language, let source = Optional((code.string as NSString).substring(with: range)),
              let pieces = tokens.call(withArguments: [source, language])?.toArray() as? [String] else { return }
        // Colour nothing rather than the wrong characters if the pieces do not add up to the code.
        guard stride(from: 0, to: pieces.count, by: 2).reduce(0, { $0 + (pieces[$1] as NSString).length }) == range.length else { return }
        var location = range.location
        for index in stride(from: 0, to: pieces.count, by: 2) {
            let length = (pieces[index] as NSString).length
            if let color = color(for: pieces[index + 1]) {
                code.addAttribute(.foregroundColor, value: color, range: NSRange(location: location, length: length))
            }
            location += length
        }
    }

    /// Token colours from the theme, grouped as GitHub groups them.
    private func color(for scope: String) -> NSColor? {
        let name = scope.split(separator: " ").first.map(String.init) ?? ""
        switch name {
        case "hljs-keyword", "hljs-doctag", "hljs-template-tag", "hljs-template-variable", "hljs-type", "hljs-deletion": return theme.keyword
        case "hljs-variable": return scope.contains("language_") ? theme.keyword : theme.literal
        case "hljs-title": return theme.title
        case "hljs-attr", "hljs-attribute", "hljs-literal", "hljs-meta", "hljs-number", "hljs-operator", "hljs-selector-attr",
             "hljs-selector-class", "hljs-selector-id", "hljs-section": return theme.literal
        case "hljs-string", "hljs-regexp": return theme.string
        case "hljs-built_in", "hljs-symbol": return theme.builtin
        case "hljs-comment", "hljs-code", "hljs-formula": return theme.comment
        case "hljs-name", "hljs-quote", "hljs-selector-tag", "hljs-selector-pseudo", "hljs-addition": return theme.tag
        default: return nil
        }
    }
}
