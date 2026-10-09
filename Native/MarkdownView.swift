import AppKit
import Quartz

/// The text of a document: a centred column of at most `columnWidth` that
/// also accepts files dropped on it.
final class ColumnTextView: NSTextView {
    var onDrop: ([URL]) -> Void = { _ in }
    /// The widest the column grows; a wider view leaves margins either side.
    var columnWidth = Settings.defaultTheme.columnWidth {
        didSet { if columnWidth != oldValue { setFrameSize(frame.size) } }
    }
    /// Whether the text has drawings (see NativeRenderer.drawing). Finding them in a large document takes a while.
    private(set) var hasDrawings = false
    /// The text container width the drawings were last fitted to.
    private var drawingsWidth = Settings.defaultTheme.columnWidth
    private(set) var tables: [NativeRenderer.FittedTable] = []
    /// The width the tables were last fitted to.
    private var tablesWidth = Settings.defaultTheme.columnWidth

    /// Called with new text, whose drawings and tables the renderer fitted to a full column.
    func textChanged(hasDrawings: Bool, tables: [NativeRenderer.FittedTable]) {
        copyButton.isHidden = true
        hover(nil)
        self.hasDrawings = hasDrawings
        self.tables = tables
        drawingsWidth = columnWidth
        tablesWidth = columnWidth
        fitDrawings()
        fitTables()
    }

    /// Tables keep their natural width in a column narrower than the full one.
    private func fitTables() {
        guard !tables.isEmpty, let width = textContainer?.size.width, min(width, columnWidth) != tablesWidth else { return }
        tablesWidth = min(width, columnWidth)
        NativeRenderer.fitTables(tables, width: tablesWidth)
        // A table's width is not an attribute of the text, so changing it tells the text system nothing.
        layoutManager?.invalidateLayout(forCharacterRange: NSRange(location: 0, length: textStorage?.length ?? 0), actualCharacterRange: nil)
    }

    /// A window narrower than the column narrows the column, and the drawings with it.
    private func fitDrawings() {
        guard hasDrawings, let storage = textStorage, let width = textContainer?.size.width, width != drawingsWidth else { return }
        drawingsWidth = width
        NativeRenderer.fitDrawings(in: storage, width: width)
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        fitDrawings()
    }

    /// While set, a change of size lays nothing out again (see MarkdownView.keepingWidth).
    var holdsLayout = false

    override func setFrameSize(_ newSize: NSSize) {
        guard !holdsLayout else { return super.setFrameSize(newSize) }
        let clip = enclosingScrollView?.contentView
        let atTop = (clip?.bounds.origin.y ?? 1) <= 0
        let inset = NSSize(width: max(40, floor((newSize.width - columnWidth) / 2)), height: 24)
        if inset != textContainerInset { textContainerInset = inset }
        super.setFrameSize(newSize)
        // A large document's drawings wait for the end of a resize: finding them takes too long to do at every step.
        if !inLiveResize || (textStorage?.length ?? 0) < 1_000_000 { fitDrawings() }
        fitTables()
        // When its width changes the text view keeps its first line in place, which at
        // the top of a document scrolls the margin above that line out of sight.
        if atTop, let clip, clip.bounds.origin.y != 0 {
            clip.scroll(to: .zero)
            enclosingScrollView?.reflectScrolledClipView(clip)
        }
    }

    // Scrolling exposes the view a strip at a time, and the text system draws a strip
    // starting from the first line it finds in it. The cells of a table sit side by
    // side, so a strip that begins inside a row misses the cells that began above it:
    // the rest of the row stayed blank and the table looked torn. Drawing every strip
    // from the top of the visible area instead keeps tables whole.
    override func draw(_ dirtyRect: NSRect) {
        var rect = dirtyRect
        let top = visibleRect.minY
        if top < rect.minY {
            rect.size.height += rect.minY - top
            rect.origin.y = top
        }
        super.draw(rect)
    }

    private func files(in sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        files(in: sender).isEmpty ? [] : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        files(in: sender).isEmpty ? [] : .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let dropped = files(in: sender)
        onDrop(dropped)
        return !dropped.isEmpty
    }

    // MARK: Pointer

    /// Called with the link under the pointer, or nil once it is off links.
    var onHoverLink: (URL?) -> Void = { _ in }
    /// Whether the picture at a character opens full size when clicked, and what opens it, with
    /// where the picture is in the view.
    var isPreviewable: (Int) -> Bool = { _ in false }
    var onPictureClick: (Int, NSRect) -> Void = { _, _ in }
    private var pointerOverPicture = false
    /// A text view takes the Quick Look panel for its own links; while a picture is shown full
    /// size, it leaves the panel to whoever shows the picture.
    var passesPreviewPanel = false

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        passesPreviewPanel ? false : super.acceptsPreviewPanelControl(panel)
    }

    /// The picture under a point, if the point is on the picture itself, and its frame.
    private func picture(at point: NSPoint) -> (index: Int, frame: NSRect)? {
        guard let layout = layoutManager, let container = textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let inContainer = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layout.glyphIndex(for: inContainer, in: container)
        let index = layout.characterIndexForGlyph(at: glyph)
        guard index < storage.length, storage.attribute(.attachment, at: index, effectiveRange: nil) != nil else { return nil }
        var frame = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        guard frame.contains(inContainer) else { return nil }
        frame.origin.x += textContainerOrigin.x
        frame.origin.y += textContainerOrigin.y
        return (index, frame)
    }

    /// Called with the character double-clicked, if set.
    var onDoubleClick: ((Int) -> Void)?

    // A plain click on a picture that can be shown full size shows it; anything else selects as usual.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 1, event.modifierFlags.intersection([.shift, .command, .option, .control]).isEmpty,
           let (index, frame) = picture(at: point), isPreviewable(index) {
            return onPictureClick(index, frame)
        }
        super.mouseDown(with: event)
        if event.clickCount == 2, let onDoubleClick, let layout = layoutManager, let container = textContainer, (textStorage?.length ?? 0) > 0 {
            let glyph = layout.glyphIndex(for: NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y), in: container)
            onDoubleClick(layout.characterIndexForGlyph(at: glyph))
        }
    }
    /// The button that copies the code block under the pointer.
    let copyButton = CopyButton()
    private var hoveredLink: URL?
    private var pointerArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard pointerArea == nil else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        pointerArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        pointerMoved(to: point)
        // The text view sets its own cursor as the pointer moves, over its subviews too.
        if pointerOverPicture || (!copyButton.isHidden && copyButton.frame.contains(point)) { NSCursor.pointingHand.set() }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        guard event.trackingArea == pointerArea else { return }
        hover(nil)
        copyButton.isHidden = true
    }

    private func hover(_ link: URL?) {
        guard link != hoveredLink else { return }
        hoveredLink = link
        onHoverLink(link)
    }

    private func pointerMoved(to point: NSPoint) {
        guard let layout = layoutManager, let container = textContainer, let storage = textStorage, storage.length > 0 else { return }
        let inContainer = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layout.glyphIndex(for: inContainer, in: container)
        let index = layout.characterIndexForGlyph(at: glyph)
        guard index < storage.length else { return }
        // A link only counts under the pointer itself, not as the nearest text to it.
        let overGlyph = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(inContainer)
        let link = overGlyph ? storage.attribute(.link, at: index, effectiveRange: nil) : nil
        hover(link as? URL ?? (link as? String).flatMap(URL.init(string:)))
        pointerOverPicture = overGlyph && link == nil && isPreviewable(index)

        // A code block's button shows while the pointer is anywhere in its box.
        var range = NSRange()
        guard let code = storage.attribute(NativeRenderer.code, at: index, effectiveRange: &range) as? String,
              let box = (storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)?.textBlocks.last
        else { return copyButton.isHidden = true }
        let block = storage.range(of: box, at: range.location)
        var bounds = layout.boundsRect(for: box, glyphRange: layout.glyphRange(forCharacterRange: block, actualCharacterRange: nil))
        bounds.origin.x += textContainerOrigin.x
        bounds.origin.y += textContainerOrigin.y
        guard bounds.contains(point) else { return copyButton.isHidden = true }
        if copyButton.superview == nil { addSubview(copyButton) }
        copyButton.code = code
        copyButton.setFrameOrigin(NSPoint(x: bounds.maxX - copyButton.frame.width - 8, y: bounds.minY + 8))
        copyButton.isHidden = false
        window?.invalidateCursorRects(for: copyButton)
    }

    /// Attribute key holding a drawn formula's or diagram's Markdown, for copying.
    static let written = NSAttributedString.Key("MarkviewWritten")

    // A drawn formula or diagram copies as the Markdown it was written as.
    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard let storage = textStorage else { return false }
        let ranges = selectedRanges.map(\.rangeValue)
        var figures = false
        for range in ranges {
            storage.enumerateAttribute(Self.written, in: range) { value, _, stop in
                if value != nil { figures = true; stop.pointee = true }
            }
        }
        guard figures else { return super.writeSelection(to: pboard, types: types) }
        var text = ""
        for range in ranges {
            storage.enumerateAttribute(Self.written, in: range) { value, part, _ in
                text += value as? String ?? (storage.string as NSString).substring(with: part)
            }
        }
        pboard.clearContents()
        return pboard.setString(text, forType: .string)
    }
}

/// The button in the corner of a code block, which copies its code.
final class CopyButton: NSView {
    var code = ""
    var colors = (fill: NSColor.textBackgroundColor, border: NSColor.separatorColor, ink: NSColor.secondaryLabelColor, done: NSColor.systemGreen)
    private var copied = false

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 28, height: 26))
        toolTip = "Copy"
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        colors.fill.setFill()
        shape.fill()
        colors.border.setStroke()
        shape.stroke()
        let name = copied ? "checkmark" : "doc.on.doc"
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular)) else { return }
        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            (self.copied ? self.colors.done : self.colors.ink).set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: NSRect(x: (bounds.width - symbol.size.width) / 2, y: (bounds.height - symbol.size.height) / 2,
                               width: symbol.size.width, height: symbol.size.height))
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func mouseDown(with event: NSEvent) { copyCode() }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copied = true
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copied = false
            self?.needsDisplay = true
        }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { "Copy code" }
    override func accessibilityPerformPress() -> Bool { copyCode(); return true }
}

/// Where the link under the pointer leads, in the bottom corner of the page, as a browser shows it.
final class LinkStatus: NSView {
    let label = NSTextField(labelWithString: "")
    var colors = (fill: NSColor.textBackgroundColor, border: NSColor.separatorColor) { didSet { needsDisplay = true } }

    init() {
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: 11)
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        colors.fill.setFill()
        shape.fill()
        colors.border.setStroke()
        shape.stroke()
    }

    // The pointer passes through it to the page.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// An attachment that shrinks to the line it is on, so a figure or picture sized for the full
/// column still fits a narrower window, such as a Quick Look preview. Figures are vector images,
/// so they stay sharp.
final class FittingAttachment: NSTextAttachment {
    /// Whether it keeps clear of the text container's padding, as a figure does. A picture
    /// has always reached into it, and only shrinks once it is wider than the line itself.
    var clearsPadding = true
    /// Where a picture came from, a file or the web, and the diagram a drawing is of, so that a
    /// click can show either full size (see MarkdownView.previewFile).
    var source: URL?
    var diagram: Diagram?

    override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: NSRect,
                                   glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        var bounds = super.attachmentBounds(for: textContainer, proposedLineFragment: lineFrag, glyphPosition: position, characterIndex: charIndex)
        let room = lineFrag.width - (clearsPadding ? 2 * (textContainer?.lineFragmentPadding ?? 0) : 0)
        if room > 0, bounds.width > room { bounds.size = NSSize(width: room, height: bounds.height * room / bounds.width) }
        return bounds
    }
}

/// A picture that depends on the appearance: from a <picture> whose sources name one image for
/// light windows and one for dark, or an image a README shows in one appearance alone
/// (#gh-light-mode-only, #gh-dark-mode-only), which has nothing for the other. Its size comes
/// from the appearance of the text view it is laid out in, so that one shown alone takes no
/// room in the other; MarkdownView lays the text out again when the appearance changes.
/// A page for printing takes plain copies (see NativeRenderer.copy): the text system keeps the
/// sizes it measured in the window rather than asking again for another layout.
final class AppearanceAttachment: NSTextAttachment {
    var light: NSImage? { didSet { redraw() } }
    var dark: NSImage? { didSet { redraw() } }
    /// Where each picture came from.
    var lightSource: URL?, darkSource: URL?

    private func picture(for appearance: NSAppearance?) -> NSImage? {
        appearance?.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
    }

    /// The image the text system draws picks its picture as it is drawn, as diagrams do.
    private func redraw() {
        let sizes = [light, dark].compactMap { $0?.size }
        let size = NSSize(width: sizes.map(\.width).max() ?? 1, height: sizes.map(\.height).max() ?? 1)
        let drawing = NSImage(size: size, flipped: false) { [weak self] rect in
            self?.picture(for: NSAppearance.currentDrawing())?.draw(in: rect)
            return true
        }
        drawing.cacheMode = .never
        image = drawing
    }

    // As wide as its picture for this appearance, and no wider than the line, as other pictures are.
    override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: NSRect,
                                   glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        guard var size = picture(for: textContainer?.textView?.effectiveAppearance)?.size else { return .zero }
        if lineFrag.width > 0, size.width > lineFrag.width { size = NSSize(width: lineFrag.width, height: size.height * lineFrag.width / size.width) }
        return NSRect(origin: .zero, size: size)
    }
}

/// Draws the boxes behind inline code, keys and highlights. The text system's own
/// background attribute fills the whole line fragment, which with the page's line
/// height is a band far taller than the glyphs; these hug the glyphs and have corners.
final class BoxedLayoutManager: NSLayoutManager {
    /// Attribute key whose value is the box's fill colour.
    static let box = NSAttributedString.Key("MarkviewBox")

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(Self.box, in: characters) { value, range, _ in
            guard let color = value as? NSColor else { return }
            let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? NSFont.systemFont(ofSize: 16)
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, fragmentGlyphs, _ in
                let part = NSIntersectionRange(glyphs, fragmentGlyphs)
                guard part.length > 0 else { return }
                let bounds = self.boundingRect(forGlyphRange: part, in: container)
                let baseline = fragment.minY + self.location(forGlyphAt: part.location).y
                let box = NSRect(x: bounds.minX - 3 + origin.x, y: baseline - font.ascender - 1 + origin.y,
                                 width: bounds.width + 6, height: font.ascender - font.descender + 2)
                color.setFill()
                NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3).fill()
            }
        }
    }
}

/// A scrolling, read-only view of a Markdown document rendered natively. The
/// app's windows and the Quick Look preview both show documents with it.
final class MarkdownView: NSScrollView, NSTextViewDelegate {
    let textView: ColumnTextView
    /// Called with a clicked link that leads out of the document, or a file dropped on it.
    var open: (URL) -> Void = { _ in }
    /// Called with a file dropped on the page, in place of `open`, if set.
    var openDropped: ((URL) -> Void)?
    /// Called before a link jumps to a heading in the document itself.
    var willFollowLink: () -> Void = {}
    /// Called with a file to show full size, and where on screen its picture is, when a picture
    /// or diagram is clicked. Nil where there is nothing to show it in, as in Quick Look.
    var onPreview: ((URL, NSRect) -> Void)? {
        didSet {
            textView.isPreviewable = { [weak self] index in self?.onPreview != nil && self?.previewSource(at: index) != nil }
            textView.onPictureClick = { [weak self] index, frame in
                guard let self, let onPreview, let file = previewFile(at: index) else { return }
                onPreview(file, textView.window?.convertToScreen(textView.convert(frame, to: nil)) ?? .zero)
            }
        }
    }
    /// The colours, fonts and sizes documents are shown in. The background and the column
    /// change at once; the text keeps its look until the document is shown again.
    var theme = Settings.theme {
        didSet { applyTheme() }
    }
    /// Called whenever new text is shown, with its headings, and whenever the view scrolls.
    var onShow: () -> Void = {}
    var onScroll: () -> Void = {}
    /// Whether to note which line of the Markdown each block of the page came from, for an editor
    /// beside it. Takes effect from the next render.
    var tracksSource = false
    /// Whether the view is moving because its text is being replaced or changed in size, rather than
    /// because it was scrolled.
    private(set) var isAdjusting = false

    private let linkStatus = LinkStatus()
    private var anchors: [String: Int] = [:]
    /// The headings of the rendered document, in order.
    private(set) var headings: [Heading] = []
    private var baseURL: URL?
    private var generation = 0
    /// Whether a large document is still being rendered in full.
    private(set) var rendering = false
    /// Large documents render here, one at a time.
    private let renderQueue = DispatchQueue(label: "com.dagurleo.markview.render", qos: .userInitiated)
    private var pendingAnchor: String?
    private var pendingPlace: Int?
    /// Whether any picture depends on the appearance, so the text is laid out again when it changes.
    private var appearanceImages = false
    /// The pictures fetched from the web for the document on show, so that showing it again, as
    /// when the file or a setting changes, puts them straight back rather than fetching them anew.
    private var fetched: [URL: NSImage] = [:]
    /// The drawings of the diagrams on show, so the same document shown again, as it is when
    /// the file changes, keeps them instead of flashing back to code while they are redrawn.
    private var drawn: [String: NSImage] = [:]
    /// Where the blocks of the page came from in the Markdown, when tracked (see `tracksSource`).
    private var sourceLines: [NativeRenderer.SourceLine] = []
    private var sourceLineCount = 0

    override init(frame: NSRect) {
        // TextKit 1, because text tables and text blocks need it.
        let storage = NSTextStorage()
        let layout = BoxedLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: frame.width, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        textView = ColumnTextView(frame: NSRect(origin: .zero, size: frame.size), textContainer: container)
        super.init(frame: frame)

        textView.isEditable = false
        textView.isSelectable = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.registerForDraggedTypes([.fileURL])
        textView.onDrop = { [weak self] files in
            guard let self else { return }
            files.forEach(openDropped ?? open)
        }
        textView.delegate = self

        documentView = textView
        hasVerticalScroller = true
        // Otherwise the scroll view adds a top inset for the window's transparent title
        // bar, and its idea of the top (-32) and this view's (0) pull against each other
        // while a document lays out, leaving the page scrolled down by its own margin.
        automaticallyAdjustsContentInsets = false
        allowsMagnification = true
        minMagnification = 0.5
        maxMagnification = 3
        applyTheme()
        textView.onHoverLink = { [weak self] link in self?.showStatus(of: link) }
        addSubview(linkStatus)
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: contentView, queue: .main) { [weak self] _ in
            self?.onScroll()
        }
    }

    private func applyTheme() {
        backgroundColor = theme.background
        textView.backgroundColor = theme.background
        textView.linkTextAttributes = [.foregroundColor: theme.link, .cursor: NSCursor.pointingHand]
        textView.columnWidth = theme.columnWidth
        textView.copyButton.colors = (theme.background, theme.border, theme.muted, theme.alerts["TIP"]!.color)
        linkStatus.colors = (theme.background, theme.border)
        linkStatus.label.textColor = theme.muted
    }

    // MARK: Links and headings

    private func showStatus(of link: URL?) {
        linkStatus.label.stringValue = link.map(describe) ?? ""
        linkStatus.isHidden = link == nil
        placeStatus()
    }

    // A scroll view lays out its own subviews, so the link's label is placed by hand: in the
    // bottom corner, as wide as its text up to most of the view.
    override func tile() {
        super.tile()
        placeStatus()
    }

    private func placeStatus() {
        guard !linkStatus.isHidden else { return }
        let size = linkStatus.fittingSize
        let width = min(size.width, bounds.width * 0.7)
        linkStatus.frame = NSRect(x: 6, y: isFlipped ? bounds.height - size.height - 6 : 6, width: width, height: size.height)
    }

    /// What a link does, in a few words: the heading it goes to, the file it opens or shows, or the address.
    private func describe(_ link: URL) -> String {
        guard link.isFileURL else {
            return link.scheme == "mailto" ? "Email " + (link.absoluteString.dropFirst("mailto:".count).removingPercentEncoding ?? "") : link.absoluteString
        }
        let file = URL(fileURLWithPath: link.path), fragment = link.fragment.map { "#" + $0 } ?? ""
        if file.path == baseURL?.path { return fragment.isEmpty ? file.lastPathComponent : fragment }
        // Relative to the document's folder when it is in it, as the document itself would write it.
        let folder = baseURL?.deletingLastPathComponent().path ?? ""
        let shown = file.path.hasPrefix(folder + "/") ? String(file.path.dropFirst(folder.count + 1)) : (file.path as NSString).abbreviatingWithTildeInPath
        if Links.markdownExtensions.contains(file.pathExtension.lowercased()) { return shown + fragment }
        return FileManager.default.fileExists(atPath: file.path) ? "Show “\(shown)” in Finder" : shown + " (not found)"
    }

    /// The heading a character is in, if any.
    private func heading(at index: Int) -> Heading? {
        guard let storage = textView.textStorage, index < storage.length else { return nil }
        let start = (storage.string as NSString).paragraphRange(for: NSRange(location: index, length: 0)).location
        return headings.first { anchors[$0.anchor] == start }
    }

    // MARK: Pictures full size

    private enum PreviewSource {
        case file(URL), web(URL), diagram(Diagram)
    }

    /// What the picture or diagram at a character can be shown full size from. A picture that is
    /// a link is the link's to follow; a formula has nothing to show.
    private func previewSource(at index: Int) -> PreviewSource? {
        guard let storage = textView.textStorage, index < storage.length,
              storage.attribute(.link, at: index, effectiveRange: nil) == nil else { return nil }
        var source: URL?
        switch storage.attribute(.attachment, at: index, effectiveRange: nil) {
        case let fitting as FittingAttachment:
            if let diagram = fitting.diagram { return .diagram(diagram) }
            source = fitting.source
        case let modal as AppearanceAttachment:
            source = isDark ? modal.darkSource : modal.lightSource
        default:
            return nil
        }
        guard let source else { return nil }
        if source.isFileURL { return .file(URL(fileURLWithPath: source.path)) }
        return fetched[source] == nil ? nil : .web(source)
    }

    private var isDark: Bool { effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }

    /// A file for Quick Look: the picture's own, or one written for it, as the picture was fetched
    /// or the diagram drawn, in the window's colours.
    private func previewFile(at index: Int) -> URL? {
        switch previewSource(at: index) {
        case .file(let file): return file
        case .web(let address):
            guard let tiff = fetched[address]?.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
            let name = address.deletingPathExtension().lastPathComponent
            return writePreview(png, named: (name.isEmpty || name == "/" ? "Image" : name) + ".png")
        case .diagram(let diagram):
            return Diagrams.pdf(diagram, dark: isDark).flatMap { writePreview($0, named: "Diagram.pdf") }
        case nil: return nil
        }
    }

    private func writePreview(_ data: Data, named name: String) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Markview Previews", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(name)
        return (try? data.write(to: file)) == nil ? nil : file
    }

    // A heading's context menu can copy a link to it, as the document's own links write one.
    func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        guard let heading = heading(at: charIndex), let name = baseURL?.lastPathComponent else { return menu }
        let item = NSMenuItem(title: "Copy Link to Heading", action: #selector(copyHeadingLink(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = (name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name) + "#" + heading.anchor
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }

    @objc private func copyHeadingLink(_ sender: NSMenuItem) {
        guard let link = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Showing a document

    /// A small document is rendered at once. A large one shows its beginning straight
    /// away and is rendered in full on a background thread, then swapped in.
    func show(_ markdown: String, baseURL: URL) {
        // The same document shown again keeps its place; another starts at its top.
        let continuing = baseURL == self.baseURL
        self.baseURL = baseURL
        generation += 1
        let generation = generation
        let theme = theme
        let large = markdown.utf8.count > 256 * 1024

        if !large || textView.string.isEmpty || !continuing {
            var beginning = markdown
            if large {
                // Cut at a paragraph break so the beginning is rarely caught mid-block.
                let from = markdown.index(markdown.startIndex, offsetBy: 96 * 1024, limitedBy: markdown.endIndex) ?? markdown.endIndex
                if let cut = markdown.range(of: "\n\n", range: from..<markdown.endIndex) { beginning = String(markdown[..<cut.lowerBound]) }
            }
            let renderer = NativeRenderer(baseURL: baseURL, theme: theme, tracksSource: tracksSource)
            replaceText(with: renderer.render(beginning), from: renderer, keepingPlace: !large && continuing)
        }
        rendering = large
        guard large else { return }
        let tracksSource = tracksSource
        renderQueue.async {
            // Each takes seconds and hundreds of megabytes, so one already overtaken, as by a
            // file saved again or a setting changed again, is skipped.
            guard DispatchQueue.main.sync(execute: { generation == self.generation }) else { return }
            let renderer = NativeRenderer(baseURL: baseURL, theme: theme, tracksSource: tracksSource)
            let rendered = renderer.render(markdown)
            DispatchQueue.main.async {
                guard generation == self.generation else { return }
                self.rendering = false
                self.replaceText(with: rendered, from: renderer, keepingPlace: true)
                if let anchor = self.pendingAnchor {
                    self.pendingAnchor = nil
                    self.jump(to: anchor)
                } else if let place = self.pendingPlace {
                    self.go(to: place)
                }
                self.pendingPlace = nil
            }
        }
    }

    /// Shows the document again as it is being edited. It renders in the background whatever its
    /// size, so typing never waits for it, and is swapped in keeping the place; one overtaken by a
    /// later edit is skipped.
    func update(_ markdown: String, baseURL: URL) {
        self.baseURL = baseURL
        generation += 1
        let generation = generation
        let theme = theme
        // This also takes the place of a large document still being rendered in full.
        rendering = false
        pendingAnchor = nil
        pendingPlace = nil
        let tracksSource = tracksSource
        renderQueue.async {
            guard DispatchQueue.main.sync(execute: { generation == self.generation }) else { return }
            let renderer = NativeRenderer(baseURL: baseURL, theme: theme, tracksSource: tracksSource)
            let rendered = renderer.render(markdown)
            DispatchQueue.main.async {
                guard generation == self.generation else { return }
                self.replaceText(with: rendered, from: renderer, keepingPlace: true)
            }
        }
    }

    /// The character at the top of the view, or `offset` points below it, or 0 at the top of the document.
    func topCharacter(offset: CGFloat = 0) -> Int {
        guard let layout = textView.layoutManager, let container = textView.textContainer else { return 0 }
        // Asking which glyph sits at a point would lay out everything above it, which takes
        // minutes far down a large document. This only reads what is already laid out.
        var visible = contentView.bounds
        visible.origin.y += offset - textView.textContainerOrigin.y
        let glyphs = layout.glyphRange(forBoundingRectWithoutAdditionalLayout: visible, in: container)
        return visible.origin.y > 0 && glyphs.length > 0 ? layout.characterIndexForGlyph(at: glyphs.location) : 0
    }

    /// Swaps in new text and returns to the character that was at the top.
    private func replaceText(with rendered: NSAttributedString, from renderer: NativeRenderer?, keepingPlace: Bool) {
        guard let layout = textView.layoutManager, let container = textView.textContainer else { return }
        isAdjusting = true
        defer { isAdjusting = false }
        let top = topCharacter()
        // Pictures already fetched go in before the text is laid out, so it takes their size at once.
        let previous = fetched
        fetched = [:]
        var remote: [NativeRenderer.RemoteImage] = []
        for request in renderer?.remoteImages ?? [] {
            guard let picture = previous[request.url] ?? fetched[request.url] else { remote.append(request); continue }
            fetched[request.url] = picture
            place(picture, for: request)
        }
        appearanceImages = renderer?.hasAppearanceImages ?? false
        // A fresh storage rather than an edit of the old one: replacing the text of a large,
        // partly laid out document in place took 14 seconds for 5 MB.
        contentView.scroll(to: .zero)
        // Laying out only what is looked at keeps a very large document usable, but it
        // misplaces boxed blocks after a resize, so ordinary documents do without it.
        layout.allowsNonContiguousLayout = rendered.length > 1_000_000
        layout.replaceTextStorage(NSTextStorage(attributedString: rendered))
        textView.textChanged(hasDrawings: renderer?.hasDrawings ?? false, tables: renderer?.fittedTables ?? [])
        anchors = renderer?.anchors ?? [:]
        headings = renderer?.headings ?? []
        sourceLines = renderer?.sourceLines ?? []
        sourceLineCount = renderer?.sourceLineCount ?? 0
        if keepingPlace, top > 0 {
            scroll(toCharacter: min(top, rendered.length - 1), margin: 0)
        } else {
            // Lay out the first screen now and go back to the top. When layout is left for
            // later, the view keeps its first plain paragraph in place as the boxed blocks
            // above it take shape, which in Quick Look left the preview opening below its title.
            layout.ensureLayout(forBoundingRect: NSRect(origin: .zero, size: contentView.bounds.size), in: container)
            contentView.scroll(to: .zero)
        }
        reflectScrolledClipView(contentView)
        fetch(remote)
        draw(renderer?.diagrams ?? [])
        onShow()
    }

    // MARK: Diagrams

    /// Diagrams are drawn once the text shows. Until then, and for good if one cannot be
    /// drawn, each shows as written.
    private func draw(_ diagrams: [Diagram]) {
        let previous = drawn
        drawn = [:]
        guard !diagrams.isEmpty, let storage = textView.textStorage else { return }
        let kept = diagrams.map { previous[$0.key] }
        for (diagram, drawing) in zip(diagrams, kept) where drawing != nil { drawn[diagram.key] = drawing }
        if drawn.count > 0 { place(kept, of: diagrams, in: storage) }
        let missing = diagrams.indices.filter { kept[$0] == nil }
        guard !missing.isEmpty else { return }
        Diagrams.draw(missing.map { diagrams[$0] }) { [weak self] drawings in
            // A document shown again since has diagrams of its own.
            guard let self, self.textView.textStorage === storage else { return false }
            var all = [NSImage?](repeating: nil, count: diagrams.count)
            for (index, drawing) in zip(missing, drawings) where drawing != nil {
                all[index] = drawing
                self.drawn[diagrams[index].key] = drawing
            }
            self.place(all, of: diagrams, in: storage)
            return true
        }
    }

    private func place(_ drawings: [NSImage?], of diagrams: [Diagram], in storage: NSTextStorage) {
        var placeholders: [(range: NSRange, index: Int)] = []
        storage.enumerateAttribute(Diagrams.placeholder, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let index = value as? Int, index < drawings.count, drawings[index] != nil { placeholders.append((range, index)) }
        }
        guard !placeholders.isEmpty else { return }
        var top = topCharacter()
        isAdjusting = true
        defer { isAdjusting = false }
        storage.beginEditing()
        // From the end, so the ranges still to come stay where they were found.
        for (range, index) in placeholders.reversed() {
            let image = drawings[index]!, diagram = diagrams[index]
            let attachment = FittingAttachment()
            attachment.image = image
            attachment.diagram = diagram
            attachment.bounds = NSRect(origin: .zero, size: image.size)
            let text = "\u{FFFC}\n"
            let attributes: [NSAttributedString.Key: Any] = [.paragraphStyle: diagram.block, .font: diagram.theme.font(size: diagram.theme.bodySize),
                                                             .attachment: attachment, ColumnTextView.written: diagram.written]
            storage.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: attributes))
            // Heading links and the place in the document move with the text after the diagram.
            let shift = (text as NSString).length - range.length
            for (anchor, location) in anchors where location > range.location { anchors[anchor] = location + shift }
            for index in sourceLines.indices where sourceLines[index].location > range.location { sourceLines[index].location += shift }
            if top > range.location { top = max(range.location, top + shift) }
        }
        storage.endEditing()
        if top > 0 { scroll(toCharacter: top, margin: 0) }
    }

    private func fetch(_ images: [NativeRenderer.RemoteImage]) {
        for request in images {
            URLSession.shared.dataTask(with: request.url) { [weak self] data, _, _ in
                guard let data, let picture = NSImage(data: data) else { return }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.fetched[request.url] = picture
                    self.place(picture, for: request)
                    guard let storage = self.textView.textStorage else { return }
                    self.textView.layoutManager?.invalidateLayout(
                        forCharacterRange: NSRange(location: 0, length: storage.length), actualCharacterRange: nil)
                }
            }.resume()
        }
    }

    /// A copy, sized as the document asked: one picture can appear at several sizes.
    private func place(_ picture: NSImage, for request: NativeRenderer.RemoteImage) {
        guard let copy = picture.copy() as? NSImage else { return }
        NativeRenderer.fit(copy, width: request.width, height: request.height, limit: theme.columnWidth)
        request.place(copy)
    }

    // A picture for one appearance takes its size in that appearance. Laying the text out again is
    // not enough: one that took no room before stays undrawn, so the text counts as changed.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        guard appearanceImages, let storage = textView.textStorage else { return }
        storage.beginEditing()
        storage.edited(.editedAttributes, range: NSRange(location: 0, length: storage.length), changeInLength: 0)
        storage.endEditing()
    }

    /// Runs `body`, which resizes the page, laying out the text again only for the width it ends
    /// at, not for those it passes through. A long page read far down takes seconds to lay out.
    func keepingWidth(_ body: () -> Void) {
        guard let container = textView.textContainer, container.widthTracksTextView else { return body() }
        container.widthTracksTextView = false
        textView.holdsLayout = true
        body()
        textView.holdsLayout = false
        container.widthTracksTextView = true
        // The margins, drawings and tables for the width it ended at, and the column.
        textView.setFrameSize(textView.frame.size)
        let width = textView.frame.width - 2 * textView.textContainerInset.width
        if container.size.width != width { container.size = NSSize(width: width, height: container.size.height) }
    }

    // MARK: Moving around

    /// Where the reader is, for going back to later: the first character of the topmost line
    /// that is mostly in view.
    var place: Int {
        let top = topCharacter()
        guard top > 0, let layout = textView.layoutManager else { return top }
        var line = NSRange()
        let rect = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: top), effectiveRange: &line, withoutAdditionalLayout: true)
        let visibleTop = contentView.bounds.minY - textView.textContainerOrigin.y
        guard visibleTop > rect.midY, NSMaxRange(line) < layout.numberOfGlyphs else { return top }
        return layout.characterIndexForGlyph(at: NSMaxRange(line))
    }

    /// Where a heading starts in the text.
    func location(of anchor: String) -> Int? { anchors[anchor] }

    /// Scrolls to a character, as one `topCharacter` gave, once the document is all there.
    func go(to place: Int) {
        if rendering { return pendingPlace = place }
        guard let length = textView.textStorage?.length, length > 0 else { return }
        // The top of the document is the top of the page, margin and all.
        guard place > 0 else {
            contentView.scroll(to: .zero)
            return reflectScrolledClipView(contentView)
        }
        scroll(toCharacter: min(place, length - 1), margin: 0)
    }

    /// Scrolls to the heading a #fragment names.
    func jump(to anchor: String) {
        let key = anchor.removingPercentEncoding ?? anchor
        guard let location = anchors[key] else {
            // The heading may be in the part of a large document still being rendered.
            if rendering { pendingAnchor = key } else { NSSound.beep() }
            return
        }
        scroll(toCharacter: location, margin: 12)
    }

    // Going by character rather than by position keeps this quick in a large document.
    private func scroll(toCharacter location: Int, margin: CGFloat) {
        guard let layout = textView.layoutManager, let container = textView.textContainer, location >= 0 else { return }
        let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: location, length: 1), actualCharacterRange: nil)
        let top = layout.boundingRect(forGlyphRange: glyphs, in: container).minY + textView.textContainerOrigin.y
        var target = contentView.bounds
        target.origin = NSPoint(x: 0, y: top - margin)
        // The view grows as the text below is laid out in the background, and a scroll past its
        // end stops short, so a place further down than it has grown yet is laid out first.
        if target.maxY > textView.frame.height {
            layout.ensureLayout(forBoundingRect: NSRect(x: 0, y: target.minY - textView.textContainerOrigin.y,
                                                        width: container.size.width, height: target.height), in: container)
            textView.sizeToFit()
        }
        contentView.scroll(to: contentView.constrainBoundsRect(target).origin)   // not past either end
        reflectScrolledClipView(contentView)
    }

    // MARK: Lines of the Markdown

    /// Whether the page knows which lines of the Markdown its blocks came from.
    var knowsSourceLines: Bool { !sourceLines.isEmpty }

    /// How far down a character's line is, in the view; the very first block counts from the top of
    /// the view, margin and all, as an editor's first line does.
    private func top(of index: Int, first: Bool) -> CGFloat {
        guard !first, let layout = textView.layoutManager, let container = textView.textContainer else { return 0 }
        let length = textView.textStorage?.length ?? 0
        guard index < length else { return textView.frame.height }
        let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
        return layout.boundingRect(forGlyphRange: glyphs, in: container).minY + textView.textContainerOrigin.y
    }

    /// The block a source line falls in, the next block that starts on a later line, and how far
    /// between them the line lies, from 0 to 1.
    private func span(at index: Int) -> (from: Int, to: Int?) {
        var from = index
        while from > 0, sourceLines[from - 1].line == sourceLines[index].line { from -= 1 }
        let to = sourceLines[(index + 1)...].firstIndex { $0.line > sourceLines[index].line }
        return (from, to)
    }

    /// The line of the Markdown at the top of the view, with the fraction of it scrolled past, as
    /// far as the blocks tell.
    func topSourceLine() -> Double? {
        guard !sourceLines.isEmpty else { return nil }
        let character = topCharacter()
        var low = 0, high = sourceLines.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if sourceLines[middle].location <= character { low = middle } else { high = middle - 1 }
        }
        let (from, to) = span(at: low)
        let startY = top(of: sourceLines[from].location, first: from == 0)
        let endY = to.map { top(of: sourceLines[$0].location, first: false) } ?? textView.frame.height
        let startLine = Double(sourceLines[from].line), endLine = Double(to.map { sourceLines[$0].line } ?? sourceLineCount)
        let fraction = endY > startY ? min(max((contentView.bounds.minY - startY) / (endY - startY), 0), 1) : 0
        return startLine + (endLine - startLine) * fraction
    }

    /// Scrolls so that a line of the Markdown, with a fraction, is at the top of the view.
    func scroll(toSourceLine line: Double) {
        guard !sourceLines.isEmpty else { return }
        var low = 0, high = sourceLines.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if Double(sourceLines[middle].line) <= line { low = middle } else { high = middle - 1 }
        }
        let (from, to) = span(at: low)
        let startY = top(of: sourceLines[from].location, first: from == 0)
        let endY = to.map { top(of: sourceLines[$0].location, first: false) } ?? textView.frame.height
        let startLine = Double(sourceLines[from].line), endLine = Double(to.map { sourceLines[$0].line } ?? sourceLineCount)
        let fraction = endLine > startLine ? min(max((line - startLine) / (endLine - startLine), 0), 1) : 0
        var target = contentView.bounds
        target.origin = NSPoint(x: 0, y: startY + (endY - startY) * fraction)
        contentView.scroll(to: contentView.constrainBoundsRect(target).origin)
        reflectScrolledClipView(contentView)
    }

    /// The line of the Markdown a character of the page came from, as near as its block tells.
    func sourceLine(at character: Int) -> Int? {
        guard let index = sourceLines.lastIndex(where: { $0.location <= character }) else { return nil }
        let (from, to) = span(at: index)
        guard let to else { return sourceLines[from].line }
        let start = sourceLines[from], end = sourceLines[to]
        let fraction = Double(character - start.location) / Double(max(end.location - start.location, 1))
        return start.line + Int(Double(end.line - start.line) * fraction)
    }

    // A #heading link in this document is followed here; any other link is the owner's to open.
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let target = link as? URL else { return true }
        if target.isFileURL, target.path == baseURL?.path, let fragment = target.fragment {
            willFollowLink()
            jump(to: fragment)
        } else {
            open(target)
        }
        return true
    }
}
