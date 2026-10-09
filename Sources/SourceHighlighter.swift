import AppKit

/// Colours Markdown as it is written, in the editor: headings, emphasis, code, links, quotes and
/// lists, in the theme's colours, with the marks that make them faded.
///
/// It works a line at a time. What a line means can depend on the lines above it (inside a fenced
/// code block, front matter or a `$$` formula, a line is not Markdown), so each line carries the
/// state it leaves the next one in. After an edit only the lines touched are coloured again, and
/// the ones below them for as long as their state changes: typing a fence recolours the rest of
/// the document, typing a word recolours one line.
///
/// A long text is coloured a part at a time between events, from the top, and what comes into
/// view is coloured as it does, so that an editor shows it at once.
///
/// The code in fenced blocks is coloured by language as on the page, with highlight.js, off the
/// main thread once typing pauses (see CodeColours).
final class SourceHighlighter: NSObject, NSTextStorageDelegate {
    private(set) var theme: Theme
    /// Called after the characters change, not just their colours.
    var onTextChange: () -> Void = {}
    /// Until an editor shows the text, nothing is coloured.
    private(set) var isActive = false
    private weak var storage: NSTextStorage?
    /// Lines edited since they were last coloured (see colourEdits).
    private var linesToColour: NSRange?
    private var colourScheduled = false
    /// Text not coloured since an editor first showed it or the theme changed (see colourSome).
    private var uncoloured = IndexSet()
    private var restScheduled = false
    /// Where code may need colouring again: what was edited since it was last coloured.
    private var codeToColour: NSRange?
    private var pendingCode: DispatchWorkItem?

    init(storage: NSTextStorage, theme: Theme) {
        self.storage = storage
        self.theme = theme
        super.init()
        makeStyles()
        storage.delegate = self
    }

    /// Colours the whole text, as when an editor first shows it or the theme changes: the start of
    /// it now, and the rest a part at a time (see colourSome).
    func activate(theme: Theme) {
        guard let storage else { return }
        if isActive, theme == self.theme { return }
        self.theme = theme
        makeStyles()
        isActive = true
        linesToColour = nil
        uncoloured = IndexSet(integersIn: 0..<storage.length)
        colourSome()
    }

    /// Colours the text not coloured yet from the top, for a few milliseconds, and goes on between
    /// events until it is all coloured; then the code in it.
    @objc private func colourSome() {
        restScheduled = false
        guard let storage else { return }
        uncoloured.remove(integersIn: storage.length..<Int.max)
        let deadline = CACurrentMediaTime() + 0.008
        var done: NSRange?
        storage.beginEditing()
        while let run = uncoloured.rangeView.first, CACurrentMediaTime() < deadline {
            let coloured = colourLines(NSRange(location: run.lowerBound, length: run.count), in: storage, by: deadline)
            done = done.map { NSUnionRange($0, coloured) } ?? coloured
        }
        storage.endEditing()
        if let done { storage.ensureAttributesAreFixed(in: done) }
        if uncoloured.isEmpty {
            codeToColour = NSRange(location: 0, length: storage.length)
            colourCodeSoon(after: 0)
        } else if !restScheduled {
            restScheduled = true
            // In the run loop's default mode: not while a scroll or a menu is tracked.
            perform(#selector(colourSome), with: nil, afterDelay: 0)
        }
    }

    /// Colours at once what is not coloured yet of a range, as one coming into view.
    func colourNow(_ range: NSRange) {
        guard let storage, let whole = Range(NSIntersectionRange(range, NSRange(location: 0, length: storage.length))),
              uncoloured.intersects(integersIn: whole) else { return }
        var done: NSRange?
        storage.beginEditing()
        while let run = uncoloured.rangeView(of: whole).first {
            let coloured = colourLines(NSRange(location: run.lowerBound, length: run.count), in: storage)
            done = done.map { NSUnionRange($0, coloured) } ?? coloured
        }
        storage.endEditing()
        if let done { storage.ensureAttributesAreFixed(in: done) }
    }

    /// The attributes text is typed with before it is coloured.
    var typingAttributes: [NSAttributedString.Key: Any] { plain }

    /// Marks text that is not prose, such as code, addresses and tags, which spelling leaves alone.
    static let notProse = NSAttributedString.Key("MarkviewNotProse")

    /// Whether a line is inside a fenced code block, front matter, a `$$` formula or an HTML
    /// comment, where what is typed is not Markdown: whether the line above leaves it in one.
    static func isInsideBlock(lineStartingAt location: Int, of storage: NSTextStorage) -> Bool {
        guard location > 0, location <= storage.length else { return false }
        return (storage.attribute(stateKey, at: location - 1, effectiveRange: nil) as? Int ?? 0) != 0
    }

    // MARK: Editing

    // The lines edited are only noted here, while the text storage processes the edit. Colouring
    // them now would widen what it counts as edited, and text views put the insertion point at the
    // end of that: on the next line, at every keystroke.
    func textStorage(_ textStorage: NSTextStorage, willProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), isActive else { return }
        // What is not coloured yet moves along with the text after the edit.
        if !uncoloured.isEmpty { uncoloured.shift(startingAt: NSMaxRange(editedRange) - delta, by: delta) }
        linesToColour = Self.pending(linesToColour, after: editedRange, changeInLength: delta)
        noteCodeEdited(editedRange, changeInLength: delta)
        guard !colourScheduled else { return }
        colourScheduled = true
        // A text view's edits are coloured as soon as it has made them (see SourceTextView.onEdit).
        DispatchQueue.main.async { [weak self] in self?.colourEdits() }
    }

    /// Colours the lines edited since they were last coloured, once the edit is done, as a change
    /// of its own. The text storage then fixes the fonts of what was coloured, as it does for what
    /// is typed, so that characters the code font lacks, such as emoji, keep a font that has them.
    func colourEdits() {
        colourScheduled = false
        guard let range = linesToColour, let storage else { return }
        linesToColour = nil
        let start = min(range.location, storage.length)
        storage.beginEditing()
        let coloured = colourLines(NSRange(location: start, length: min(NSMaxRange(range), storage.length) - start), in: storage)
        storage.endEditing()
        // Fonts are fixed lazily, over whatever range is still unfixed when an attribute is next
        // read; fixed now, that range never spans the text from one edit to another far away.
        storage.ensureAttributesAreFixed(in: coloured)
    }

    /// A range still to be dealt with, moved along by an edit, and taking it in.
    private static func pending(_ pending: NSRange?, after edit: NSRange, changeInLength delta: Int) -> NSRange {
        guard var pending else { return edit }
        let editStart = edit.location, previousEnd = edit.location + edit.length - delta
        if pending.location >= previousEnd { pending.location += delta }
        else if NSMaxRange(pending) > editStart { pending.length = max(NSMaxRange(pending) + delta, editStart) - pending.location }
        return NSUnionRange(pending, edit)
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

    /// Colours the lines from the one holding a range's start to the one holding its end, then the
    /// ones below for as long as the state they leave the next line in changes, up to a line not
    /// coloured yet, which colourSome comes to later. Gives the lines coloured; they are fewer if
    /// the deadline passes first.
    private func colourLines(_ range: NSRange, in storage: NSTextStorage, by deadline: CFTimeInterval = .infinity) -> NSRange {
        // The storage's own string: `string` would copy the whole text at every keystroke.
        let text = storage.mutableString
        guard text.length > 0 else { return NSRange(location: 0, length: 0) }
        var line = text.lineRange(for: NSRange(location: min(range.location, text.length - 1), length: 0))
        let start = line.location, end = min(NSMaxRange(range), text.length)
        var state = state(before: line.location, in: storage)
        while true {
            let lineEnd = NSMaxRange(line)
            // A line's end is the part of it least likely to be new.
            let previous = isColoured(line) ? self.state(at: lineEnd - 1, in: storage) : nil
            state = highlight(line: line, of: text, in: storage, from: state)
            uncoloured.remove(integersIn: line.location..<lineEnd)
            guard lineEnd < text.length else { break }
            // Past the range, a line that leaves the next where it was before means the rest is as
            // it was. The line just after an edit was part of an edited line if a line break was typed.
            if lineEnd > end, previous == state { break }
            line = text.lineRange(for: NSRange(location: lineEnd, length: 0))
            if lineEnd >= end, !isColoured(line) { return NSRange(location: start, length: lineEnd - start) }
            if CACurrentMediaTime() > deadline {
                // Past the range, the lines below may still need colouring again: left for colourSome.
                if lineEnd >= end { uncoloured.insert(integersIn: line.location..<NSMaxRange(line)) }
                return NSRange(location: start, length: lineEnd - start)
            }
        }
        return NSRange(location: start, length: NSMaxRange(line) - start)
    }

    private func isColoured(_ line: NSRange) -> Bool { !uncoloured.intersects(integersIn: line.location..<NSMaxRange(line)) }

    /// The state the lines above leave a line in: the one the line above was coloured with, or if
    /// that is not coloured yet, worked out from the nearest coloured line above it.
    private func state(before location: Int, in storage: NSTextStorage) -> State {
        guard location > 0 else { return .text }
        guard let run = uncoloured.rangeView(of: 0..<location).last, run.upperBound == location else {
            return state(at: location - 1, in: storage) ?? .text
        }
        let text = storage.mutableString
        var line = text.lineRange(for: NSRange(location: run.lowerBound, length: 0))
        var state = line.location == 0 ? State.text : (self.state(at: line.location - 1, in: storage) ?? .text)
        while line.location < location, line.length > 0 {
            state = highlight(line: line, of: text, in: nil, from: state)
            line = text.lineRange(for: NSRange(location: NSMaxRange(line), length: 0))
        }
        return state
    }

    /// Colours one line, and gives the state it leaves the next one in. Without a text storage, it
    /// only works out the state.
    private func highlight(line: NSRange, of text: NSString, in storage: NSTextStorage?, from state: State) -> State {
        let content = text.substring(with: line)
        let body = content.trimmingCharacters(in: .newlines)
        let bodyRange = NSRange(location: line.location, length: (body as NSString).length)
        if let storage {
            // A line of code keeps the colours its language gave it until the block is coloured
            // again, rather than flashing plain while it is typed in.
            var kept: [(NSRange, Any)] = []
            if case .fence = state {
                storage.enumerateAttribute(Self.codeColour, in: line) { flag, range, _ in
                    guard flag != nil, let color = storage.attribute(.foregroundColor, at: range.location, effectiveRange: nil) else { return }
                    kept.append((range, color))
                }
            }
            storage.setAttributes(plain, range: line)
            for (range, color) in kept { storage.addAttributes([.foregroundColor: color, Self.codeColour: true], range: range) }
        }
        var next = state

        func style(_ attributes: [NSAttributedString.Key: Any], _ range: NSRange) {
            storage?.addAttributes(attributes, range: NSRange(location: line.location + range.location, length: range.length))
        }

        switch state {
        case .fence(let mark, let count):
            storage?.addAttributes(codeBlock, range: bodyRange)
            if let close = Self.fence(in: body), close.mark == mark, close.count >= count, close.info.isEmpty {
                style(marker, close.range)
                next = .text
            }
        case .frontMatter:
            if body == "---" || body == "..." {
                storage?.addAttributes(marker, range: bodyRange)
                next = .text
            } else if let colon = body.firstIndex(of: ":"), !body.hasPrefix(" ") {
                style(literal, NSRange(location: 0, length: body.utf16.distance(from: body.startIndex, to: colon)))
                style(string, NSRange(location: body.utf16.distance(from: body.startIndex, to: colon) + 1,
                                      length: body.utf16.distance(from: colon, to: body.endIndex) - 1))
            } else {
                storage?.addAttributes(string, range: bodyRange)
            }
        case .math:
            storage?.addAttributes(math, range: bodyRange)
            if body.trimmingCharacters(in: .whitespaces).hasSuffix("$$") { next = .text }
        case .comment:
            storage?.addAttributes(comment, range: bodyRange)
            if body.contains("-->") { next = .text }
        case .text:
            next = highlightText(body, at: line.location, in: storage)
        }
        storage?.addAttribute(Self.stateKey, value: next.number, range: line)
        return next
    }

    /// A line of Markdown, outside any block that hides it.
    private func highlightText(_ line: String, at location: Int, in storage: NSTextStorage?) -> State {
        let ns = line as NSString
        let all = NSRange(location: 0, length: ns.length)
        func style(_ attributes: [NSAttributedString.Key: Any], _ range: NSRange) {
            guard range.location != NSNotFound, range.length > 0 else { return }
            storage?.addAttributes(attributes, range: NSRange(location: location + range.location, length: range.length))
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
        // The rest is colour only.
        guard let storage else { return .text }
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

    // MARK: Code

    /// Marks colours that highlight.js gave code, which a line keeps while it is edited.
    private static let codeColour = NSAttributedString.Key("MarkviewCodeColour")

    /// An edit moves what is still to be coloured, and adds to it.
    private func noteCodeEdited(_ range: NSRange, changeInLength delta: Int) {
        codeToColour = Self.pending(codeToColour, after: range, changeInLength: delta)
        colourCodeSoon(after: 0.25)
    }

    private func colourCodeSoon(after delay: TimeInterval) {
        pendingCode?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.colourCode() }
        pendingCode = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Colours the fenced blocks that what was edited touches.
    private func colourCode() {
        guard let storage, let pending = codeToColour, storage.length > 0 else { return }
        codeToColour = nil
        let text = storage.mutableString
        let end = min(NSMaxRange(pending), storage.length)
        // Back to the start of a block the edit falls inside.
        var line = text.lineRange(for: NSRange(location: min(pending.location, storage.length - 1), length: 0))
        while line.location > 0, isFence(state(at: line.location - 1, in: storage)) {
            line = text.lineRange(for: NSRange(location: line.location - 1, length: 0))
        }
        while true {
            if !isFence(line.location == 0 ? .text : state(at: line.location - 1, in: storage)), isFence(state(at: NSMaxRange(line) - 1, in: storage)),
               let open = Self.fence(in: text.substring(with: line).trimmingCharacters(in: .newlines)) {
                // An opening fence: the code runs up to the line that leaves the block.
                var last = line
                while NSMaxRange(last) < storage.length {
                    let next = text.lineRange(for: NSRange(location: NSMaxRange(last), length: 0))
                    guard isFence(state(at: NSMaxRange(next) - 1, in: storage)) else { break }
                    last = next
                }
                let code = NSRange(location: NSMaxRange(line), length: NSMaxRange(last) - NSMaxRange(line))
                let language = open.info.split(separator: " ").first.map { $0.lowercased() } ?? ""
                if code.length > 0, !language.isEmpty { colour(code, as: language, in: storage) }
                line = last
            }
            guard NSMaxRange(line) < end, NSMaxRange(line) < storage.length else { break }
            line = text.lineRange(for: NSRange(location: NSMaxRange(line), length: 0))
        }
    }

    private func isFence(_ state: State?) -> Bool {
        if case .fence = state { return true }
        return false
    }

    private func colour(_ range: NSRange, as language: String, in storage: NSTextStorage) {
        let code = storage.mutableString.substring(with: range)
        CodeColours.shared.colours(of: code, language: language, theme: theme) { [weak self, weak storage] colours in
            // Typed on since: a later colouring takes care of it.
            guard let self, let storage, NSMaxRange(range) <= storage.length, storage.mutableString.substring(with: range) == code else { return }
            storage.beginEditing()
            storage.removeAttribute(Self.codeColour, range: range)
            storage.addAttribute(.foregroundColor, value: theme.text, range: range)
            for (part, color) in colours {
                storage.addAttributes([.foregroundColor: color, Self.codeColour: true], range: NSRange(location: range.location + part.location, length: part.length))
            }
            storage.endEditing()
            storage.ensureAttributesAreFixed(in: range)
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

/// highlight.js for the editor's code, shared by every editor and run on a queue of its own: it
/// lives on once started, holding a few megabytes, as the editor colours code at every pause.
final class CodeColours {
    static let shared = CodeColours()
    private let queue = DispatchQueue(label: "com.dagurleo.markview.code-colours", qos: .userInitiated)
    private var engine: HighlightEngine?
    private var engineTheme: Theme?

    /// Calls back on the main thread with the colours of a piece of code, as ranges within it; none
    /// for a language highlight.js does not know.
    func colours(of code: String, language: String, theme: Theme, then: @escaping ([(NSRange, NSColor)]) -> Void) {
        queue.async {
            if self.engineTheme != theme {
                self.engine = HighlightEngine(theme: theme)
                self.engineTheme = theme
            }
            var colours: [(NSRange, NSColor)] = []
            if let engine = self.engine {
                let text = NSMutableAttributedString(string: code)
                let whole = NSRange(location: 0, length: text.length)
                engine.highlight(text, in: whole, language: language)
                text.enumerateAttribute(.foregroundColor, in: whole) { value, range, _ in
                    if let color = value as? NSColor { colours.append((range, color)) }
                }
            }
            DispatchQueue.main.async { then(colours) }
        }
    }
}
