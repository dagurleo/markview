import AppKit

/// The text of a document: a centred column of at most Theme.columnWidth that
/// also accepts files dropped on it.
final class ColumnTextView: NSTextView {
    var onDrop: ([URL]) -> Void = { _ in }
    /// Whether the text has drawings (see NativeRenderer.drawing). Finding them in a large document takes a while.
    private(set) var hasDrawings = false
    /// The text container width the drawings were last fitted to.
    private var drawingsWidth = Theme.columnWidth

    /// Called with new text, whose drawings the renderer fitted to a full column.
    func textChanged(hasDrawings: Bool) {
        self.hasDrawings = hasDrawings
        drawingsWidth = Theme.columnWidth
        fitDrawings()
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

    override func setFrameSize(_ newSize: NSSize) {
        let clip = enclosingScrollView?.contentView
        let atTop = (clip?.bounds.origin.y ?? 1) <= 0
        let inset = NSSize(width: max(40, floor((newSize.width - Theme.columnWidth) / 2)), height: 24)
        if inset != textContainerInset { textContainerInset = inset }
        super.setFrameSize(newSize)
        // A large document's drawings wait for the end of a resize: finding them takes too long to do at every step.
        if !inLiveResize || (textStorage?.length ?? 0) < 1_000_000 { fitDrawings() }
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

/// An attachment that shrinks to the line it is on, so a figure drawn for the full column
/// still fits a narrower window, such as a Quick Look preview. Figures are vector images,
/// so they stay sharp.
final class FittingAttachment: NSTextAttachment {
    override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: NSRect,
                                   glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        var bounds = super.attachmentBounds(for: textContainer, proposedLineFragment: lineFrag, glyphPosition: position, characterIndex: charIndex)
        let room = lineFrag.width - 2 * (textContainer?.lineFragmentPadding ?? 0)
        if room > 0, bounds.width > room { bounds.size = NSSize(width: room, height: bounds.height * room / bounds.width) }
        return bounds
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
            let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? NSFont.systemFont(ofSize: Theme.bodySize)
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

    private var anchors: [String: Int] = [:]
    /// The headings of the rendered document, in order.
    private(set) var headings: [Heading] = []
    private var baseURL: URL?
    private var generation = 0
    private var rendering = false
    private var pendingAnchor: String?
    /// The drawings of the diagrams on show, so the same document shown again, as it is when
    /// the file changes, keeps them instead of flashing back to code while they are redrawn.
    private var drawn: [String: NSImage] = [:]

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
        textView.backgroundColor = Theme.background
        textView.linkTextAttributes = [.foregroundColor: Theme.link, .cursor: NSCursor.pointingHand]
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.registerForDraggedTypes([.fileURL])
        textView.onDrop = { [weak self] files in files.forEach { self?.open($0) } }
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
        backgroundColor = Theme.background
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Showing a document

    /// A small document is rendered at once. A large one shows its beginning straight
    /// away and is rendered in full on a background thread, then swapped in.
    func show(_ markdown: String, baseURL: URL) {
        self.baseURL = baseURL
        generation += 1
        let generation = generation
        let large = markdown.utf8.count > 256 * 1024

        if !large || textView.string.isEmpty {
            var beginning = markdown
            if large {
                // Cut at a paragraph break so the beginning is rarely caught mid-block.
                let from = markdown.index(markdown.startIndex, offsetBy: 96 * 1024, limitedBy: markdown.endIndex) ?? markdown.endIndex
                if let cut = markdown.range(of: "\n\n", range: from..<markdown.endIndex) { beginning = String(markdown[..<cut.lowerBound]) }
            }
            let renderer = NativeRenderer(baseURL: baseURL)
            replaceText(with: renderer.render(beginning), from: renderer, keepingPlace: !large)
        }
        rendering = large
        guard large else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let renderer = NativeRenderer(baseURL: baseURL)
            let rendered = renderer.render(markdown)
            DispatchQueue.main.async {
                guard generation == self.generation else { return }
                self.rendering = false
                self.replaceText(with: rendered, from: renderer, keepingPlace: true)
                if let anchor = self.pendingAnchor {
                    self.pendingAnchor = nil
                    self.jump(to: anchor)
                }
            }
        }
    }

    /// Shows the document's Markdown as written, in place of the rendered page.
    func showSource(_ markdown: String) {
        generation += 1
        rendering = false
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.25
        let text = NSAttributedString(string: markdown, attributes: [
            .font: Theme.font(size: 13, mono: true), .foregroundColor: Theme.text, .paragraphStyle: style])
        replaceText(with: text, from: nil, keepingPlace: false)
    }

    /// The character at the top of the view, or 0 at the top of the document.
    private func topCharacter() -> Int {
        guard let layout = textView.layoutManager, let container = textView.textContainer else { return 0 }
        // Asking which glyph sits at a point would lay out everything above it, which takes
        // minutes far down a large document. This only reads what is already laid out.
        var visible = contentView.bounds
        visible.origin.y -= textView.textContainerOrigin.y
        let glyphs = layout.glyphRange(forBoundingRectWithoutAdditionalLayout: visible, in: container)
        return visible.origin.y > 0 && glyphs.length > 0 ? layout.characterIndexForGlyph(at: glyphs.location) : 0
    }

    /// Swaps in new text and returns to the character that was at the top.
    private func replaceText(with rendered: NSAttributedString, from renderer: NativeRenderer?, keepingPlace: Bool) {
        guard let layout = textView.layoutManager, let container = textView.textContainer else { return }
        let top = topCharacter()
        // A fresh storage rather than an edit of the old one: replacing the text of a large,
        // partly laid out document in place took 14 seconds for 5 MB.
        contentView.scroll(to: .zero)
        // Laying out only what is looked at keeps a very large document usable, but it
        // misplaces boxed blocks after a resize, so ordinary documents do without it.
        layout.allowsNonContiguousLayout = rendered.length > 1_000_000
        layout.replaceTextStorage(NSTextStorage(attributedString: rendered))
        textView.textChanged(hasDrawings: renderer?.hasDrawings ?? false)
        anchors = renderer?.anchors ?? [:]
        headings = renderer?.headings ?? []
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
        fetch(renderer?.remoteImages ?? [])
        draw(renderer?.diagrams ?? [])
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
        storage.beginEditing()
        // From the end, so the ranges still to come stay where they were found.
        for (range, index) in placeholders.reversed() {
            let image = drawings[index]!, diagram = diagrams[index]
            let attachment = FittingAttachment()
            attachment.image = image
            attachment.bounds = NSRect(origin: .zero, size: image.size)
            let text = "\u{FFFC}\n"
            let attributes: [NSAttributedString.Key: Any] = [.paragraphStyle: diagram.block, .font: Theme.font(size: Theme.bodySize),
                                                             .attachment: attachment, ColumnTextView.written: diagram.written]
            storage.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: attributes))
            // Heading links and the place in the document move with the text after the diagram.
            let shift = (text as NSString).length - range.length
            for (anchor, location) in anchors where location > range.location { anchors[anchor] = location + shift }
            if top > range.location { top = max(range.location, top + shift) }
        }
        storage.endEditing()
        if top > 0 { scroll(toCharacter: top, margin: 0) }
    }

    private func fetch(_ images: [(attachment: NSTextAttachment, url: URL, width: CGFloat?, height: CGFloat?)]) {
        for (attachment, url, width, height) in images {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let picture = NSImage(data: data) else { return }
                DispatchQueue.main.async {
                    NativeRenderer.fit(picture, width: width, height: height)
                    attachment.image = picture
                    guard let self, let storage = self.textView.textStorage else { return }
                    self.textView.layoutManager?.invalidateLayout(
                        forCharacterRange: NSRange(location: 0, length: storage.length), actualCharacterRange: nil)
                }
            }.resume()
        }
    }

    // MARK: Moving around

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
        contentView.scroll(to: contentView.constrainBoundsRect(target).origin)   // not past either end
        reflectScrolledClipView(contentView)
    }

    // A #heading link in this document is followed here; any other link is the owner's to open.
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let target = link as? URL else { return true }
        if target.isFileURL, target.path == baseURL?.path, let fragment = target.fragment { jump(to: fragment) } else { open(target) }
        return true
    }
}
