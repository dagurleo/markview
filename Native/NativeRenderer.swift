import AppKit

/// Turns Markdown into an attributed string for a TextKit 1 text view, using
/// Foundation's own Markdown parser. No web view and no JavaScript.
final class NativeRenderer {
    /// Heading slug to character location, for #heading links.
    private(set) var anchors: [String: Int] = [:]
    /// The headings in order, for the Go menu.
    private(set) var headings: [Heading] = []
    /// An image still to be fetched from the network, with any size the document asked for,
    /// and where to put it once it is in.
    struct RemoteImage {
        let url: URL
        let width: CGFloat?, height: CGFloat?
        let place: (NSImage) -> Void
    }
    private(set) var remoteImages: [RemoteImage] = []
    /// Whether any picture depends on the appearance (see AppearanceAttachment).
    private(set) var hasAppearanceImages = false
    /// Diagrams still to be drawn, in the order their placeholders appear. Math is drawn as it is rendered.
    private(set) var diagrams: [Diagram] = []
    /// Whether any code block is a drawing, which the view fits to its column (see `drawing`).
    private(set) var hasDrawings = false
    /// Tables given their natural width, which the view fits to its column (see `fitTables`).
    private(set) var fittedTables: [FittedTable] = []

    private typealias Piece = (run: AttributedString.Runs.Run, text: String)

    /// What a paragraph is, decided before its text is built.
    private struct Paragraph {
        var quotes: [NSTextBlock] = []
        var heading: Int?
        var cell: NSTextTableBlock?
        var alignment: NSTextAlignment?
        var listDepth = 0
        var marker: String?
        /// Identity of the outermost list the paragraph is in, so one list can be told from the next.
        var listID: Int?
        var size: CGFloat
        var color: NSColor
    }

    /// Formatting switched on by HTML tags, in Markdown paragraphs and HTML blocks alike.
    private struct InlineStyle {
        var bold = 0, italic = 0, mono = 0, sub = 0, sup = 0, strike = 0, underline = 0, mark = 0
        var links: [URL?] = []
        /// Inside a <picture>, the images its <source>s name for light and dark windows.
        var sources: (light: URL?, dark: URL?)?
        var link: URL? { links.last ?? nil }

        mutating func apply(_ tag: HTMLTag, baseURL: URL) {
            let delta = tag.closing ? -1 : 1
            switch tag.name {
            case "b", "strong": bold = max(0, bold + delta)
            case "i", "em", "cite", "var", "dfn": italic = max(0, italic + delta)
            case "code", "kbd", "samp", "tt": mono = max(0, mono + delta)
            case "sub": sub = max(0, sub + delta)
            case "sup": sup = max(0, sup + delta)
            case "s", "strike", "del": strike = max(0, strike + delta)
            case "u", "ins": underline = max(0, underline + delta)
            case "mark": mark = max(0, mark + delta)
            case "a":
                if tag.closing { if !links.isEmpty { links.removeLast() } }
                else { links.append(tag.attributes["href"].flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }) }
            case "picture":
                sources = tag.closing ? nil : (nil, nil)
            case "source":
                // The first candidate of a srcset will do: the page is drawn at one size.
                guard !tag.closing, sources != nil, let candidate = tag.attributes["srcset"]?.split(separator: ",").first?.split(separator: " ").first,
                      let url = URL(string: String(candidate), relativeTo: baseURL)?.absoluteURL else { break }
                let media = (tag.attributes["media"] ?? "").lowercased().replacingOccurrences(of: " ", with: "")
                if media.contains("prefers-color-scheme:dark") { sources?.dark = url }
                else if media.contains("prefers-color-scheme:light") { sources?.light = url }
            default: break
            }
        }
    }

    private let baseURL: URL
    private let theme: Theme
    private let output = NSMutableAttributedString()
    private var quoteBlocks: [Int: NSTextBlock] = [:]
    private var alertColors: [Int: NSColor] = [:]
    private var tables: [Int: NSTextTable] = [:]
    private var columnWidths: [ObjectIdentifier: [CGFloat]] = [:]
    private var measuredCells: [ObjectIdentifier: Int] = [:]
    private var startedItems = Set<Int>()
    private var slugCounts: [String: Int] = [:]
    private var styles: [String: NSParagraphStyle] = [:]
    private var listTail: NSRange?
    private var lastListID: Int?
    private var lastBox: AnyObject?
    private var htmlTables = 0
    private var htmlLists = 0
    /// Alignment asked for by enclosing HTML elements; a centring div around Markdown reaches it this way.
    private var htmlAlignments: [NSTextAlignment?] = []
    private var cells: [ObjectIdentifier: [NSTextTableBlock]] = [:]
    private var spans: [ObjectIdentifier: [(column: Int, count: Int, width: CGFloat)]] = [:]
    /// The Markdown table being written and its last cell, so that empty cells can be filled in.
    private struct OpenTable {
        let id: Int, columns: [PresentationIntent.TableColumn], quotes: [NSTextBlock], alert: NSColor?
        var row = 0, column = -1
    }
    private var openTable: OpenTable?
    private var formulas: [MarkdownExtensions.Formula] = []
    /// The last equation number used, so that equations number on through the document.
    private var equations = 0
    /// highlight.js, started for the first code block and dropped when rendering ends.
    /// Kept alive it would hold about 7 MB; this way it leaves about 1.
    private lazy var engine: HighlightEngine? = HighlightEngine(theme: theme)

    init(baseURL: URL, theme: Theme) {
        self.baseURL = baseURL
        self.theme = theme
    }

    func render(_ markdown: String) -> NSAttributedString {
        var body = markdown
        if let match = markdown.range(of: #"^---\r?\n[\s\S]*?\r?\n---[ \t]*(?:\r?\n|$)"#, options: .regularExpression) {
            let inner = markdown[match].split(separator: "\n", omittingEmptySubsequences: false).dropFirst().dropLast(2)
            appendBoxed(inner.joined(separator: "\n"), font: theme.font(size: theme.scaled(12.8), mono: true), color: theme.muted,
                        fill: nil, border: theme.border)
            body.removeSubrange(match)
        }
        body = MarkdownExtensions.apply(body, baseURL: baseURL, formulas: &formulas)
        body = linkedImagesAsHTML(body)
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true, interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: body, options: options, baseURL: baseURL) else {
            return NSAttributedString(string: markdown, attributes: [.font: theme.font(size: theme.bodySize), .foregroundColor: theme.text])
        }

        // Slicing text out of an AttributedString run by run is slow, so the text comes from an
        // NSAttributedString copy, whose attribute runs line up one to one with the Swift runs.
        let copy = NSAttributedString(parsed)
        let characters = copy.string as NSString
        var ranges: [NSRange] = []
        copy.enumerateAttributes(in: NSRange(location: 0, length: copy.length)) { _, range, _ in ranges.append(range) }
        let runs = Array(parsed.runs)
        let aligned = ranges.count == runs.count
        let text: (Int) -> String = { aligned ? characters.substring(with: ranges[$0]) : String(parsed[runs[$0].range].characters) }

        // Runs that share their innermost block belong to one paragraph, cell or code block.
        var block: [Piece] = []
        var blockID: Int?
        var htmlBlocks = 0
        for (index, run) in runs.enumerated() {
            let id: Int
            if let leaf = run.presentationIntent?.components.first { id = leaf.identity } else { htmlBlocks += 1; id = -htmlBlocks }
            if id != blockID, !block.isEmpty {
                append(block)
                block.removeAll(keepingCapacity: true)
            }
            blockID = id
            block.append((run, text(index)))
        }
        if !block.isEmpty { append(block) }
        finishTable()
        fitTables()
        engine = nil   // the JavaScript engine only lives for one render
        return output
    }

    private static let calloutMarker = try! NSRegularExpression(pattern: #"^\[!(\w+)\][+-]?[ \t]*"#)

    private static let linkedImage = try! NSRegularExpression(
        pattern: #"\[!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#)

    /// Foundation keeps only the alt text of an image inside a link, so a linked image
    /// (the badges at the top of most READMEs) is handed over as HTML instead.
    private func linkedImagesAsHTML(_ markdown: String) -> String {
        let source = markdown as NSString
        let whole = NSRange(location: 0, length: source.length)
        let matches = NativeRenderer.linkedImage.matches(in: markdown, range: whole)
        guard !matches.isEmpty else { return markdown }
        // Fenced code shows the Markdown as written.
        var fences: [NSRange] = []
        var fenceStart: Int?
        source.enumerateSubstrings(in: whole, options: .byLines) { line, range, _, _ in
            guard let line = line?.drop(while: { $0 == " " }), line.hasPrefix("```") || line.hasPrefix("~~~") else { return }
            if let start = fenceStart {
                fences.append(NSRange(location: start, length: range.location + range.length - start))
                fenceStart = nil
            } else {
                fenceStart = range.location
            }
        }
        if let start = fenceStart { fences.append(NSRange(location: start, length: source.length - start)) }
        let result = NSMutableString(string: markdown)
        for match in matches.reversed() where !fences.contains(where: { NSLocationInRange(match.range.location, $0) }) {
            let alt = source.substring(with: match.range(at: 1)).replacingOccurrences(of: "\"", with: "")
            let image = source.substring(with: match.range(at: 2)), target = source.substring(with: match.range(at: 3))
            result.replaceCharacters(in: match.range, with: "<a href=\"\(target)\"><img src=\"\(image)\" alt=\"\(alt)\"></a>")
        }
        return result as String
    }

    // MARK: Blocks

    private func append(_ pieces: [Piece]) {
        let components = pieces[0].run.presentationIntent?.components ?? []
        var quotes: [NSTextBlock] = []
        var alert: NSColor?
        var listDepth = 0, item: (id: Int, ordinal: Int, ordered: Bool)?
        var table: (id: Int, columns: [PresentationIntent.TableColumn])?, row = 0, column = 0, isHeaderRow = false
        for (index, component) in components.enumerated().reversed() {
            switch component.kind {
            case .blockQuote:
                quotes.append(quoteBlock(component.identity))
                alert = alertColors[component.identity] ?? alert
            case .listItem(let ordinal):
                listDepth += 1
                if case .orderedList = components[index + 1].kind { item = (component.identity, ordinal, true) }
                else { item = (component.identity, ordinal, false) }
            case .table(let columns): table = (component.identity, columns)
            case .tableHeaderRow: isHeaderRow = true
            case .tableRow(let rowIndex): row = rowIndex
            case .tableCell(let columnIndex): column = columnIndex
            default: break
            }
        }
        if let table {
            if openTable?.id != table.id {
                finishTable()
                openTable = OpenTable(id: table.id, columns: table.columns, quotes: quotes, alert: alert)
            }
            fillCells(upTo: isHeaderRow ? 0 : row, column)
        } else {
            finishTable()
        }

        // The parser hands raw HTML blocks over untouched.
        if pieces[0].run.inlinePresentationIntent?.contains(.blockHTML) == true {
            html(pieces.map(\.text).joined(), inside: quotes, alert: alert)
            return
        }
        guard let leaf = components.first else { return }

        switch leaf.kind {
        case .codeBlock(let language):
            var code = written(pieces.map(\.text).joined())   // an indented block is not kept from the math pass
            if code.hasSuffix("\n") { code.removeLast() }
            appendCode(code, language: language, inside: quotes, indent: CGFloat(listDepth) * theme.scaled(32))
            return
        case .thematicBreak:
            rule(inside: quotes)
            return
        default: break
        }

        var paragraph = Paragraph(quotes: quotes, size: theme.bodySize, color: theme.text)
        if case .header(let level) = leaf.kind { paragraph.heading = min(max(level, 1), 6) }
        if let openTable, table != nil { paragraph = cell(of: openTable, row: isHeaderRow ? 0 : row, column: column) }
        if paragraph.cell == nil, let pending = htmlAlignments.last ?? nil { paragraph.alignment = pending }
        if let item {
            paragraph.listDepth = listDepth
            paragraph.listID = components.last { if case .orderedList = $0.kind { return true }; if case .unorderedList = $0.kind { return true }; return false }?.identity
            if startedItems.insert(item.id).inserted { paragraph.marker = item.ordered ? "\(item.ordinal)." : "•" }
        }
        // > [!NOTE] and friends: a coloured bar and a title instead of the marker. Obsidian
        // adds more kinds, a title after the marker, and a fold sign that is ignored here.
        // The title is the marker's line; the rest of the paragraph is the body.
        var pieces = pieces
        if let quoteID = components.first(where: { if case .blockQuote = $0.kind { return true } else { return false } })?.identity,
           alertColors[quoteID] == nil, let first = pieces.first,
           let match = NativeRenderer.calloutMarker.firstMatch(in: first.text, range: NSRange(location: 0, length: (first.text as NSString).length)) {
            let found = theme.callout((first.text as NSString).substring(with: match.range(at: 1)))
            alertColors[quoteID] = found.color
            alert = found.color
            quoteBlock(quoteID).setBorderColor(found.color, for: .minX)
            let lineEnd = pieces.firstIndex { piece in
                let intents = piece.run.inlinePresentationIntent ?? []
                return intents.contains(.softBreak) || intents.contains(.lineBreak) || piece.text == "\n"
            }
            var titleLine = Array(pieces[..<(lineEnd ?? pieces.count)])
            titleLine[0].text = (first.text as NSString).substring(from: match.range.length)
            pieces = lineEnd.map { Array(pieces[($0 + 1)...]) } ?? []
            let custom = inline(titleLine, size: theme.bodySize, bold: true, color: found.color)
            let title = custom.string.trimmingCharacters(in: .whitespaces).isEmpty
                ? NSMutableAttributedString(string: found.title, attributes: [.font: theme.font(size: theme.bodySize, bold: true), .foregroundColor: found.color])
                : custom
            separate(quotes)
            let style = NSMutableParagraphStyle()
            style.textBlocks = quotes
            style.paragraphSpacing = theme.scaled(4)
            title.append(NSAttributedString(string: "\n"))
            title.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: title.length))
            output.append(title)
            if pieces.isEmpty { return }
        }

        let (size, bold, color) = textStyle(heading: paragraph.heading, header: isHeaderRow, quotes: quotes, alert: alert)
        paragraph.size = size
        paragraph.color = color
        let text = inline(pieces, size: size, bold: bold, color: color)

        if paragraph.marker != nil, text.string.hasPrefix("[ ] ") || text.string.lowercased().hasPrefix("[x] ") {
            paragraph.marker = text.string.hasPrefix("[ ] ") ? "☐" : "☑"
            text.deleteCharacters(in: NSRange(location: 0, length: 4))
        }
        emit(text, paragraph)
    }

    private func textStyle(heading: Int?, header: Bool, quotes: [NSTextBlock], alert: NSColor?) -> (size: CGFloat, bold: Bool, color: NSColor) {
        var size = theme.bodySize, bold = header
        var color = quotes.isEmpty || alert != nil ? theme.text : theme.muted
        if let heading {
            size = theme.headingSizes[heading - 1]
            bold = true
            if heading == 6 { color = theme.muted }
        }
        return (size, bold, color)
    }

    /// Adds one paragraph to the output with everything its kind implies.
    private func emit(_ text: NSMutableAttributedString, _ paragraph: Paragraph) {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = theme.lineSpacing
        style.paragraphSpacing = theme.scaled(16)
        var blocks = paragraph.quotes
        var prefix = ""

        if let level = paragraph.heading {
            let size = paragraph.size
            style.lineHeightMultiple = 1.1
            style.paragraphSpacing = size * 0.6
            style.paragraphSpacingBefore = size * 0.9
            if level <= 2 {
                let underline = NativeRenderer.fullWidthBlock()
                underline.setBorderColor(theme.border)
                underline.setWidth(1, type: .absoluteValueType, for: .border, edge: .maxY)
                underline.setWidth(size * 0.3, type: .absoluteValueType, for: .padding, edge: .maxY)
                underline.setWidth(size * 0.6, type: .absoluteValueType, for: .margin, edge: .maxY)
                blocks.append(underline)
                style.paragraphSpacing = 0
            }
        }
        if let cell = paragraph.cell {
            // A cell inside another text block makes TextKit throw while drawing.
            blocks = [cell]
            style.paragraphSpacing = 0
            measure(text, in: cell)
        }
        if let alignment = paragraph.alignment { style.alignment = alignment }
        // A line is as tall as its tallest glyph times the multiple, which above a big
        // picture is a blank band, so a paragraph with one keeps its natural height.
        if tallestPicture(in: text) > paragraph.size * 2 { style.lineHeightMultiple = 1 }
        if paragraph.listDepth > 0 {
            let indent = CGFloat(paragraph.listDepth) * theme.scaled(32)
            style.headIndent = indent
            style.firstLineHeadIndent = indent
            style.paragraphSpacing = theme.scaled(4)
            if let marker = paragraph.marker {
                prefix = marker
                style.firstLineHeadIndent = indent - theme.scaled(24)
                style.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
            } else {
                style.paragraphSpacingBefore = theme.scaled(8)   // a further paragraph inside an item
            }
        }
        separate(blocks)

        if let level = paragraph.heading {
            let slug = MarkdownExtensions.slug(text.string)
            let count = slugCounts[slug, default: 0]
            slugCounts[slug] = count + 1
            let anchor = count == 0 ? slug : "\(slug)-\(count)"
            anchors[anchor] = output.length
            headings.append(Heading(level: level, title: text.string.trimmingCharacters(in: .whitespacesAndNewlines), anchor: anchor))
        }

        // The last paragraph of a list gets the normal gap below it, also before another list.
        if paragraph.listDepth == 0 || paragraph.listID != lastListID, let tail = listTail,
           let last = output.attribute(.paragraphStyle, at: tail.location, effectiveRange: nil) as? NSParagraphStyle {
            let spaced = last.mutableCopy() as! NSMutableParagraphStyle
            spaced.paragraphSpacing = theme.scaled(16)
            output.addAttribute(.paragraphStyle, value: spaced, range: tail)
        }
        lastListID = paragraph.listID

        style.textBlocks = blocks
        if !prefix.isEmpty {
            text.insert(NSAttributedString(string: prefix + "\t", attributes: [.font: theme.font(size: paragraph.size), .foregroundColor: paragraph.color]), at: 0)
        }
        text.append(NSAttributedString(string: "\n", attributes: [.font: theme.font(size: paragraph.size)]))
        text.addAttribute(.paragraphStyle, value: shared(style), range: NSRange(location: 0, length: text.length))
        let start = output.length
        output.append(text)
        listTail = paragraph.listDepth == 0 ? nil : NSRange(location: start, length: text.length)
    }

    /// The height of the tallest image in the text; a remote one, not yet fetched, counts as tall.
    private func tallestPicture(in text: NSAttributedString) -> CGFloat {
        let whole = NSRange(location: 0, length: text.length)
        guard text.containsAttachments(in: whole) else { return 0 }
        var tallest: CGFloat = 0
        text.enumerateAttribute(.attachment, in: whole) { value, _, _ in
            guard let picture = (value as? NSTextAttachment)?.image else { return }
            tallest = max(tallest, picture.size == NSSize(width: 1, height: 1) ? .greatestFiniteMagnitude : picture.size.height)
        }
        return tallest
    }

    /// TextKit draws neighbouring text blocks that look alike as a single box, so a
    /// thin empty paragraph goes between two different ones.
    private func separate(_ blocks: [NSTextBlock]) {
        let outermost = blocks.first
        let box: AnyObject? = (outermost as? NSTextTableBlock)?.table ?? outermost
        if let box, let lastBox, box !== lastBox {
            let style = NSMutableParagraphStyle()
            style.maximumLineHeight = 1
            output.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: style, .font: theme.font(size: 1)]))
        }
        lastBox = box
    }

    /// Most paragraphs are styled alike, so identical styles are stored once.
    private func shared(_ style: NSMutableParagraphStyle) -> NSParagraphStyle {
        guard style.textBlocks.isEmpty else { return style }
        let key = "\(style.headIndent)/\(style.firstLineHeadIndent)/\(style.paragraphSpacing)/\(style.paragraphSpacingBefore)/\(style.lineHeightMultiple)/\(style.alignment.rawValue)"
        if let cached = styles[key] { return cached }
        styles[key] = style
        return style
    }

    private func appendCode(_ code: String, language: String?, inside quotes: [NSTextBlock], indent: CGFloat = 0) {
        let kind = language?.lowercased()
        let width = theme.figureWidth - indent - CGFloat(quotes.count) * quoteInset
        if kind == "math", let math = Math.image(code, display: true, size: theme.bodySize, width: width, color: theme.text, equations: &equations) {
            let attachment = FittingAttachment()
            attachment.image = math.image
            attachment.bounds = NSRect(origin: .zero, size: math.image.size)
            separate(quotes)
            output.append(NSAttributedString(string: "\u{FFFC}\n", attributes: [
                .attachment: attachment, .paragraphStyle: NativeRenderer.figureBlock(inside: quotes, indent: indent),
                .font: theme.font(size: theme.bodySize), ColumnTextView.written: "$$\n\(code)\n$$\n"]))
            appendGap(inside: quotes)
            return
        }
        // Math that cannot be drawn shows as written.
        let drawing = kind != "mermaid" && code.unicodeScalars.contains { (0x2500...0x259F).contains($0.value) }
        let codeSize = theme.scaled(14)
        let range = appendBoxed(code, font: drawing ? Theme.drawingFont(size: codeSize) : theme.font(size: codeSize, mono: true),
                                color: theme.text, fill: theme.subtle, border: nil, inside: quotes, indent: indent, wraps: !drawing)
        if drawing { markDrawing(NSRange(location: range.location, length: range.length + 1), size: codeSize, room: width - theme.scaled(32)) }
        if kind != "mermaid" { output.addAttribute(NativeRenderer.code, value: code, range: range) }
        guard kind == "mermaid" else {
            if let language, !language.isEmpty, kind != "math" { engine?.highlight(output, in: range, language: language) }
            return
        }
        // The code stands in for the diagram, with its line break, until the drawing takes its paragraph.
        output.addAttribute(Diagrams.placeholder, value: diagrams.count, range: NSRange(location: range.location, length: range.length + 1))
        diagrams.append(Diagram(source: code, width: width, theme: theme, block: NativeRenderer.figureBlock(inside: quotes, indent: indent),
                                written: "```mermaid\n\(code)\n```\n"))
    }

    /// The centred paragraph of its own a drawn formula or diagram takes.
    private static func figureBlock(inside quotes: [NSTextBlock], indent: CGFloat) -> NSParagraphStyle {
        let block = NSMutableParagraphStyle()
        block.textBlocks = quotes
        block.alignment = .center
        block.headIndent = indent
        block.firstLineHeadIndent = indent
        return block
    }

    /// Attribute key marking a code block's text, whose value is the code, for its copy button.
    static let code = NSAttributedString.Key("MarkviewCode")

    /// Attribute key marking a drawing: a code block drawn with box-drawing characters, such as
    /// a flow chart or the output of `tree`. Wrapping would tear it apart, so its lines never
    /// wrap; its text shrinks instead until the widest line fits, as a wide formula does.
    static let drawing = NSAttributedString.Key("MarkviewDrawing")

    /// A drawing's widest line in columns, how much narrower than the text container its lines
    /// are, and the size of code, which is the largest it is drawn.
    struct Drawing: Hashable {
        let columns: Int
        let margin: CGFloat
        let size: CGFloat
    }

    /// Characters the monospaced font lacks come from other fonts, at other widths, which would
    /// knock the lines of a drawing out of line. Each is kerned to the columns a terminal gives it.
    private func markDrawing(_ range: NSRange, size: CGFloat, room: CGFloat) {
        let font = Theme.drawingFont(size: size)
        let column = ("0" as NSString).size(withAttributes: [.font: font]).width
        var widths: [Character: CGFloat] = [:]
        var widest = 0, columns = 0, location = range.location
        for character in (output.string as NSString).substring(with: range) {
            let length = character.utf16.count
            defer { location += length }
            if character.isNewline {
                widest = max(widest, columns)
                columns = 0
            } else if character.isASCII {
                columns += 1
            } else {
                let width = widths[character] ?? (String(character) as NSString).size(withAttributes: [.font: font]).width
                widths[character] = width
                let span = width > 0 ? (NativeRenderer.isWide(character) ? 2 : 1) : 0
                columns += span
                let kern = CGFloat(span) * column - width
                if abs(kern) > 0.01 { output.addAttribute(.kern, value: kern, range: NSRange(location: location, length: length)) }
            }
        }
        guard max(widest, columns) > 0 else { return }
        hasDrawings = true
        output.addAttribute(NativeRenderer.drawing, value: Drawing(columns: max(widest, columns), margin: theme.columnWidth - room, size: size), range: range)
        NativeRenderer.fitDrawings(in: output, width: theme.columnWidth, within: range)
    }

    /// Whether a terminal gives a character two columns, as it does Chinese, Japanese and Korean
    /// characters and emoji. Their widths in the fonts they come from vary.
    private static func isWide(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        if scalar.properties.isEmojiPresentation || character.unicodeScalars.contains("\u{FE0F}") { return true }
        switch scalar.value {
        case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xA000...0xA4CF,
             0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60, 0xFFE0...0xFFE6, 0x20000...0x3FFFD: return true
        default: return false
        }
    }

    /// Sizes each drawing so that its widest line fits a text container this wide.
    static func fitDrawings(in text: NSMutableAttributedString, width: CGFloat, within range: NSRange? = nil) {
        text.beginEditing()
        text.enumerateAttribute(drawing, in: range ?? NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let drawing = value as? Drawing, let font = text.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont else { return }
            let column = ("0" as NSString).size(withAttributes: [.font: font]).width / font.pointSize
            let size = max(1, min(drawing.size, floor((width - drawing.margin) / (CGFloat(drawing.columns) * column) * 4) / 4))
            guard size != font.pointSize else { return }
            text.addAttribute(.font, value: Theme.drawingFont(size: size), range: range)
            // Characters from other fonts scale with it, and so do the kerns that align them.
            text.enumerateAttribute(.kern, in: range) { kern, part, _ in
                if let kern = kern as? CGFloat { text.addAttribute(.kern, value: kern * size / font.pointSize, range: part) }
            }
        }
        text.endEditing()
    }

    /// Code blocks and front matter: monospaced text in a filled or outlined box.
    @discardableResult
    private func appendBoxed(_ text: String, font: NSFont, color: NSColor, fill: NSColor?, border: NSColor?,
                             inside quotes: [NSTextBlock] = [], indent: CGFloat = 0, wraps: Bool = true) -> NSRange {
        let box = NativeRenderer.fullWidthBlock()
        box.backgroundColor = fill
        box.setWidth(theme.scaled(16), type: .absoluteValueType, for: .padding)
        if indent > 0 { box.setWidth(indent, type: .absoluteValueType, for: .margin, edge: .minX) }
        if let border {
            box.setBorderColor(border)
            box.setWidth(1, type: .absoluteValueType, for: .border)
        }
        let style = NSMutableParagraphStyle()
        style.textBlocks = quotes + [box]
        // A drawing's lines touch, as in a terminal, so that its upright strokes join.
        style.lineHeightMultiple = wraps ? 1.2 : 1
        if wraps {
            // A line too long for the box wraps; the continuation is indented so it reads as one line.
            style.headIndent = ("00" as NSString).size(withAttributes: [.font: font]).width
        } else {
            // A drawing is sized to fit, so this only trims a line that rounding leaves a hair too long.
            style.lineBreakMode = .byClipping
        }
        separate(style.textBlocks)
        let start = output.length
        output.append(NSAttributedString(string: text + "\n", attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style]))
        appendGap(inside: quotes)
        return NSRange(location: start, length: (text as NSString).length)
    }

    /// The space below a block. A filled box paints its bottom margin too, so it is a paragraph of its own.
    private func appendGap(inside quotes: [NSTextBlock]) {
        let gap = NSMutableParagraphStyle()
        gap.textBlocks = quotes
        gap.minimumLineHeight = theme.scaled(16)
        gap.maximumLineHeight = theme.scaled(16)
        output.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: gap, .font: theme.font(size: 1)]))
        lastBox = quotes.first
    }

    private func rule(inside quotes: [NSTextBlock]) {
        let rule = NativeRenderer.fullWidthBlock()
        rule.setBorderColor(theme.border)
        rule.setWidth(1, type: .absoluteValueType, for: .border, edge: .minY)
        rule.setWidth(theme.scaled(16), type: .absoluteValueType, for: .margin, edge: .minY)
        rule.setWidth(theme.scaled(16), type: .absoluteValueType, for: .margin, edge: .maxY)
        let style = NSMutableParagraphStyle()
        style.textBlocks = quotes + [rule]
        style.maximumLineHeight = 1
        separate(style.textBlocks)
        output.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: style, .font: theme.font(size: 1)]))
    }

    /// How far a quote moves its text in: its bar and the padding after it.
    private var quoteInset: CGFloat { 4 + theme.scaled(16) }

    private func quoteBlock(_ identity: Int) -> NSTextBlock {
        if let block = quoteBlocks[identity] { return block }
        let block = NativeRenderer.fullWidthBlock()
        block.setBorderColor(theme.border, for: .minX)
        block.setWidth(4, type: .absoluteValueType, for: .border, edge: .minX)
        block.setWidth(theme.scaled(16), type: .absoluteValueType, for: .padding, edge: .minX)
        block.setWidth(theme.scaled(16), type: .absoluteValueType, for: .margin, edge: .maxY)
        quoteBlocks[identity] = block
        return block
    }

    // MARK: Tables

    private func textTable(_ identity: Int, columns: Int, inside quotes: [NSTextBlock], alert: NSColor?) -> NSTextTable {
        if let table = tables[identity] { return table }
        let table = NSTextTable()
        table.numberOfColumns = max(columns, 1)
        table.collapsesBorders = true
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        table.setWidth(theme.scaled(16), type: .absoluteValueType, for: .margin, edge: .maxY)
        // Its cells cannot sit inside the quote's block, so the table wears the quote's bar itself.
        if !quotes.isEmpty {
            table.setBorderColor(alert ?? theme.border, for: .minX)
            table.setWidth(4, type: .absoluteValueType, for: .border, edge: .minX)
            table.setWidth(theme.scaled(16), type: .absoluteValueType, for: .padding, edge: .minX)
            table.setWidth(CGFloat(quotes.count - 1) * quoteInset, type: .absoluteValueType, for: .margin, edge: .minX)
        }
        tables[identity] = table
        return table
    }

    private func cellBlock(_ table: NSTextTable, row: Int, column: Int, columnSpan: Int = 1, rowSpan: Int = 1, header: Bool) -> NSTextTableBlock {
        let cell = NSTextTableBlock(table: table, startingRow: row, rowSpan: rowSpan, startingColumn: column, columnSpan: columnSpan)
        cell.setBorderColor(theme.border)
        cell.setWidth(1, type: .absoluteValueType, for: .border)
        cell.setWidth(theme.scaled(6), type: .absoluteValueType, for: .padding)
        cell.setWidth(theme.scaled(13), type: .absoluteValueType, for: .padding, edge: .minX)
        cell.setWidth(theme.scaled(13), type: .absoluteValueType, for: .padding, edge: .maxX)
        if header { cell.backgroundColor = theme.subtle }
        return cell
    }

    /// The room a cell's padding and border take beside its text.
    private var cellInsets: CGFloat { 2 * theme.scaled(13) + 1 }

    /// A paragraph that is a cell of a Markdown table; row 0 is the header row.
    private func cell(of table: OpenTable, row: Int, column: Int) -> Paragraph {
        var paragraph = Paragraph(quotes: table.quotes, size: theme.bodySize, color: theme.text)
        let header = row == 0
        paragraph.cell = cellBlock(textTable(table.id, columns: table.columns.count, inside: table.quotes, alert: table.alert),
                                   row: row, column: column, header: header)
        switch column < table.columns.count ? table.columns[column].alignment : .left {
        case .center: paragraph.alignment = .center
        case .right: paragraph.alignment = .right
        default: paragraph.alignment = header ? .center : .left
        }
        return paragraph
    }

    /// The parser leaves empty cells out, a wholly empty row too, and TextKit moves the rest
    /// of a row into the gap, so the cells missing before this one are written empty.
    private func fillCells(upTo row: Int, _ column: Int) {
        guard var table = openTable else { return }
        table.column += 1
        while table.row < row || (table.row == row && table.column < column) {
            if table.column >= table.columns.count {
                table.row += 1
                table.column = 0
                continue
            }
            var paragraph = cell(of: table, row: table.row, column: table.column)
            (paragraph.size, _, paragraph.color) = textStyle(heading: nil, header: table.row == 0, quotes: table.quotes, alert: table.alert)
            emit(NSMutableAttributedString(), paragraph)
            table.column += 1
        }
        table.column = column
        openTable = table
    }

    /// Fills in the empty cells that end the table's last row, and leaves the space below it.
    private func finishTable() {
        guard let table = openTable else { return }
        fillCells(upTo: table.row, table.columns.count)
        openTable = nil
        // A table is in no quote's block (see `textTable`), so neither is the space below it.
        appendGap(inside: [])
    }

    /// Remembers how wide a cell wants to be. Measuring stops after 2,000 cells; a table
    /// that large spans the column anyway.
    private func measure(_ text: NSAttributedString, in cell: NSTextTableBlock) {
        let id = ObjectIdentifier(cell.table)
        let count = measuredCells[id, default: 0] + 1
        measuredCells[id] = count
        guard count <= 2000 else { return }
        cells[id, default: []].append(cell)
        let width = ceil(text.size().width)
        if cell.columnSpan > 1 {
            spans[id, default: []].append((cell.startingColumn, cell.columnSpan, width))
            return
        }
        var widths = columnWidths[id] ?? []
        while widths.count <= cell.startingColumn { widths.append(0) }
        widths[cell.startingColumn] = max(widths[cell.startingColumn], width)
        columnWidths[id] = widths
    }

    /// A table is as wide as its content wants, up to the width of the column. Left to
    /// itself TextKit shares a table's width out evenly, so each column is told its width.
    private func fitTables() {
        for table in tables.values {
            let id = ObjectIdentifier(table)
            guard var widths = columnWidths[id], measuredCells[id, default: 0] <= 2000 else { continue }
            while widths.count < table.numberOfColumns { widths.append(0) }
            // A cell spanning several columns widens the ones it covers until it fits.
            for span in spans[id] ?? [] {
                let covered = span.column..<min(span.column + span.count, widths.count)
                guard !covered.isEmpty else { continue }
                let room = covered.reduce(0) { $0 + widths[$1] } + CGFloat(covered.count - 1) * cellInsets
                if span.width > room { for column in covered { widths[column] += (span.width - room) / CGFloat(covered.count) } }
            }
            let content = widths.reduce(0, +), padding = CGFloat(widths.count) * cellInsets
            let natural = (content + padding) * 1.05
            // In a quote the table has a bar and padding of its own, which its width must include.
            let insets = [NSTextBlock.Layer.padding, .border, .margin].reduce(0) { $0 + table.width(for: $1, edge: .minX) }
            guard content > 0, natural + insets < theme.columnWidth else { continue }
            fittedTables.append(FittedTable(table: table, width: natural + insets))
            let share = (natural - padding) / content
            for cell in cells[id] ?? [] where cell.columnSpan == 1 && cell.startingColumn < widths.count {
                cell.setContentWidth(widths[cell.startingColumn] * share / natural * 100, type: .percentageValueType)
            }
        }
        NativeRenderer.fitTables(fittedTables, width: theme.columnWidth)
    }

    /// A table narrower than the column, and its natural width. Its cells' widths are shares of
    /// the table's, but the table's own is a share of the text container's, so a narrower
    /// container, as in a small window or with a long line length, needs a larger share.
    struct FittedTable {
        let table: NSTextTable
        let width: CGFloat
    }

    /// Gives each table its natural width in a text container this wide, or all of it if that is less.
    static func fitTables(_ tables: [FittedTable], width: CGFloat) {
        for fitted in tables { fitted.table.setContentWidth(min(100, fitted.width / width * 100), type: .percentageValueType) }
    }

    /// A copy of the text with tables of its own, fitted to a text container this wide, and the
    /// pictures for light pages, as a page for printing wants. Tables are objects the text only
    /// points to, and the view's change with the view's width.
    static func copy(_ text: NSAttributedString, tables fitted: [FittedTable], fittedTo width: CGFloat) -> NSTextStorage {
        let copy = NSTextStorage(attributedString: text)
        var pictures: [(range: NSRange, light: NSImage?)] = []
        copy.enumerateAttribute(.attachment, in: NSRange(location: 0, length: copy.length)) { value, range, _ in
            if let picture = value as? AppearanceAttachment { pictures.append((range, picture.light)) }
        }
        for (range, light) in pictures.reversed() {
            guard let light else { copy.replaceCharacters(in: range, with: ""); continue }
            let plain = FittingAttachment()
            plain.clearsPadding = false
            plain.image = light
            copy.addAttribute(.attachment, value: plain, range: range)
        }
        var tables: [ObjectIdentifier: NSTextTable] = [:], cells: [ObjectIdentifier: NSTextTableBlock] = [:]
        func table(_ old: NSTextTable) -> NSTextTable {
            if let table = tables[ObjectIdentifier(old)] { return table }
            let table = NSTextTable()
            table.numberOfColumns = old.numberOfColumns
            table.layoutAlgorithm = old.layoutAlgorithm
            table.collapsesBorders = old.collapsesBorders
            table.hidesEmptyCells = old.hidesEmptyCells
            copyLook(of: old, to: table)
            tables[ObjectIdentifier(old)] = table
            return table
        }
        copy.beginEditing()
        copy.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: copy.length)) { value, range, _ in
            guard let style = value as? NSParagraphStyle, style.textBlocks.contains(where: { $0 is NSTextTableBlock }) else { return }
            let mapped = style.mutableCopy() as! NSMutableParagraphStyle
            mapped.textBlocks = style.textBlocks.map { block in
                guard let old = block as? NSTextTableBlock else { return block }
                if let cell = cells[ObjectIdentifier(old)] { return cell }
                let cell = NSTextTableBlock(table: table(old.table), startingRow: old.startingRow, rowSpan: old.rowSpan,
                                            startingColumn: old.startingColumn, columnSpan: old.columnSpan)
                copyLook(of: old, to: cell)
                cells[ObjectIdentifier(old)] = cell
                return cell
            }
            copy.addAttribute(.paragraphStyle, value: mapped, range: range)
        }
        copy.endEditing()
        fitTables(fitted.compactMap { old in tables[ObjectIdentifier(old.table)].map { FittedTable(table: $0, width: old.width) } }, width: width)
        return copy
    }

    /// Everything a text block has to show: its edges, colours, sizes and alignment.
    private static func copyLook(of old: NSTextBlock, to block: NSTextBlock) {
        for edge in [NSRectEdge.minX, .minY, .maxX, .maxY] {
            for layer in [NSTextBlock.Layer.padding, .border, .margin] {
                block.setWidth(old.width(for: layer, edge: edge), type: old.widthValueType(for: layer, edge: edge), for: layer, edge: edge)
            }
            block.setBorderColor(old.borderColor(for: edge), for: edge)
        }
        for dimension in [NSTextBlock.Dimension.width, .minimumWidth, .maximumWidth, .height, .minimumHeight, .maximumHeight] {
            block.setValue(old.value(for: dimension), type: old.valueType(for: dimension), for: dimension)
        }
        block.backgroundColor = old.backgroundColor
        block.verticalAlignment = old.verticalAlignment
    }

    // MARK: HTML

    /// Raw HTML blocks get the elements a README tends to use: paragraphs and headings,
    /// lists, tables, code, rules, images, details, and the inline tags. Any other tag is
    /// dropped and its text kept; comments, scripts and styles are dropped entirely.
    private func html(_ source: String, inside quotes: [NSTextBlock], alert: NSColor?) {
        var style = InlineStyle()
        var text = NSMutableAttributedString()
        var heading: Int?
        var summary = false
        var lists: [(ordered: Bool, count: Int)] = []
        var listID: Int?
        var marker: String?
        var table: (table: NSTextTable, row: Int, column: Int, columns: Int, occupied: Set<[Int]>)?
        var cell: (block: NSTextTableBlock, header: Bool, alignment: NSTextAlignment?, written: Bool)?
        var code: String?, codeLanguage: String?
        var skip = 0

        func currentStyle() -> (size: CGFloat, bold: Bool, color: NSColor) {
            let base = textStyle(heading: heading, header: cell?.header ?? false, quotes: quotes, alert: alert)
            return (base.size, base.bold || summary, base.color)
        }
        func flush(keepingEmpty: Bool = false) {
            defer { text = NSMutableAttributedString() }
            while let last = text.string.last, last.isWhitespace { text.deleteCharacters(in: NSRange(location: text.length - 1, length: 1)) }
            guard text.length > 0 || marker != nil || keepingEmpty else { return }
            cell?.written = true
            var paragraph = Paragraph(quotes: quotes, size: theme.bodySize, color: theme.text)
            paragraph.heading = heading
            paragraph.alignment = cell?.alignment ?? htmlAlignments.last ?? nil
            paragraph.cell = cell?.block
            paragraph.listDepth = lists.count
            paragraph.listID = lists.isEmpty ? nil : listID
            paragraph.marker = marker
            marker = nil
            let (size, _, color) = currentStyle()
            paragraph.size = size
            paragraph.color = color
            if summary {
                text.insert(NSAttributedString(string: "▸ ", attributes: [.font: theme.font(size: size, bold: true), .foregroundColor: color]), at: 0)
            }
            emit(text, paragraph)
        }
        func closeCell() {
            guard let open = cell else { return }
            // An empty cell is written too, or TextKit moves the rest of the row into its place.
            flush(keepingEmpty: !open.written)
            table?.column += open.block.columnSpan
            cell = nil
        }
        func closeTable() {
            closeCell()
            flush()
            guard let open = table else { return }
            open.table.numberOfColumns = max(open.columns, 1)
            table = nil
            appendGap(inside: [])
        }

        for token in HTMLScanner.tokens(source) {
            switch token {
            case .comment:
                continue
            case .text(let raw):
                if skip > 0 { continue }
                if code != nil { code! += written(raw); continue }
                var piece = raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                if text.length == 0 { piece = String(piece.drop { $0 == " " }) }
                if piece.isEmpty { continue }
                let (size, bold, color) = currentStyle()
                appendText(piece, to: text, attributes: attributes(style, intents: [], size: size, bold: bold, color: color, link: nil),
                           literal: style.mono > 0)
            case .tag(let tag):
                if !tag.closing, let id = tag.attributes["id"] ?? (tag.name == "a" ? tag.attributes["name"] : nil) { anchors[id] = output.length }
                switch tag.name {
                case "script", "style":
                    skip = max(0, skip + (tag.closing ? -1 : 1))
                case _ where skip > 0:
                    continue
                case "br":
                    if code == nil { text.append(NSAttributedString(string: "\u{2028}")) }
                case "img":
                    guard !tag.closing, let src = tag.attributes["src"], let url = URL(string: src, relativeTo: baseURL) else { continue }
                    text.append(image(url.absoluteURL, alt: tag.attributes["alt"] ?? "", width: dimension(tag.attributes["width"]),
                                      height: dimension(tag.attributes["height"]), link: style.link, sources: style.sources))
                case "p", "div", "center", "section", "article", "header", "footer", "main", "nav", "aside", "figure", "figcaption",
                     "blockquote", "dl", "dt", "dd", "address":
                    flush()
                    if tag.closing { if !htmlAlignments.isEmpty { htmlAlignments.removeLast() } }
                    else { htmlAlignments.append(tag.name == "center" ? .center : alignment(tag.attributes["align"]) ?? htmlAlignments.last ?? nil) }
                case "h1", "h2", "h3", "h4", "h5", "h6":
                    flush()
                    if tag.closing {
                        heading = nil
                        if !htmlAlignments.isEmpty { htmlAlignments.removeLast() }
                    } else {
                        heading = Int(String(tag.name.last!))
                        htmlAlignments.append(alignment(tag.attributes["align"]) ?? htmlAlignments.last ?? nil)
                    }
                case "ul", "ol":
                    flush()
                    if tag.closing { if !lists.isEmpty { lists.removeLast() } }
                    else {
                        if lists.isEmpty { htmlLists += 1; listID = -htmlLists }
                        lists.append((tag.name == "ol", 0))
                    }
                case "li":
                    flush()
                    if !tag.closing, !lists.isEmpty {
                        lists[lists.count - 1].count += 1
                        marker = lists[lists.count - 1].ordered ? "\(lists[lists.count - 1].count)." : "•"
                    }
                case "table":
                    closeTable()
                    if !tag.closing {
                        htmlTables += 1
                        table = (textTable(-htmlTables, columns: 1, inside: quotes, alert: alert), -1, 0, 0, [])
                    }
                case "tr":
                    closeCell()
                    if !tag.closing, table != nil { table!.row += 1; table!.column = 0 }
                case "td", "th":
                    closeCell()
                    guard !tag.closing, table != nil else { continue }
                    if table!.row < 0 { table!.row = 0 }
                    while table!.occupied.contains([table!.row, table!.column]) { table!.column += 1 }
                    let span = max(1, Int(tag.attributes["colspan"] ?? "") ?? 1), rows = max(1, Int(tag.attributes["rowspan"] ?? "") ?? 1)
                    for r in 1..<rows { for c in 0..<span { table!.occupied.insert([table!.row + r, table!.column + c]) } }
                    let header = tag.name == "th"
                    let block = cellBlock(table!.table, row: table!.row, column: table!.column, columnSpan: span, rowSpan: rows, header: header)
                    table!.columns = max(table!.columns, table!.column + span)
                    cell = (block, header, alignment(tag.attributes["align"]) ?? (header ? .center : .left), false)
                case "pre":
                    flush()
                    if tag.closing {
                        if var block = code {
                            if block.hasPrefix("\n") { block.removeFirst() }
                            if block.hasSuffix("\n") { block.removeLast() }
                            appendCode(block, language: codeLanguage, inside: quotes)
                        }
                        code = nil
                        codeLanguage = nil
                    } else {
                        code = ""
                    }
                case "code" where code != nil:
                    if let classes = tag.attributes["class"],
                       let language = classes.split(separator: " ").first(where: { $0.hasPrefix("language-") || $0.hasPrefix("lang-") }) {
                        codeLanguage = String(language.drop { $0 != "-" }.dropFirst())
                    }
                case "hr":
                    flush()
                    rule(inside: quotes)
                case "details":
                    flush()
                case "summary":
                    flush()
                    summary = !tag.closing
                default:
                    style.apply(tag, baseURL: baseURL)
                }
            }
        }
        closeTable()
        flush()
    }

    private func alignment(_ value: String?) -> NSTextAlignment? {
        switch value?.lowercased() {
        case "center": return .center
        case "right": return .right
        case "left": return .left
        case "justify": return .justified
        default: return nil
        }
    }

    /// A width or height attribute: a number of pixels, or a percentage of the column.
    private func dimension(_ value: String?) -> CGFloat? {
        guard let value, let number = Double(value.prefix { $0.isNumber || $0 == "." }), number > 0 else { return nil }
        return value.contains("%") ? theme.columnWidth * number / 100 : number
    }

    // MARK: Inline

    private func inline(_ pieces: [Piece], size: CGFloat, bold: Bool, color: NSColor) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        var style = InlineStyle()
        var skip = 0   // inside <script> or <style>
        for (run, piece) in pieces {
            let intents = run.inlinePresentationIntent ?? []
            if intents.contains(.inlineHTML) {
                for case .tag(let tag) in HTMLScanner.tokens(piece) {
                    if !tag.closing, let id = tag.attributes["id"] ?? (tag.name == "a" ? tag.attributes["name"] : nil) { anchors[id] = output.length }
                    switch tag.name {
                    case "script", "style":
                        skip = max(0, skip + (tag.closing ? -1 : 1))
                    case "br":
                        result.append(NSAttributedString(string: "\u{2028}"))
                    case "img":
                        if let src = tag.attributes["src"], let url = URL(string: src, relativeTo: baseURL) {
                            result.append(image(url.absoluteURL, alt: tag.attributes["alt"] ?? "", width: dimension(tag.attributes["width"]),
                                                height: dimension(tag.attributes["height"]), link: style.link, sources: style.sources))
                        }
                    default:
                        style.apply(tag, baseURL: baseURL)
                    }
                }
                continue
            }
            if skip > 0 { continue }
            if let imageURL = run.imageURL {
                result.append(image(imageURL, alt: piece, link: run.link ?? style.link))
                continue
            }
            let text = intents.contains(.lineBreak) ? "\u{2028}" : piece
            appendText(text, to: result, attributes: attributes(style, intents: intents, size: size, bold: bold, color: color, link: run.link),
                       literal: style.mono > 0)
        }
        return result
    }

    /// Appends text in which MarkdownExtensions may have left formula markers. Each formula
    /// is drawn, unless it is in code or cannot be drawn, and then it shows as written.
    private func appendText(_ text: String, to result: NSMutableAttributedString, attributes: [NSAttributedString.Key: Any], literal: Bool) {
        guard !formulas.isEmpty, NativeRenderer.hasFormula(text) else {
            result.append(NSAttributedString(string: text, attributes: attributes))
            return
        }
        if literal {
            result.append(NSAttributedString(string: written(text), attributes: attributes))
            return
        }
        var math = attributes
        math[.foregroundColor] = theme.muted
        math[BoxedLayoutManager.box] = nil
        let size = (attributes[.font] as? NSFont)?.pointSize ?? theme.bodySize
        for (number, part) in text.split(separator: MarkdownExtensions.formulaStart, omittingEmptySubsequences: false).enumerated() {
            var rest = part
            if number > 0, let end = part.firstIndex(of: MarkdownExtensions.formulaEnd), let index = Int(part[..<end]), index < formulas.count {
                let formula = formulas[index]
                if let drawn = Math.image(formula.display ? "\\displaystyle " + formula.tex : formula.tex, display: false, size: size,
                                          width: theme.figureWidth, color: theme.text, equations: &equations) {
                    let attachment = NSTextAttachment()
                    attachment.image = drawn.image
                    attachment.bounds = NSRect(x: 0, y: -drawn.depth, width: drawn.image.size.width, height: drawn.image.size.height)
                    var attributes = math
                    attributes[.attachment] = attachment
                    attributes[ColumnTextView.written] = formula.written
                    result.append(NSAttributedString(string: "\u{FFFC}", attributes: attributes))
                } else {
                    result.append(NSAttributedString(string: formula.written, attributes: math))
                }
                rest = part[part.index(after: end)...]
            }
            if !rest.isEmpty { result.append(NSAttributedString(string: String(rest), attributes: attributes)) }
        }
    }

    /// Searching by character would cost a tenth of a large document's render time.
    private static func hasFormula(_ text: String) -> Bool {
        text.unicodeScalars.contains(MarkdownExtensions.formulaStart.unicodeScalars.first!)
    }

    /// Text with any formula markers put back as the formulas were written.
    private func written(_ text: String) -> String {
        guard !formulas.isEmpty, NativeRenderer.hasFormula(text) else { return text }
        var result = ""
        for (number, part) in text.split(separator: MarkdownExtensions.formulaStart, omittingEmptySubsequences: false).enumerated() {
            if number > 0, let end = part.firstIndex(of: MarkdownExtensions.formulaEnd), let index = Int(part[..<end]), index < formulas.count {
                result += formulas[index].written + part[part.index(after: end)...]
            } else {
                result += part
            }
        }
        return result
    }

    private func attributes(_ style: InlineStyle, intents: InlinePresentationIntent, size: CGFloat, bold: Bool, color: NSColor,
                            link: URL?) -> [NSAttributedString.Key: Any] {
        let mono = style.mono > 0 || intents.contains(.code)
        var fontSize = mono ? size * 0.875 : size
        if style.sub > 0 || style.sup > 0 { fontSize *= 0.75 }
        var result: [NSAttributedString.Key: Any] = [
            .font: theme.font(size: fontSize, bold: bold || style.bold > 0 || intents.contains(.stronglyEmphasized),
                              italic: style.italic > 0 || intents.contains(.emphasized), mono: mono),
            .foregroundColor: color,
        ]
        if mono { result[BoxedLayoutManager.box] = theme.subtle }
        if style.mark > 0 { result[BoxedLayoutManager.box] = theme.mark }
        if style.strike > 0 || intents.contains(.strikethrough) { result[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if style.underline > 0 { result[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if style.sup > 0 { result[.baselineOffset] = size * 0.35 } else if style.sub > 0 { result[.baselineOffset] = -size * 0.15 }
        if let link = link ?? style.link { result[.link] = link }
        return result
    }

    /// A picture, or its alt text if it cannot be shown. READMEs on GitHub often carry one for
    /// each appearance: in a <picture> whose sources name them, or as two images marked
    /// #gh-light-mode-only and #gh-dark-mode-only. Those take an AppearanceAttachment.
    private func image(_ url: URL, alt: String, width: CGFloat? = nil, height: CGFloat? = nil, link: URL? = nil,
                       sources: (light: URL?, dark: URL?)? = nil) -> NSAttributedString {
        var light: URL? = url, dark: URL? = url
        switch url.fragment {
        case "gh-dark-mode-only": light = nil
        case "gh-light-mode-only": dark = nil
        default: break
        }
        if let sources, sources.light != nil || sources.dark != nil {
            light = sources.light ?? url
            dark = sources.dark ?? url
        }
        let attachment: NSTextAttachment
        if let url = light, light == dark {
            let fitting = FittingAttachment()
            fitting.clearsPadding = false
            guard let picture = picture(url, width: width, height: height, place: { fitting.image = $0 }) else { return altText(alt) }
            fitting.image = picture
            attachment = fitting
        } else {
            let modal = AppearanceAttachment()
            modal.light = light.flatMap { picture($0, width: width, height: height) { [weak modal] in modal?.light = $0 } }
            modal.dark = dark.flatMap { picture($0, width: width, height: height) { [weak modal] in modal?.dark = $0 } }
            guard modal.light != nil || modal.dark != nil else { return altText(alt) }
            hasAppearanceImages = true
            attachment = modal
        }
        let result = NSMutableAttributedString(attachment: attachment)
        if let link { result.addAttribute(.link, value: link, range: NSRange(location: 0, length: result.length)) }
        return result
    }

    /// A local picture at once, or a stand-in for one from the web, which is fetched once the
    /// text shows and handed to `place`. Nil for one that cannot be shown.
    private func picture(_ url: URL, width: CGFloat?, height: CGFloat?, place: @escaping (NSImage) -> Void) -> NSImage? {
        if url.isFileURL {
            guard let picture = NSImage(contentsOf: URL(fileURLWithPath: url.path)) else { return nil }
            NativeRenderer.fit(picture, width: width, height: height, limit: theme.columnWidth)
            return picture
        }
        guard ["http", "https"].contains(url.scheme) else { return nil }
        remoteImages.append(RemoteImage(url: url, width: width, height: height, place: place))
        return NSImage(size: NSSize(width: 1, height: 1))
    }

    private func altText(_ alt: String) -> NSAttributedString {
        NSAttributedString(string: alt, attributes: [.font: theme.font(size: theme.bodySize), .foregroundColor: theme.muted])
    }

    /// A text block has no width of its own, and without one its text wraps after every character.
    private static func fullWidthBlock() -> NSTextBlock {
        let block = NSTextBlock()
        block.setContentWidth(100, type: .percentageValueType)
        return block
    }

    /// One point per pixel, as a browser shows it, unless the document asked for a size,
    /// and never wider than the text column.
    static func fit(_ picture: NSImage, width: CGFloat? = nil, height: CGFloat? = nil, limit: CGFloat) {
        if let pixels = picture.representations.first, pixels.pixelsWide > 0 {
            picture.size = NSSize(width: pixels.pixelsWide, height: pixels.pixelsHigh)
        }
        var size = picture.size
        guard size.width > 0, size.height > 0 else { return }
        if let width {
            size = NSSize(width: width, height: height ?? size.height * width / size.width)
        } else if let height {
            size = NSSize(width: size.width * height / size.height, height: height)
        }
        if size.width > limit { size = NSSize(width: limit, height: size.height * limit / size.width) }
        picture.size = size
    }
}

private struct HTMLTag {
    let name: String
    let closing: Bool
    let attributes: [String: String]
}

/// The little HTML the renderer reads: tags with attributes, text with entities, comments.
private enum HTMLScanner {
    enum Token {
        case text(String)
        case tag(HTMLTag)
        case comment
    }

    static func tokens(_ html: String) -> [Token] {
        let chars = Array(html)
        var result: [Token] = []
        var text = "", i = 0
        func flush() { if !text.isEmpty { result.append(.text(decode(text))); text = "" } }
        while i < chars.count {
            if chars[i] == "<", i + 1 < chars.count {
                let next = chars[i + 1]
                if next == "!", i + 3 < chars.count, chars[i + 2] == "-", chars[i + 3] == "-" {
                    var j = i + 4
                    while j + 2 < chars.count, !(chars[j] == "-" && chars[j + 1] == "-" && chars[j + 2] == ">") { j += 1 }
                    flush()
                    result.append(.comment)
                    i = min(j + 3, chars.count)
                    continue
                }
                if next.isLetter || next == "/" || next == "!" || next == "?" {
                    var j = i + 1, quote: Character?
                    while j < chars.count {
                        let c = chars[j]
                        if let q = quote { if c == q { quote = nil } }
                        else if c == "\"" || c == "'" { quote = c }
                        else if c == ">" { break }
                        j += 1
                    }
                    if j < chars.count {
                        flush()
                        if next != "!", next != "?" { result.append(.tag(tag(chars[(i + 1)..<j]))) }   // doctype and the like are dropped
                        i = j + 1
                        continue
                    }
                }
            }
            text.append(chars[i])
            i += 1
        }
        flush()
        return result
    }

    private static func tag(_ body: ArraySlice<Character>) -> HTMLTag {
        var i = body.startIndex
        let end = body.endIndex
        var closing = false
        if i < end, body[i] == "/" { closing = true; i += 1 }
        func skipSpace() { while i < end, body[i].isWhitespace { i += 1 } }
        func word(until stop: (Character) -> Bool) -> String {
            var s = ""
            while i < end, !stop(body[i]) { s.append(body[i]); i += 1 }
            return s
        }
        skipSpace()
        let name = word { $0.isWhitespace || $0 == "/" || $0 == ">" }.lowercased()
        var attributes: [String: String] = [:]
        while i < end {
            skipSpace()
            let key = word { $0.isWhitespace || $0 == "=" || $0 == "/" }.lowercased()
            skipSpace()
            var value = ""
            if i < end, body[i] == "=" {
                i += 1
                skipSpace()
                if i < end, body[i] == "\"" || body[i] == "'" {
                    let q = body[i]
                    i += 1
                    value = word { $0 == q }
                    if i < end { i += 1 }
                } else {
                    value = word { $0.isWhitespace }
                }
            }
            if !key.isEmpty { attributes[key] = decode(value) } else if i < end { i += 1 }
        }
        return HTMLTag(name: name, closing: closing, attributes: attributes)
    }

    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            result += rest[..<amp]
            rest = rest[amp...]
            if let semi = rest.firstIndex(of: ";"), rest.distance(from: rest.startIndex, to: semi) <= 10,
               let replacement = entity(String(rest[rest.index(after: rest.startIndex)..<semi])) {
                result += replacement
                rest = rest[rest.index(after: semi)...]
            } else {
                result += "&"
                rest = rest.dropFirst()
            }
        }
        return result + String(rest)
    }

    private static func entity(_ name: String) -> String? {
        switch name {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        case "nbsp": return "\u{a0}"
        case "copy": return "©"
        case "reg": return "®"
        case "trade": return "™"
        case "hellip": return "…"
        case "mdash": return "—"
        case "ndash": return "–"
        case "bull": return "•"
        case "middot": return "·"
        case "laquo": return "«"
        case "raquo": return "»"
        case "larr": return "←"
        case "rarr": return "→"
        case "times": return "×"
        default:
            let hex = name.hasPrefix("#x") || name.hasPrefix("#X")
            guard name.hasPrefix("#"), let value = UInt32(name.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10),
                  let scalar = Unicode.Scalar(value) else { return nil }
            return String(Character(scalar))
        }
    }
}
