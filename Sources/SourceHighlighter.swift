import AppKit

/// Colours Markdown as it is written, in the editor: headings, emphasis, code, links, quotes and
/// lists, in the theme's colours, with the marks that make them faded.
///
/// It works a line at a time. What a line means can depend on the lines above it (inside a fenced
/// code block, front matter or a `$$` formula, a line is not Markdown), so each line carries the
/// state it leaves the next one in. After an edit only the lines touched are coloured again, and
/// the ones below them for as long as their state changes: typing a fence recolours the rest of
/// the document, typing a word recolours one line.
final class SourceHighlighter: NSObject, NSTextStorageDelegate {
    private(set) var theme: Theme
    /// Called after the characters change, not just their colours.
    var onTextChange: () -> Void = {}
    /// Until an editor shows the text, nothing is coloured.
    private(set) var isActive = false
    private weak var storage: NSTextStorage?

    init(storage: NSTextStorage, theme: Theme) {
        self.storage = storage
        self.theme = theme
        super.init()
        makeStyles()
        storage.delegate = self
    }

    /// Colours the whole text, as when an editor first shows it or the theme changes.
    func activate(theme: Theme) {
        guard let storage else { return }
        if isActive, theme == self.theme { return }
        self.theme = theme
        makeStyles()
        isActive = true
        storage.beginEditing()
        highlightLines(in: NSRange(location: 0, length: storage.length), of: storage, untilSettled: false)
        storage.endEditing()
        // Fonts are fixed lazily, for characters the code font lacks, over whatever range is still
        // unfixed when an attribute is next read: done now, or each keystroke would fix a large part.
        storage.ensureAttributesAreFixed(in: NSRange(location: 0, length: storage.length))
    }

    /// The attributes text is typed with before it is coloured.
    var typingAttributes: [NSAttributedString.Key: Any] { plain }

    /// Marks text that is not prose, such as code, addresses and tags, which spelling leaves alone.
    static let notProse = NSAttributedString.Key("MarkviewNotProse")

    // MARK: Editing

    // Before the text storage fixes its fonts, which gives characters the code font lacks, such as
    // emoji, a font that has them: colouring after that would take those fonts away again.
    func textStorage(_ textStorage: NSTextStorage, willProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), isActive else { return }
        highlightLines(in: editedRange, of: textStorage, untilSettled: true)
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        if editedMask.contains(.editedCharacters) { onTextChange() }
    }

    // MARK: Lines

    /// What the lines above leave a line inside of.
    private enum State: Equatable {
        case text
        /// A fenced code block opened by `count` of `mark` (` or ~).
        case fence(mark: unichar, count: Int)
        case frontMatter
        case math
        case comment

        /// Kept in the text as a number, which attributes compare reliably.
        var number: Int {
            switch self {
            case .text: 0
            case .frontMatter: 1
            case .math: 2
            case .comment: 3
            case .fence(let mark, let count): (mark == 96 ? 1_000 : 2_000) + count
            }
        }

        init(number: Int?) {
            switch number ?? 0 {
            case 1: self = .frontMatter
            case 2: self = .math
            case 3: self = .comment
            case let n where n > 2_000: self = .fence(mark: 126, count: n - 2_000)
            case let n where n > 1_000: self = .fence(mark: 96, count: n - 1_000)
            default: self = .text
            }
        }
    }

    /// Attribute on each line's characters: the state the line leaves the next one in.
    private static let stateKey = NSAttributedString.Key("MarkviewSourceState")

    private func state(at index: Int, in storage: NSTextStorage) -> State? {
        (storage.attribute(Self.stateKey, at: index, effectiveRange: nil) as? Int).map { State(number: $0) }
    }

    private func highlightLines(in range: NSRange, of storage: NSTextStorage, untilSettled: Bool) {
        // The storage's own string: `string` would copy the whole text at every keystroke.
        let text = storage.mutableString
        guard text.length > 0 else { return }
        var line = text.lineRange(for: NSRange(location: min(range.location, text.length - 1), length: 0))
        let end = min(NSMaxRange(range), text.length)
        var state = line.location == 0 ? State.text : (self.state(at: line.location - 1, in: storage) ?? .text)
        while true {
            // A line's end is the part of it least likely to be new.
            let previous = self.state(at: NSMaxRange(line) - 1, in: storage)
            let next = highlight(line: line, of: text, in: storage, from: state)
            state = next
            let lineEnd = NSMaxRange(line)
            guard lineEnd < text.length else { break }
            // Past the edit, a line that leaves the next where it was before means the rest is as it
            // was. The line just after an edit was part of an edited line if a line break was typed.
            if untilSettled ? lineEnd > end && previous == next : lineEnd >= end { break }
            line = text.lineRange(for: NSRange(location: lineEnd, length: 0))
        }
    }

    /// Colours one line, and gives the state it leaves the next one in.
    private func highlight(line: NSRange, of text: NSString, in storage: NSTextStorage, from state: State) -> State {
        let content = text.substring(with: line)
        let body = content.trimmingCharacters(in: .newlines)
        let bodyRange = NSRange(location: line.location, length: (body as NSString).length)
        storage.setAttributes(plain, range: line)
        var next = state

        func style(_ attributes: [NSAttributedString.Key: Any], _ range: NSRange) {
            storage.addAttributes(attributes, range: NSRange(location: line.location + range.location, length: range.length))
        }

        switch state {
        case .fence(let mark, let count):
            storage.addAttributes(codeBlock, range: bodyRange)
            if let close = Self.fence(in: body), close.mark == mark, close.count >= count, close.info.isEmpty {
                style(marker, close.range)
                next = .text
            }
        case .frontMatter:
            if body == "---" || body == "..." {
                storage.addAttributes(marker, range: bodyRange)
                next = .text
            } else if let colon = body.firstIndex(of: ":"), !body.hasPrefix(" ") {
                style(literal, NSRange(location: 0, length: body.utf16.distance(from: body.startIndex, to: colon)))
                style(string, NSRange(location: body.utf16.distance(from: body.startIndex, to: colon) + 1,
                                      length: body.utf16.distance(from: colon, to: body.endIndex) - 1))
            } else {
                storage.addAttributes(string, range: bodyRange)
            }
        case .math:
            storage.addAttributes(math, range: bodyRange)
            if body.trimmingCharacters(in: .whitespaces).hasSuffix("$$") { next = .text }
        case .comment:
            storage.addAttributes(comment, range: bodyRange)
            if body.contains("-->") { next = .text }
        case .text:
            next = highlightText(body, at: line.location, in: storage)
        }
        storage.addAttribute(Self.stateKey, value: next.number, range: line)
        return next
    }

    /// A line of Markdown, outside any block that hides it.
    private func highlightText(_ line: String, at location: Int, in storage: NSTextStorage) -> State {
        let ns = line as NSString
        let all = NSRange(location: 0, length: ns.length)
        func style(_ attributes: [NSAttributedString.Key: Any], _ range: NSRange) {
            guard range.location != NSNotFound, range.length > 0 else { return }
            storage.addAttributes(attributes, range: NSRange(location: location + range.location, length: range.length))
        }

        if location == 0, line == "---" {
            style(marker, all)
            return .frontMatter
        }
        if let open = Self.fence(in: line) {
            style(marker, open.range)
            if let info = open.infoRange { style(literal, info) }
            return .fence(mark: open.mark, count: open.count)
        }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("$$") {
            style(math, all)
            return trimmed.count > 2 && trimmed.hasSuffix("$$") ? .text : .math
        }
        if trimmed.hasPrefix("<!--") {
            style(comment, all)
            return trimmed.contains("-->") ? .text : .comment
        }
        // A code block indented by four spaces is only one after a blank line; telling needs the
        // lines above, and list items indent their own paragraphs, so they are left as text.

        if let match = Self.heading.firstMatch(in: line, range: all) {
            style(heading, all)
            style(marker, match.range(at: 1))
            return .text
        }
        if Self.rule.firstMatch(in: line, range: all) != nil {
            style(marker, all)
            return .text
        }
        var start = 0
        // Quote marks, then a list item's mark and its task box, each possibly inside the other.
        while true {
            let rest = NSRange(location: start, length: all.length - start)
            if let match = Self.quote.firstMatch(in: line, options: .anchored, range: rest) {
                style(quoteMark, match.range(at: 1))
                start = NSMaxRange(match.range)
            } else if let match = Self.listItem.firstMatch(in: line, options: .anchored, range: rest) {
                style(listMark, match.range(at: 1))
                style(listMark, match.range(at: 2))
                start = NSMaxRange(match.range)
            } else {
                break
            }
        }
        if Self.tableRow.firstMatch(in: line, range: all) != nil {
            for match in Self.pipe.matches(in: line, range: all) { style(marker, match.range) }
            if Self.tableRule.firstMatch(in: line, range: all) != nil { style(marker, all) }
        }
        if let match = Self.footnoteDefinition.firstMatch(in: line, options: .anchored, range: all) { style(link, match.range(at: 1)) }
        highlightInline(line, from: start, at: location, in: storage)
        return .text
    }

    /// Code spans first: nothing inside one is Markdown. Then links, emphasis and the rest.
    private func highlightInline(_ line: String, from start: Int, at location: Int, in storage: NSTextStorage) {
        let ns = line as NSString
        let range = NSRange(location: start, length: ns.length - start)
        guard range.length > 0 else { return }
        var taken = IndexSet()
        func style(_ attributes: [NSAttributedString.Key: Any], _ range: NSRange) {
            guard range.location != NSNotFound, range.length > 0 else { return }
            storage.addAttributes(attributes, range: NSRange(location: location + range.location, length: range.length))
        }
        func free(_ range: NSRange) -> Bool { !taken.intersects(integersIn: range.location..<NSMaxRange(range)) }
        func take(_ range: NSRange) { taken.insert(integersIn: range.location..<NSMaxRange(range)) }

        for match in Self.codeSpan.matches(in: line, range: range) {
            style(code, match.range)
            style(marker, match.range(at: 1))
            style(marker, match.range(at: 3))
            take(match.range)
        }
        for match in Self.inlineMath.matches(in: line, range: range) where free(match.range) {
            style(math, match.range)
            take(match.range)
        }
        for match in Self.htmlTag.matches(in: line, range: range) where free(match.range) {
            style(tag, match.range)
            take(match.range)
        }
        for match in Self.wikiLink.matches(in: line, range: range) where free(match.range) {
            style(marker, match.range)
            style(link, match.range(at: 1))
            take(match.range)
        }
        for match in Self.footnoteReference.matches(in: line, range: range) where free(match.range) {
            style(link, match.range)
            take(match.range)
        }
        for match in Self.link.matches(in: line, range: range) where free(match.range) {
            style(marker, match.range)
            style(link, match.range(at: 2))
            // A link's words are prose, though the marks and the address around them are not.
            storage.removeAttribute(Self.notProse, range: NSRange(location: location + match.range(at: 2).location, length: match.range(at: 2).length))
            take(match.range(at: 1))
            take(match.range(at: 3))
        }
        for match in Self.autolink.matches(in: line, range: range) where free(match.range) {
            style(link, match.range)
            take(match.range)
        }
        for match in Self.strong.matches(in: line, range: range) where free(match.range(at: 1)) && free(match.range(at: 3)) {
            style(bold, match.range)
            style(marker, match.range(at: 1))
            style(marker, match.range(at: 3))
        }
        for match in Self.emphasis.matches(in: line, range: range) where free(match.range(at: 1)) && free(match.range(at: 3)) {
            style(italic, match.range(at: 2))
            style(marker, match.range(at: 1))
            style(marker, match.range(at: 3))
        }
        for match in Self.strikethrough.matches(in: line, range: range) where free(match.range) {
            style([.strikethroughStyle: NSUnderlineStyle.single.rawValue], match.range(at: 2))
            style(marker, match.range(at: 1))
            style(marker, match.range(at: 3))
        }
        for match in Self.highlight.matches(in: line, range: range) where free(match.range) {
            style([.backgroundColor: theme.mark], match.range(at: 2))
            style(marker, match.range(at: 1))
            style(marker, match.range(at: 3))
        }
    }

    /// A fence line: up to three spaces, then three or more backticks or tildes, then the info
    /// string (a backtick fence's info has no backticks).
    private static func fence(in line: String) -> (mark: unichar, count: Int, range: NSRange, info: String, infoRange: NSRange?)? {
        let ns = line as NSString
        var index = 0
        while index < ns.length, index < 3, ns.character(at: index) == 32 { index += 1 }
        guard index < ns.length else { return nil }
        let mark = ns.character(at: index)
        guard mark == 96 || mark == 126 else { return nil }   // ` or ~
        var end = index
        while end < ns.length, ns.character(at: end) == mark { end += 1 }
        let count = end - index
        guard count >= 3 else { return nil }
        let rest = ns.substring(from: end)
        let info = rest.trimmingCharacters(in: .whitespaces)
        if mark == 96, info.contains("`") { return nil }
        let infoStart = end + ((rest as NSString).length - (rest.drop { $0 == " " || $0 == "\t" } as Substring).utf16.count)
        return (mark, count, NSRange(location: index, length: count), info,
                info.isEmpty ? nil : NSRange(location: infoStart, length: (info as NSString).length))
    }

    // MARK: Patterns

    private static func pattern(_ source: String) -> NSRegularExpression { try! NSRegularExpression(pattern: source) }

    private static let heading = pattern(#"^ {0,3}(#{1,6})(?:[ \t]|$)"#)
    private static let rule = pattern(#"^ {0,3}(?:(?:\*[ \t]*){3,}|(?:-[ \t]*){3,}|(?:_[ \t]*){3,}|={3,})$"#)
    private static let quote = pattern(#"[ ]{0,3}(>)[ ]?"#)
    private static let listItem = pattern(#"[ \t]*([-+*]|\d{1,9}[.)])[ \t]+(\[[ xX]\](?=[ \t]))?"#)
    private static let tableRow = pattern(#"^\s*\|.*\|\s*$"#)
    private static let tableRule = pattern(#"^\s*\|?\s*:?-+:?\s*(?:\|\s*:?-+:?\s*)+\|?\s*$"#)
    private static let pipe = pattern(#"(?<!\\)\|"#)
    private static let footnoteDefinition = pattern(#"\s{0,3}(\[\^[^\]\s]+\]:)"#)
    private static let codeSpan = pattern(#"(`+)(?!`)(.+?)(?<!`)(\1)(?!`)"#)
    private static let inlineMath = pattern(#"(?<![\\$\w])\$(?![\s$])[^$\n]*?(?<![\s\\])\$(?![\w$])"#)
    private static let htmlTag = pattern(#"</?[A-Za-z][A-Za-z0-9-]*(?:\s+[^<>]*)?/?>|<!--.*?-->"#)
    private static let wikiLink = pattern(#"\[\[([^\]\n]+)\]\]"#)
    private static let footnoteReference = pattern(#"\[\^[^\]\s]+\]"#)
    private static let link = pattern(#"(!?\[)((?:[^\[\]]|\[[^\[\]]*\])*)(\]\([^)\s]*(?:\s+"[^"]*")?\)|\]\[[^\]]*\])"#)
    private static let autolink = pattern(#"<(?:https?|mailto):[^>\s]+>|(?<![\w/(\[<])https?://[^\s<>()\[\]]+[^\s<>()\[\].,;:!?'"]"#)
    private static let strong = pattern(#"(\*\*|__)(?=\S)(.+?)(?<=\S)(\1)"#)
    private static let emphasis = pattern(#"(?<![*_\w])([*_])(?![*_\s])(.+?)(?<![*_\s])(\1)(?![*_\w])"#)
    private static let strikethrough = pattern(#"(~~)(?=\S)(.+?)(?<=\S)(~~)"#)
    private static let highlight = pattern(#"(?<!=)(==)([^=\n]+?)(==)(?!=)"#)

    // MARK: Styles

    private var plain: [NSAttributedString.Key: Any] = [:]
    private var marker: [NSAttributedString.Key: Any] = [:], heading: [NSAttributedString.Key: Any] = [:]
    private var bold: [NSAttributedString.Key: Any] = [:], italic: [NSAttributedString.Key: Any] = [:]
    private var code: [NSAttributedString.Key: Any] = [:], math: [NSAttributedString.Key: Any] = [:]
    private var link: [NSAttributedString.Key: Any] = [:], tag: [NSAttributedString.Key: Any] = [:]
    private var comment: [NSAttributedString.Key: Any] = [:], literal: [NSAttributedString.Key: Any] = [:]
    private var string: [NSAttributedString.Key: Any] = [:], codeBlock: [NSAttributedString.Key: Any] = [:]
    private var quoteMark: [NSAttributedString.Key: Any] = [:], listMark: [NSAttributedString.Key: Any] = [:]

    /// The editor's text is the theme's code font, at the size code has on the page.
    static func font(_ theme: Theme, bold: Bool = false, italic: Bool = false) -> NSFont {
        theme.font(size: theme.scaled(13.6), bold: bold, italic: italic, mono: true)
    }

    private func makeStyles() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.2
        plain = [.font: Self.font(theme), .foregroundColor: theme.text, .paragraphStyle: paragraph]
        let notProse: [NSAttributedString.Key: Any] = [Self.notProse: true]
        marker = notProse.merging([.foregroundColor: theme.muted]) { $1 }
        heading = [.font: Self.font(theme, bold: true), .foregroundColor: theme.keyword]
        bold = [.font: Self.font(theme, bold: true)]
        italic = [.font: Self.font(theme, italic: true)]
        // Code blocks are left in the text's colour; their marks and language are coloured.
        codeBlock = notProse
        code = notProse.merging([.foregroundColor: theme.literal]) { $1 }
        math = notProse.merging([.foregroundColor: theme.builtin]) { $1 }
        link = [.foregroundColor: theme.link]
        tag = notProse.merging([.foregroundColor: theme.tag]) { $1 }
        comment = [.foregroundColor: theme.comment]
        literal = notProse.merging([.foregroundColor: theme.literal]) { $1 }
        string = [.foregroundColor: theme.string]
        quoteMark = [.foregroundColor: theme.tag]
        listMark = [.foregroundColor: theme.builtin]
    }
}
