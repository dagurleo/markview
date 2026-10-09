import Cocoa

/// The editor beside the page (View > Show Editor): the document's Markdown as written, coloured
/// by SourceHighlighter, with a bar above it when the file changes on disk under unsaved edits.
///
/// Every window showing a document edits the same text: each editor lays out the document's one
/// text storage (see MarkdownDocument.source) with a layout manager of its own.
final class SourceEditor: NSView, NSTextViewDelegate {
    let textView: SourceTextView
    let scrollView = NSScrollView()
    private let bar = ChangeOnDiskBar()
    private var theme = Settings.theme
    private(set) var settings = EditorSettings.current
    private lazy var lineNumbers = LineNumbers(editor: self)
    /// What the text view lays out while it shows no document. A layout manager does not keep its
    /// text storage, so this one is kept here.
    private let blank = NSTextStorage()
    /// The document whose text is on show.
    private weak var document: MarkdownDocument?
    /// Called whenever the editor scrolls.
    var onScroll: () -> Void = {}
    /// Where each line of the text starts, worked out when first needed after the text changes.
    private var lineStarts: [Int]?
    private var textObserver: NSObjectProtocol?

    var onDrop: ([URL]) -> Void {
        get { textView.onDrop }
        set { textView.onDrop = newValue }
    }

    override init(frame: NSRect) {
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: frame.width, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        textView = SourceTextView(frame: NSRect(origin: .zero, size: frame.size), textContainer: container)
        super.init(frame: frame)
        blank.addLayoutManager(layout)

        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.usesFontPanel = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 20, height: 24)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: frame.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = self
        textView.onTypingSettingChange = { [weak self] in self?.keepTypingSettings() }
        // The edited lines are coloured once the text view is done with the edit.
        textView.onEdit = { [weak self] in self?.document?.colourEdits() }
        textView.folder = { [weak self] in self?.document.flatMap { $0.fileURL?.deletingLastPathComponent() ?? $0.draftFolder } }

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        // As with the page: the window's transparent title bar would otherwise add a top inset.
        scrollView.automaticallyAdjustsContentInsets = false

        let stack = NSStackView(views: [bar, scrollView])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.widthAnchor.constraint(equalTo: stack.widthAnchor), scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main) { [weak self] _ in
            self?.lineNumbers.needsDisplay = true
            self?.textView.slashMenuFollows()
            self?.onScroll()
        }
        bar.isHidden = true
        bar.onReload = { [weak self] in self?.document?.reloadDiscardingEdits() }
        bar.onKeep = { [weak self] in self?.document?.keepEdits() }
        apply(theme)
        apply(settings)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows a document's text, in place of whatever was on show.
    func show(_ document: MarkdownDocument) {
        guard let layout = textView.layoutManager else { return }
        let storage = document.editableSource(theme: editorTheme)
        if self.document !== document { leave() }
        self.document = document
        if layout.textStorage !== storage {
            layout.textStorage?.removeLayoutManager(layout)
            storage.addLayoutManager(layout)
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.scroll(.zero)
            watch(storage)
        }
        recolour()
        reflectChangeOnDisk()
    }

    /// Lets go of the document on show: its text no longer lays itself out here, and edits made here
    /// are no longer undone through this view, which may go on to show another document.
    func leave() {
        guard let document, let layout = textView.layoutManager else { return }
        textView.closeSlashMenu()
        document.undoManager?.removeAllActions(withTarget: textView)
        // A text storage keeps its layout managers, and would go on laying this one out.
        layout.textStorage?.removeLayoutManager(layout)
        blank.addLayoutManager(layout)
        watch(nil)
        self.document = nil
    }

    // MARK: Lines

    /// The text changes in this window or another showing the same document.
    private func watch(_ storage: NSTextStorage?) {
        textObserver.map(NotificationCenter.default.removeObserver)
        textObserver = nil
        lineStarts = nil
        guard let storage else { return }
        textObserver = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: nil) { [weak self, weak storage] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.lineStarts = nil
                self.lineNumbers.textChanged()
                if let storage, storage.editedMask.contains(.editedCharacters) {
                    self.textView.textEdited(storage.editedRange, changeInLength: storage.changeInLength)
                }
            }
        }
    }

    /// Where each line starts.
    var starts: [Int] {
        if let lineStarts { return lineStarts }
        let text = textView.textStorage?.mutableString ?? NSMutableString()
        var found = [0], location = 0
        while location < text.length {
            let newline = text.range(of: "\n", options: .literal, range: NSRange(location: location, length: text.length - location))
            guard newline.location != NSNotFound else { break }
            location = NSMaxRange(newline)
            found.append(location)
        }
        lineStarts = found
        return found
    }

    /// The line, counting from 0, that holds a character.
    func line(of character: Int) -> Int {
        let starts = starts
        var low = 0, high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= character { low = middle } else { high = middle - 1 }
        }
        return low
    }

    /// Where a line is in the view, from the top of its first row to the bottom of its last; the
    /// first line counts from the top of the view, margin and all, as the page's first block does.
    private func frame(ofLine line: Int) -> (top: CGFloat, bottom: CGFloat)? {
        guard let layout = textView.layoutManager, let container = textView.textContainer else { return nil }
        let starts = starts, length = textView.textStorage?.length ?? 0
        guard line < starts.count else { return nil }
        let end = line + 1 < starts.count ? starts[line + 1] : length
        let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: starts[line], length: max(end - starts[line], 0)), actualCharacterRange: nil)
        var rect = glyphs.length > 0 ? layout.boundingRect(forGlyphRange: glyphs, in: container) : layout.extraLineFragmentRect
        rect.origin.y += textView.textContainerOrigin.y
        return (line == 0 ? 0 : rect.minY, rect.maxY)
    }

    /// The line at the top of the view, with the fraction of it scrolled past.
    func topLine() -> Double {
        guard let layout = textView.layoutManager, let container = textView.textContainer, (textView.textStorage?.length ?? 0) > 0 else { return 0 }
        let top = scrollView.contentView.bounds.minY
        let point = NSPoint(x: 0, y: max(top - textView.textContainerOrigin.y, 0))
        let line = line(of: layout.characterIndexForGlyph(at: layout.glyphIndex(for: point, in: container)))
        guard let frame = frame(ofLine: line), frame.bottom > frame.top else { return Double(line) }
        return Double(line) + min(max((top - frame.top) / (frame.bottom - frame.top), 0), 1)
    }

    /// Scrolls so that a line, with a fraction, is at the top of the view.
    func scroll(toLine line: Double) {
        let whole = min(max(Int(line), 0), starts.count - 1)
        guard let frame = frame(ofLine: whole) else { return }
        let clip = scrollView.contentView
        var target = clip.bounds
        target.origin = NSPoint(x: 0, y: frame.top + (frame.bottom - frame.top) * min(max(line - Double(whole), 0), 1))
        clip.scroll(to: clip.constrainBoundsRect(target).origin)
        scrollView.reflectScrolledClipView(clip)
    }

    /// Puts the insertion point at the start of a line, scrolling it into view if it is not.
    func reveal(line: Int) {
        let starts = starts
        let location = starts[min(max(line, 0), starts.count - 1)]
        textView.setSelectedRange(NSRange(location: location, length: 0))
        textView.scrollRangeToVisible(NSRange(location: location, length: 0))
        window?.makeFirstResponder(textView)
    }

    func apply(_ theme: Theme) {
        self.theme = theme
        scrollView.backgroundColor = theme.background
        textView.backgroundColor = theme.background
        textView.insertionPointColor = theme.text
        bar.apply(theme)
        lineNumbers.colors = (theme.muted, theme.background)
        recolour()
    }

    /// The theme the text is coloured in: the page's, in the editor's own font if one is chosen.
    private var editorTheme: Theme {
        guard !settings.font.isEmpty else { return theme }
        return Theme(palette: theme.palette, bodySize: theme.bodySize, textFont: theme.textFont, codeFont: settings.font,
                     columnWidth: theme.columnWidth, lineSpacing: theme.lineSpacing)
    }

    private func recolour() {
        guard let document else { return }
        document.apply(editorTheme)
        textView.typingAttributes = document.typingAttributes
        lineNumbers.font = SourceHighlighter.font(editorTheme)
    }

    /// Settings > Editor, and the Edit menu's spelling and substitutions.
    func apply(_ settings: EditorSettings) {
        let fontChanged = settings.font != self.settings.font
        self.settings = settings
        textView.indent = settings.indent
        textView.offersSlashMenu = settings.slashMenu
        textView.isContinuousSpellCheckingEnabled = settings.spelling
        textView.isAutomaticQuoteSubstitutionEnabled = settings.smartQuotes
        textView.isAutomaticDashSubstitutionEnabled = settings.smartDashes
        textView.isAutomaticTextReplacementEnabled = settings.textReplacement
        // Long lines wrap at the edge, or run on with a scroller below.
        guard let container = textView.textContainer else { return }
        if settings.wraps != container.widthTracksTextView {
            container.widthTracksTextView = settings.wraps
            textView.isHorizontallyResizable = !settings.wraps
            scrollView.hasHorizontalScroller = !settings.wraps
            container.size = NSSize(width: settings.wraps ? scrollView.contentSize.width : CGFloat.greatestFiniteMagnitude,
                                    height: CGFloat.greatestFiniteMagnitude)
            if settings.wraps { textView.setFrameSize(NSSize(width: scrollView.contentSize.width, height: textView.frame.height)) }
        }
        if scrollView.verticalRulerView !== lineNumbers { scrollView.verticalRulerView = lineNumbers }
        scrollView.hasVerticalRuler = settings.lineNumbers
        scrollView.rulersVisible = settings.lineNumbers
        if fontChanged { recolour() }
    }

    /// Keeps what the Edit menu turned on or off, for every editor.
    private func keepTypingSettings() {
        let defaults = Settings.defaults
        defaults.set(textView.isContinuousSpellCheckingEnabled, forKey: EditorSettings.Key.spelling)
        defaults.set(textView.isAutomaticQuoteSubstitutionEnabled, forKey: EditorSettings.Key.smartQuotes)
        defaults.set(textView.isAutomaticDashSubstitutionEnabled, forKey: EditorSettings.Key.smartDashes)
        defaults.set(textView.isAutomaticTextReplacementEnabled, forKey: EditorSettings.Key.textReplacement)
    }

    /// Shows the bar while the file on disk has changed under unsaved edits, and hides it once settled.
    func reflectChangeOnDisk() {
        bar.isHidden = document?.changedOnDisk != true
        bar.name = document?.displayName ?? ""
    }

    // MARK: Text view

    // Edits are undone with the document's own undo list, which also tracks whether it has unsaved
    // changes. Every window showing the document shares it.
    func undoManager(for view: NSTextView) -> UndoManager? { document?.undoManager }

    // Spelling looks at prose only, not at code, addresses, tags or the marks around them.
    func textView(_ textView: NSTextView, shouldSetSpellingState value: Int, range affectedCharRange: NSRange) -> Int {
        guard value != 0, let storage = textView.textStorage, NSMaxRange(affectedCharRange) <= storage.length else { return value }
        var notProse = false
        storage.enumerateAttribute(SourceHighlighter.notProse, in: affectedCharRange) { flag, _, stop in
            if flag != nil { notProse = true; stop.pointee = true }
        }
        return notProse ? 0 : value
    }

    // Text is typed plain and coloured once it is in.
    func textView(_ textView: NSTextView, shouldChangeTypingAttributes oldTypingAttributes: [String: Any] = [:],
                  toAttributes newTypingAttributes: [NSAttributedString.Key: Any] = [:]) -> [NSAttributedString.Key: Any] {
        document?.typingAttributes ?? newTypingAttributes
    }
}

/// Above the editor when the file has changed on disk while it holds unsaved edits: which to keep.
final class ChangeOnDiskBar: NSView {
    var onReload: () -> Void = {}
    var onKeep: () -> Void = {}
    var name = "" { didSet { label.stringValue = "“\(name)” was changed by another app." } }
    private let label = NSTextField(labelWithString: "")
    private let reload = NSButton(title: "Reload", target: nil, action: nil)
    private let keep = NSButton(title: "Keep My Edits", target: nil, action: nil)
    private var fill: NSColor = .clear, line: NSColor = .separatorColor

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.font = .systemFont(ofSize: 12)
        reload.target = self
        reload.action = #selector(reloadPressed)
        reload.toolTip = "Throw away the unsaved edits and show the file as it is now"
        keep.target = self
        keep.action = #selector(keepPressed)
        keep.toolTip = "Keep editing; saving replaces the file on disk"
        for button in [reload, keep] {
            button.bezelStyle = .push
            button.controlSize = .small
            button.font = .systemFont(ofSize: 11)
        }
        let row = NSStackView(views: [label, keep, reload])
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 10)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func apply(_ theme: Theme) {
        fill = theme.callout("WARNING").color.withAlphaComponent(0.14)
        line = theme.border
        label.textColor = theme.text
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        fill.setFill()
        bounds.fill()
        line.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    @objc private func reloadPressed() { onReload() }
    @objc private func keepPressed() { onKeep() }
}
