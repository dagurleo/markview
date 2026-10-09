import Cocoa
import UniformTypeIdentifiers

/// The editor's text view. Return carries a list or a quote on to the next line, Tab and Shift-Tab
/// indent list items and selected lines, and the Format menu marks text as bold, italic, code or a
/// link. In a table, Tab goes from cell to cell and Return starts a row, lining the columns up.
/// Typing `/` opens a menu of things to insert (see SlashCommand), and pasting an address over
/// selected text makes it a link. Files dropped on it open, as on the page, rather than being
/// typed in as their paths; dragged text still moves and copies as usual.
final class SourceTextView: NSTextView {
    var onDrop: ([URL]) -> Void = { _ in }
    /// One step of indentation (see EditorSettings).
    var indent = "    "
    /// Whether typing `/` opens the slash menu (see EditorSettings).
    var offersSlashMenu = true
    /// Called when the Edit menu turns spelling or a substitution on or off, so the choice can be kept.
    var onTypingSettingChange: () -> Void = {}
    /// The folder of the document on show, which a picture's path is written from.
    var folder: () -> URL? = { nil }
    /// Called once an edit is made, before anything hears of it.
    var onEdit: () -> Void = {}

    private var text: NSMutableString { textStorage?.mutableString ?? NSMutableString() }
    private var slashMenu: SlashMenu?
    /// Where the slash is that opened the slash menu, while it is open.
    private var slash: Int?
    /// The places still to fill in of the template last put in, in the order Tab goes to them.
    private var fields: [NSRange] = []
    private var windowObserver: NSObjectProtocol?

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

    /// What a line starts with, if anything: indentation alone is not a list or a quote to carry on.
    private func lineStart(of line: String) -> LineStart? {
        let start = parse(line)
        return start.isListItem || !start.quotes.isEmpty ? start : nil
    }

    private func parse(_ line: String) -> LineStart {
        let ns = line as NSString
        let match = Self.lineStart.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))
        func group(_ index: Int) -> String? {
            guard let range = match?.range(at: index), range.location != NSNotFound else { return nil }
            return ns.substring(with: range)
        }
        return LineStart(indent: group(1) ?? "", quotes: group(2) ?? "", innerIndent: group(3) ?? "", marker: group(4),
                         spacing: group(5) ?? "", task: group(6), length: match?.range.length ?? 0)
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
        if newRowInTable() { return }
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
        if moveToField(by: 1) || moveInTable(by: 1) { return }
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
        if moveToField(by: -1) || moveInTable(by: -1) { return }
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

    // MARK: Tables

    /// The table a line is in: where its lines are, what they hold, and which of them the line is.
    private func table(at location: Int) -> (block: NSRange, table: MarkdownTable, line: Int)? {
        guard let storage = textStorage else { return nil }
        func isRow(_ line: NSRange) -> Bool {
            let row = content(of: line)
            return row.contains("|") && !row.hasPrefix("    ") && !row.hasPrefix("\t")
                && !SourceHighlighter.isInsideBlock(lineStartingAt: line.location, of: storage)
        }
        let line = lineRange(at: location)
        guard isRow(line) else { return nil }
        var rows = [line]
        while let first = rows.first, first.location > 0, case let above = lineRange(at: first.location - 1), isRow(above) { rows.insert(above, at: 0) }
        while let last = rows.last, NSMaxRange(last) < text.length, case let below = lineRange(at: NSMaxRange(last)), isRow(below) { rows.append(below) }
        // The table starts on the row above its delimiter row; rows with pipes above that are not in it.
        guard let delimiter = rows.indices.dropFirst().first(where: { MarkdownTable.isDelimiterRow(content(of: rows[$0])) }),
              let index = rows.firstIndex(of: line), index >= delimiter - 1 else { return nil }
        rows.removeFirst(delimiter - 1)
        let lines = rows.map(content(of:))
        guard let table = MarkdownTable(lines: lines) else { return nil }
        let end = rows.last!.location + (lines.last! as NSString).length
        return (NSRange(location: rows[0].location, length: end - rows[0].location), table, index - (delimiter - 1))
    }

    /// Tab and Shift-Tab go from cell to cell, Tab past the last cell starting a new row. A line
    /// of cells that is no table yet becomes the header of one.
    private func moveInTable(by step: Int) -> Bool {
        let selection = selectedRange()
        guard selectedRanges.count == 1, selectedLines().count == 1 else { return false }
        guard let (block, table, lineIndex) = table(at: selection.location) else { return makeTable() }
        var changed = table
        let line = lineRange(at: selection.location)
        var row = max(lineIndex - 1, 0)
        var column = min(MarkdownTable.column(at: selection.location - line.location, in: content(of: line)), changed.columns - 1) + step
        if column >= changed.columns {
            column = 0
            row += 1
        } else if column < 0 {
            guard row > 0 else { NSSound.beep(); return true }
            row -= 1
            column = changed.columns - 1
        }
        if row == changed.rows.count { changed.rows.append(Array(repeating: "", count: changed.columns)) }
        rewrite(changed, in: block, selecting: row, column)
        return true
    }

    /// A line like `| Name | Age |` above no delimiter row: Tab makes it a table's header, and
    /// goes to the first cell of its first row.
    private func makeTable() -> Bool {
        let line = lineRange(at: selectedRange().location)
        let lineText = content(of: line)
        guard lineText.trimmingCharacters(in: .whitespaces).hasPrefix("|"), let storage = textStorage,
              !SourceHighlighter.isInsideBlock(lineStartingAt: line.location, of: storage) else { return false }
        let columns = MarkdownTable.cells(of: lineText).count
        let delimiter = "|" + String(repeating: " --- |", count: columns), empty = "|" + String(repeating: "  |", count: columns)
        guard columns > 0, let table = MarkdownTable(lines: [lineText, delimiter, empty]) else { return false }
        rewrite(table, in: NSRange(location: line.location, length: (lineText as NSString).length), selecting: 1, 0)
        return true
    }

    /// Return starts a new row below, or on an empty last row ends the table.
    private func newRowInTable() -> Bool {
        let selection = selectedRange()
        guard selectedRanges.count == 1, selection.length == 0, let (block, table, lineIndex) = table(at: selection.location) else { return false }
        var changed = table
        let row = max(lineIndex - 1, 0)
        guard row == 0 || row < changed.rows.count - 1 || changed.rows[row].contains(where: { !$0.isEmpty }) else {
            changed.rows.removeLast()
            let written = changed.formatted().text
            let after = NSMaxRange(block)
            // On to a line after the table: the empty one there, or a new one.
            let followedByEmptyLine = after < text.length && (after + 1 == text.length || text.character(at: after + 1) == 10)
            breakUndoCoalescing()
            change([(block, followedByEmptyLine ? written : written + "\n")])
            setSelectedRange(NSRange(location: block.location + (written as NSString).length + 1, length: 0))
            return true
        }
        changed.rows.insert(Array(repeating: "", count: changed.columns), at: row + 1)
        rewrite(changed, in: block, selecting: row + 1, 0)
        return true
    }

    /// Writes a table again with its columns lined up, and selects the text of one of its cells.
    private func rewrite(_ table: MarkdownTable, in block: NSRange, selecting row: Int, _ column: Int) {
        let (written, cells) = table.formatted()
        if written != text.substring(with: block) {
            breakUndoCoalescing()
            change([(block, written)])
        }
        let cell = cells[row][column]
        let selection = NSRange(location: block.location + cell.location, length: cell.length)
        setSelectedRange(selection)
        scrollRangeToVisible(selection)
    }

    // MARK: Slash menu

    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        let typed = (string as? String) ?? (string as? NSAttributedString)?.string
        if typed == "/", slash == nil, offersSlashMenu { openSlashMenu() }
    }

    /// Opens the menu for a slash just typed at the start of a line or after a space, in Markdown:
    /// not in a path or an address, and not in code.
    private func openSlashMenu() {
        let caret = selectedRange()
        guard selectedRanges.count == 1, caret.length == 0, caret.location > 0, !hasMarkedText(), let storage = textStorage else { return }
        let at = caret.location - 1
        guard text.character(at: at) == 47, at == 0 || [32, 9, 10].contains(text.character(at: at - 1)),
              storage.attribute(SourceHighlighter.notProse, at: at, effectiveRange: nil) == nil,
              !SourceHighlighter.isInsideBlock(lineStartingAt: lineRange(at: at).location, of: storage) else { return }
        slash = at
        updateSlashMenu()
    }

    /// Shows what the word after the slash finds, or closes the menu once it finds nothing, the
    /// slash is gone or the insertion point has left the word.
    private func updateSlashMenu() {
        guard let slash else { return }
        let caret = selectedRange()
        guard selectedRanges.count == 1, caret.length == 0, slash < text.length, text.character(at: slash) == 47,
              caret.location > slash, caret.location - slash <= 40, let window else { return closeSlashMenu() }
        let query = text.substring(with: NSRange(location: slash + 1, length: caret.location - slash - 1))
        let found = query.contains("\n") ? [] : SlashCommand.matches(query, allowingFrontMatter: !text.hasPrefix("---\n"))
        guard !found.isEmpty else { return closeSlashMenu() }
        if slashMenu == nil {
            slashMenu = SlashMenu()
            slashMenu?.onChoose = { [weak self] in self?.perform($0) }
        }
        slashMenu?.show(found, under: firstRect(forCharacterRange: NSRange(location: slash, length: 1), actualRange: nil), in: window)
    }

    func closeSlashMenu() {
        slash = nil
        slashMenu?.close()
    }

    /// Keeps the menu under its slash as the text scrolls.
    func slashMenuFollows() {
        guard let slash, let window, slash < text.length else { return }
        slashMenu?.move(under: firstRect(forCharacterRange: NSRange(location: slash, length: 1), actualRange: nil), in: window)
    }

    override func didChangeText() {
        onEdit()
        super.didChangeText()
        if slash != nil { updateSlashMenu() }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        guard !stillSelecting else { return }
        // Moving out of the template's fields leaves it done.
        if !fields.isEmpty, let selection = ranges.first?.rangeValue, !fields.contains(where: { $0.holds(selection) }) { fields = [] }
        if slash != nil { updateSlashMenu() }
    }

    // While the menu is open, the arrow keys move in it, Return and Tab choose, and Escape closes it.
    override func doCommand(by selector: Selector) {
        if slash != nil, let menu = slashMenu, menu.isShown {
            switch selector {
            case #selector(moveUp(_:)): return menu.step(-1)
            case #selector(moveDown(_:)): return menu.step(1)
            case #selector(insertNewline(_:)), #selector(insertTab(_:)): if let command = menu.selected { return perform(command) }
            case #selector(cancelOperation(_:)), #selector(complete(_:)): return closeSlashMenu()
            default: break
            }
        }
        if selector == #selector(cancelOperation(_:)), !fields.isEmpty { return fields = [] }
        super.doCommand(by: selector)
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { closeSlashMenu() }
        return resigned
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObserver.map(NotificationCenter.default.removeObserver)
        windowObserver = window.map { window in
            NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.closeSlashMenu() }
            }
        }
        if window == nil { closeSlashMenu() }
    }

    /// Does what a command in the menu does, in place of the slash and the word after it. A
    /// command with choices goes on to them, as if its name and a space had been typed.
    private func perform(_ command: SlashCommand) {
        guard let slash else { return }
        let typed = NSRange(location: slash, length: selectedRange().location - slash)
        if command.choices != nil { return insertText("/" + command.word + " ", replacementRange: typed) }
        closeSlashMenu()
        // Undo takes the command back to the word typed.
        breakUndoCoalescing()
        switch command.kind {
        case .line(let marks): mark(lineOf: typed, with: marks)
        case .block(let template): insertBlock(template, replacing: typed)
        case .inline(let template): insert([(typed, template)])
        case .image: chooseImage(replacing: typed)
        case .footnote: insertFootnote(replacing: typed)
        case .frontMatter: insertFrontMatter(removing: typed)
        }
    }

    /// What to take out with the slash and its word: the spaces before it too, if nothing but
    /// spaces follows on the line.
    private func removal(of typed: NSRange) -> NSRange {
        let line = lineRange(at: typed.location)
        let lineEnd = line.location + (content(of: line) as NSString).length
        let rest = text.substring(with: NSRange(location: NSMaxRange(typed), length: lineEnd - NSMaxRange(typed)))
        guard rest.trimmingCharacters(in: .whitespaces).isEmpty else { return typed }
        var start = typed.location
        while start > line.location, [32, 9].contains(text.character(at: start - 1)) { start -= 1 }
        return NSRange(location: start, length: lineEnd - start)
    }

    /// The marks a line starts with: indentation, quote marks, then a heading's or a list item's.
    private static let lineMarks = try! NSRegularExpression(
        pattern: #"^([ \t]*)((?:>[ \t]?)*)(#{1,6}[ \t]+|(?:[-+*]|\d{1,9}[.)])[ \t]+(?:\[[ xX]\][ \t]+)?)?"#)

    /// Makes a line a heading or a list item in place of what it was, or puts it in a quote.
    private func mark(lineOf typed: NSRange, with mark: String) {
        let line = lineRange(at: typed.location)
        let lineText = content(of: line)
        guard let match = Self.lineMarks.firstMatch(in: lineText, range: NSRange(location: 0, length: (lineText as NSString).length)) else { return }
        let old = match.range(at: 3).location == NSNotFound ? NSRange(location: NSMaxRange(match.range(at: 2)), length: 0) : match.range(at: 3)
        var marked = NSRange(location: line.location + old.location, length: old.length)
        if mark == "> " { marked = NSRange(location: line.location + match.range(at: 1).length, length: 0) }
        let removed = removal(of: typed)
        guard let starts = change([(marked, mark), (removed, "")]) else { return }
        setSelectedRange(NSRange(location: starts[1], length: 0))
    }

    /// Puts lines of their own where the slash was: in place of its line if nothing else is on it,
    /// else after the line. In a list item or a quote they stay inside it, and a blank line sets
    /// them apart from text above and below, which Markdown needs to read a table or a divider.
    private func insertBlock(_ template: String, replacing typed: NSRange) {
        let line = lineRange(at: typed.location)
        let lineText = content(of: line) as NSString
        let before = lineText.substring(to: typed.location - line.location)
        let after = lineText.substring(from: NSMaxRange(typed) - line.location)
        let start = parse(before)
        let inside = start.indent + start.quotes + start.innerIndent + String(repeating: " ", count: ((start.marker ?? "") + (start.marker == nil ? "" : start.spacing)).count)
        let blank = inside.trimmingCharacters(in: .whitespaces)
        let body = template.components(separatedBy: "\n")
        let lineAfter = NSMaxRange(line) < text.length ? lineRange(at: NSMaxRange(line)) : nil
        if (before as NSString).length == start.length, after.trimmingCharacters(in: .whitespaces).isEmpty {
            var lines = [before + body[0]] + body.dropFirst().map { inside + $0 }
            if start.marker == nil, line.location > 0, !isBlank(lineRange(at: line.location - 1)) { lines.insert(blank, at: 0) }
            if let lineAfter, !isBlank(lineAfter) { lines.append(blank) }
            insert([(NSRange(location: line.location, length: lineText.length), lines.joined(separator: "\n"))])
        } else {
            var lines = [blank] + body.map { inside + $0 }
            if let lineAfter, !isBlank(lineAfter) { lines.append(blank) }
            insert([(removal(of: typed), ""), (NSRange(location: line.location + lineText.length, length: 0), "\n" + lines.joined(separator: "\n"))])
        }
    }

    /// Whether a line has nothing in it but spaces and quote marks.
    private func isBlank(_ line: NSRange) -> Bool {
        content(of: line).allSatisfy { $0 == " " || $0 == "\t" || $0 == ">" }
    }

    private static let footnoteReference = try! NSRegularExpression(pattern: #"\[\^(\d+)\]"#)

    /// A numbered reference where the slash was, and its note at the end of the document, where
    /// the insertion point goes to write it. Tab then goes back to after the reference.
    private func insertFootnote(replacing typed: NSRange) {
        // The reference goes right after the word before it.
        var typed = typed
        if typed.location > lineRange(at: typed.location).location, text.character(at: typed.location - 1) == 32 {
            typed = NSRange(location: typed.location - 1, length: typed.length + 1)
        }
        let numbers = Self.footnoteReference.matches(in: text as String, range: NSRange(location: 0, length: text.length)).compactMap {
            Int(text.substring(with: $0.range(at: 1)))
        }
        let number = (numbers.max() ?? 0) + 1
        let lastLine = text.length == 0 ? "" : content(of: lineRange(at: text.length - 1))
        // Notes go together, after a blank line.
        var definition = text.hasSuffix("\n") || text.length == 0 ? "" : "\n"
        if !lastLine.trimmingCharacters(in: .whitespaces).isEmpty, !lastLine.hasPrefix("[^") { definition += "\n" }
        definition += "[^\(number)]: ⟨⟩"
        insert([(NSRange(location: text.length, length: 0), definition), (typed, "[^\(number)]⟨⟩")])
    }

    /// Front matter at the top of the document, wherever the slash was.
    private func insertFrontMatter(removing typed: NSRange) {
        let removed = removal(of: typed)
        let firstLine = text.length == 0 ? NSRange(location: 0, length: 0) : lineRange(at: 0)
        var rest = content(of: firstLine) as NSString
        if removed.location < NSMaxRange(firstLine) { rest = rest.replacingCharacters(in: NSRange(location: removed.location, length: min(removed.length, rest.length - removed.location)), with: "") as NSString }
        let gap = rest.trimmingCharacters(in: .whitespaces).isEmpty ? "" : "\n"
        insert([(NSRange(location: 0, length: 0), "---\ntitle: ⟨Title⟩\n---\n" + gap), (removed, "")])
    }

    /// Asks for a picture, and puts it in where the slash was, with its path from the document's
    /// folder and its name to describe it, selected to type over.
    private func chooseImage(replacing typed: NSRange) {
        guard let window else { return }
        let word = text.substring(with: typed)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.directoryURL = folder()
        panel.prompt = "Insert"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let file = panel.url else { return }
            // The text may have changed meanwhile, in another window.
            let range = NSMaxRange(typed) <= text.length && text.substring(with: typed) == word ? typed : selectedRange()
            let name = file.deletingPathExtension().lastPathComponent.filter { !"⟨⟩".contains($0) }
                .replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
            insert([(range, "![⟨\(name)⟩](\(path(to: file)))")])
        }
    }

    /// How the document refers to a file: from its folder, or by its full path if they have only
    /// the top of the disk in common.
    func path(to file: URL) -> String {
        var path = file.path
        if let folder = folder() {
            let from = folder.resolvingSymlinksInPath().pathComponents, to = file.resolvingSymlinksInPath().pathComponents
            var shared = 0
            while shared < min(from.count, to.count), from[shared] == to[shared] { shared += 1 }
            if shared > 1 { path = (Array(repeating: "..", count: from.count - shared) + to[shared...]).joined(separator: "/") }
        }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "()")
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }

    // MARK: Templates

    /// Puts templates in as one change, and selects the first of their fields (see SlashCommand).
    private func insert(_ templates: [(range: NSRange, template: String)]) {
        let filled = templates.map { SlashCommand.fill($0.template) }
        guard let starts = change(zip(templates, filled).map { ($0.range, $1.text) }) else { return }
        let found = zip(starts, filled).flatMap { start, fill in fill.fields.map { NSRange(location: $0.location + start, length: $0.length) } }
        guard let first = found.first else {
            return setSelectedRange(NSRange(location: starts[0] + (filled[0].text as NSString).length, length: 0))
        }
        fields = []
        setSelectedRange(first)
        scrollRangeToVisible(first)
        if found.count > 1 { fields = found }
    }

    /// Goes on to the next field of a template, or back to the one before. The last is where the
    /// template ends: once there, it is done.
    private func moveToField(by step: Int) -> Bool {
        guard !fields.isEmpty else { return false }
        let selection = selectedRange()
        guard let current = fields.firstIndex(where: { $0.holds(selection) }) else {
            fields = []
            return false
        }
        let next = current + step
        guard fields.indices.contains(next) else { return true }
        let field = fields[next]
        if next == fields.count - 1 { fields = [] }
        setSelectedRange(field)
        scrollRangeToVisible(field)
        return true
    }

    /// Keeps the fields on the text they mark as it changes. Typing in a field or at either end of
    /// it grows the field; a change across one's edge leaves the template done.
    func textEdited(_ edited: NSRange, changeInLength delta: Int) {
        guard !fields.isEmpty else { return }
        let replaced = NSRange(location: edited.location, length: edited.length - delta)
        var moved: [NSRange] = []
        for field in fields {
            if NSMaxRange(replaced) <= field.location, replaced.location < field.location || replaced.length > 0 {
                moved.append(NSRange(location: field.location + delta, length: field.length))
            } else if replaced.location >= field.location, NSMaxRange(replaced) <= NSMaxRange(field) {
                moved.append(NSRange(location: field.location, length: field.length + delta))
            } else if replaced.location >= NSMaxRange(field) {
                moved.append(field)
            } else {
                return fields = []
            }
        }
        fields = moved
    }

    /// Makes changes to the text as one, to undo together, and gives where each one's new text
    /// starts once all are made.
    @discardableResult
    private func change(_ edits: [(range: NSRange, text: String)]) -> [Int]? {
        let order = edits.indices.sorted { (edits[$0].range.location, edits[$0].range.length) < (edits[$1].range.location, edits[$1].range.length) }
        guard let storage = textStorage,
              shouldChangeText(inRanges: order.map { NSValue(range: edits[$0].range) }, replacementStrings: order.map { edits[$0].text }) else { return nil }
        storage.beginEditing()
        for index in order.reversed() {
            storage.replaceCharacters(in: edits[index].range, with: NSAttributedString(string: edits[index].text, attributes: typingAttributes))
        }
        storage.endEditing()
        didChangeText()
        var starts = Array(repeating: 0, count: edits.count), shift = 0
        for index in order {
            starts[index] = edits[index].range.location + shift
            shift += (edits[index].text as NSString).length - edits[index].range.length
        }
        return starts
    }

    // MARK: Pasting links

    override func paste(_ sender: Any?) {
        if !pasteLink(from: .general) { super.paste(sender) }
    }

    /// Makes the selected text a link, if the pasteboard holds an address and nothing else, and
    /// the selection is prose on one line rather than code or an address itself.
    func pasteLink(from pasteboard: NSPasteboard) -> Bool {
        let selection = selectedRange()
        guard selectedRanges.count == 1, selection.length > 0, let storage = textStorage,
              let address = pasteboard.string(forType: .string).flatMap({ Self.address($0.trimmingCharacters(in: .whitespacesAndNewlines)) }),
              storage.attribute(SourceHighlighter.notProse, at: selection.location, effectiveRange: nil) == nil else { return false }
        let selected = text.substring(with: selection)
        guard !selected.contains("\n"), Self.address(selected) == nil else { return false }
        breakUndoCoalescing()
        insertText("[\(selected)](\(address))", replacementRange: selection)
        breakUndoCoalescing()
        return true
    }

    private static func address(_ text: String) -> String? {
        guard !text.contains(where: \.isWhitespace), let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "mailto" || (scheme == "http" || scheme == "https") && url.host?.isEmpty == false else { return nil }
        return text
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

private extension NSRange {
    /// Whether a selection is inside this range, or at either end of it.
    func holds(_ selection: NSRange) -> Bool { selection.location >= location && NSMaxRange(selection) <= NSMaxRange(self) }
}
