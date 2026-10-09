import Cocoa

/// The editor's text view. Return carries a list or a quote on to the next line, Tab and Shift-Tab
/// indent list items and selected lines, and the Format menu marks text as bold, italic, code or a
/// link. Files dropped on it open, as on the page, rather than being typed in as their paths;
/// dragged text still moves and copies as usual.
final class SourceTextView: NSTextView {
    var onDrop: ([URL]) -> Void = { _ in }
    /// One step of indentation (see EditorSettings).
    var indent = "    "
    /// Called when the Edit menu turns spelling or a substitution on or off, so the choice can be kept.
    var onTypingSettingChange: () -> Void = {}

    private var text: NSMutableString { textStorage?.mutableString ?? NSMutableString() }

    // MARK: Lists

    /// The start of a list item or a quoted line: indentation, quote marks, then a list item's mark,
    /// its spacing and a task box.
    private static let lineStart = try! NSRegularExpression(
        pattern: #"^([ \t]*)((?:>[ \t]?)*)(?:([ \t]*)([-+*]|\d{1,9}[.)])([ \t]+)(\[[ xX]\][ \t]+)?)?"#)

    private struct LineStart {
        let indent: String, quotes: String, innerIndent: String, marker: String?, spacing: String, task: String?
        /// Everything before the line's text.
        let length: Int

        var isListItem: Bool { marker != nil }
        /// How far in the item's text starts, counting a tab as four columns.
        var contentColumn: Int { columns(indent + quotes + innerIndent) + (marker ?? "").count + columns(spacing) }

        /// What the next line starts with: the next number, a fresh task box.
        var continued: String {
            guard let marker else { return indent + quotes }
            var next = marker
            if let number = Int(marker.dropLast()) { next = "\(number + 1)\(marker.last!)" }
            return indent + quotes + innerIndent + next + spacing + (task == nil ? "" : "[ ] ")
        }
    }

    private static func columns(_ whitespace: String) -> Int { whitespace.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } }

    private func lineStart(of line: String) -> LineStart? {
        let ns = line as NSString
        guard let match = Self.lineStart.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)), match.range.length > 0 else { return nil }
        func group(_ index: Int) -> String? {
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : ns.substring(with: range)
        }
        let start = LineStart(indent: group(1) ?? "", quotes: group(2) ?? "", innerIndent: group(3) ?? "", marker: group(4),
                              spacing: group(5) ?? "", task: group(6), length: match.range.length)
        // Indentation alone is not a list or a quote to carry on.
        return start.isListItem || !start.quotes.isEmpty ? start : nil
    }

    private func lineRange(at location: Int) -> NSRange { text.lineRange(for: NSRange(location: location, length: 0)) }

    /// A line's text without its line break.
    private func content(of line: NSRange) -> String {
        text.substring(with: line).trimmingCharacters(in: .newlines)
    }

    /// Whether a line is code, in a fenced block or the like, where a list is no list.
    private func isCode(_ line: NSRange) -> Bool {
        guard line.location < text.length else { return false }
        return textStorage?.attribute(SourceHighlighter.notProse, at: line.location, effectiveRange: nil) != nil
    }

    // Return on a list item starts the next item; on an item with nothing in it, it ends the list.
    override func insertNewline(_ sender: Any?) {
        let selection = selectedRange()
        let line = lineRange(at: selection.location)
        let lineText = content(of: line)
        guard selectedRanges.count == 1, !isCode(line), let start = lineStart(of: lineText), selection.location - line.location >= start.length else {
            return super.insertNewline(sender)
        }
        if (lineText as NSString).length == start.length, NSMaxRange(selection) >= line.location + start.length {
            // Nothing in the item or the quoted line: Return ends the list, leaving the line empty.
            insertText("", replacementRange: NSRange(location: line.location, length: start.length + selection.length))
            return
        }
        insertText("\n" + start.continued, replacementRange: selection)
    }

    // Tab nests a list item under the one above it, lined up with that item's text, as Markdown
    // reads it; with lines selected it indents them all. Anywhere else it inserts the indentation.
    override func insertTab(_ sender: Any?) {
        let lines = selectedLines()
        if lines.count > 1 { return shift(lines, by: 1) }
        let line = lines[0]
        guard !isCode(line), let start = lineStart(of: content(of: line)), start.isListItem else { return insertText(indent, replacementRange: selectedRange()) }
        // The nearest item above that is not nested deeper sets how far in this one goes.
        guard let parent = itemAbove(line, within: Self.columns(start.indent)), parent.contentColumn > Self.columns(start.indent) else {
            return NSSound.beep()
        }
        reindent(line, from: start.indent, to: String(repeating: " ", count: parent.contentColumn))
    }

    // Shift-Tab takes a list item out to the level of the item it was nested under, or takes one
    // step of indentation off the selected lines.
    override func insertBacktab(_ sender: Any?) {
        let lines = selectedLines()
        if lines.count > 1 { return shift(lines, by: -1) }
        let line = lines[0]
        let lineText = content(of: line)
        guard let start = lineStart(of: lineText), start.isListItem else { return shift(lines, by: -1) }
        let column = Self.columns(start.indent)
        guard column > 0 else { return NSSound.beep() }
        let outer = itemAbove(line, within: column - 1)
        reindent(line, from: start.indent, to: outer?.indent ?? "")
    }

    /// The closest list item above a line whose indentation is at most `column`.
    private func itemAbove(_ line: NSRange, within column: Int) -> LineStart? {
        var location = line.location
        while location > 0 {
            let above = lineRange(at: location - 1)
            location = above.location
            let aboveText = content(of: above)
            if aboveText.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            guard let start = lineStart(of: aboveText), start.isListItem else {
                // A line of an item's text is indented under it; anything at the left margin ends the list.
                if Self.columns(String(aboveText.prefix { $0 == " " || $0 == "\t" })) == 0 { return nil }
                continue
            }
            if Self.columns(start.indent) <= column { return start }
        }
        return nil
    }

    private func reindent(_ line: NSRange, from old: String, to new: String) {
        let selection = selectedRange()
        let delta = (new as NSString).length - (old as NSString).length
        insertText(new, replacementRange: NSRange(location: line.location, length: (old as NSString).length))
        setSelectedRange(NSRange(location: max(selection.location + delta, line.location), length: selection.length))
    }

    /// The lines the selection touches; a selection ending at the start of a line leaves that line out.
    private func selectedLines() -> [NSRange] {
        let selection = selectedRange()
        var end = NSMaxRange(selection)
        if selection.length > 0, end > selection.location, end <= text.length, text.character(at: end - 1) == 10 { end -= 1 }
        var lines: [NSRange] = [], location = selection.location
        repeat {
            let line = lineRange(at: location)
            lines.append(line)
            location = NSMaxRange(line)
        } while location < end && location < text.length
        return lines
    }

    /// Indents each line by one step, or takes one step off, as one change to undo.
    private func shift(_ lines: [NSRange], by steps: Int) {
        guard let first = lines.first, let last = lines.last else { return }
        let block = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        var result = ""
        for line in lines {
            let lineText = text.substring(with: line)
            if steps > 0 {
                result += lineText.trimmingCharacters(in: .newlines).isEmpty ? lineText : indent + lineText
            } else {
                var removed = 0, columns = 0
                for character in lineText {
                    guard character == " " || character == "\t", columns < Self.columns(indent) else { break }
                    columns += character == "\t" ? 4 : 1
                    removed += 1
                }
                result += String(lineText.dropFirst(removed))
            }
        }
        guard result != text.substring(with: block) else { return NSSound.beep() }
        insertText(result, replacementRange: block)
        setSelectedRange(NSRange(location: block.location, length: (result as NSString).length - (result.hasSuffix("\n") ? 1 : 0)))
    }

    // MARK: Format

    @objc func toggleBold(_ sender: Any?) { toggle("**") }
    @objc func toggleItalic(_ sender: Any?) { toggle("*") }
    @objc func toggleStrikethrough(_ sender: Any?) { toggle("~~") }
    @objc func toggleCode(_ sender: Any?) { toggle("`") }

    /// Puts a mark either side of the selection, or takes it away if it is there already, just
    /// inside the selection or just outside it. With nothing selected, the insertion point goes
    /// between the two marks. Stars are counted, so italic and bold go on and off each other:
    /// an odd number either side is italic, two or more bold.
    private func toggle(_ mark: String) {
        let selection = selectedRange()
        let length = (mark as NSString).length
        let selected = text.substring(with: selection)
        let star = mark.first == "*"
        func marked(_ before: Int, _ after: Int) -> Bool {
            star ? (length == 1 ? min(before, after) % 2 == 1 : min(before, after) >= 2) : min(before, after) >= 1
        }
        let outside = (count(mark.first!, before: selection.location), count(mark.first!, after: NSMaxRange(selection)))
        let outsideMarks = star ? outside : (outside.0 >= length ? 1 : 0, outside.1 >= length ? 1 : 0)
        if marked(outsideMarks.0, outsideMarks.1), (star || text.substring(with: NSRange(location: selection.location - length, length: length)) == mark) {
            insertText(selected, replacementRange: NSRange(location: selection.location - length, length: selection.length + 2 * length))
            return setSelectedRange(NSRange(location: selection.location - length, length: selection.length))
        }
        let inner = selected.prefix { $0 == mark.first! }.count, innerEnd = selected.reversed().prefix { $0 == mark.first! }.count
        if selection.length >= 2 * length, inner < selected.count, star ? marked(inner, innerEnd) : selected.hasPrefix(mark) && selected.hasSuffix(mark) {
            let unmarked = String(selected.dropFirst(mark.count).dropLast(mark.count))
            insertText(unmarked, replacementRange: selection)
            return setSelectedRange(NSRange(location: selection.location, length: (unmarked as NSString).length))
        }
        insertText(mark + selected + mark, replacementRange: selection)
        setSelectedRange(NSRange(location: selection.location + length, length: selection.length))
    }

    /// How many of a character run up to a location, and on from one.
    private func count(_ character: Character, before location: Int) -> Int {
        let unit = String(character).utf16.first!
        var index = location, found = 0
        while index > 0, text.character(at: index - 1) == unit { index -= 1; found += 1 }
        return found
    }

    private func count(_ character: Character, after location: Int) -> Int {
        let unit = String(character).utf16.first!
        var index = location, found = 0
        while index < text.length, text.character(at: index) == unit { index += 1; found += 1 }
        return found
    }

    /// Makes the selection a link, with the address left selected to type over; a selected address
    /// becomes the link's address, with the insertion point where its text goes.
    @objc func insertLink(_ sender: Any?) {
        let selection = selectedRange()
        let selected = text.substring(with: selection)
        if let url = URL(string: selected), url.scheme == "http" || url.scheme == "https" || url.scheme == "mailto" {
            insertText("[](\(selected))", replacementRange: selection)
            return setSelectedRange(NSRange(location: selection.location + 1, length: 0))
        }
        insertText("[\(selected)](url)", replacementRange: selection)
        setSelectedRange(NSRange(location: selection.location + (selected as NSString).length + 3, length: 3))
    }

    // MARK: Typing settings

    // Spelling and substitutions chosen in the Edit menu are kept for every editor.
    override func toggleContinuousSpellChecking(_ sender: Any?) {
        super.toggleContinuousSpellChecking(sender)
        onTypingSettingChange()
    }

    override func toggleAutomaticQuoteSubstitution(_ sender: Any?) {
        super.toggleAutomaticQuoteSubstitution(sender)
        onTypingSettingChange()
    }

    override func toggleAutomaticDashSubstitution(_ sender: Any?) {
        super.toggleAutomaticDashSubstitution(sender)
        onTypingSettingChange()
    }

    override func toggleAutomaticTextReplacement(_ sender: Any?) {
        super.toggleAutomaticTextReplacement(sender)
        onTypingSettingChange()
    }

    // MARK: Dropping files

    private func files(in sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        files(in: sender).isEmpty ? super.draggingEntered(sender) : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        files(in: sender).isEmpty ? super.draggingUpdated(sender) : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let dropped = files(in: sender)
        guard !dropped.isEmpty else { return super.performDragOperation(sender) }
        onDrop(dropped)
        return true
    }
}
