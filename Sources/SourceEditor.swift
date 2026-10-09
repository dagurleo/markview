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
    /// What the text view lays out while it shows no document. A layout manager does not keep its
    /// text storage, so this one is kept here.
    private let blank = NSTextStorage()
    /// The document whose text is on show.
    private weak var document: MarkdownDocument?

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
        // Markdown is written for code as much as prose: nothing changes what is typed by itself.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.textContainerInset = NSSize(width: 20, height: 24)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: frame.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = self

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
        bar.isHidden = true
        bar.onReload = { [weak self] in self?.document?.reloadDiscardingEdits() }
        bar.onKeep = { [weak self] in self?.document?.keepEdits() }
        apply(theme)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows a document's text, in place of whatever was on show.
    func show(_ document: MarkdownDocument) {
        guard let layout = textView.layoutManager else { return }
        let storage = document.editableSource(theme: theme)
        if self.document !== document { leave() }
        self.document = document
        if layout.textStorage !== storage {
            layout.textStorage?.removeLayoutManager(layout)
            storage.addLayoutManager(layout)
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.scroll(.zero)
        }
        textView.typingAttributes = document.typingAttributes
        reflectChangeOnDisk()
    }

    /// Lets go of the document on show: its text no longer lays itself out here, and edits made here
    /// are no longer undone through this view, which may go on to show another document.
    func leave() {
        guard let document, let layout = textView.layoutManager else { return }
        document.undoManager?.removeAllActions(withTarget: textView)
        // A text storage keeps its layout managers, and would go on laying this one out.
        layout.textStorage?.removeLayoutManager(layout)
        blank.addLayoutManager(layout)
        self.document = nil
    }

    func apply(_ theme: Theme) {
        self.theme = theme
        scrollView.backgroundColor = theme.background
        textView.backgroundColor = theme.background
        textView.insertionPointColor = theme.text
        bar.apply(theme)
        if let document {
            document.apply(theme)
            textView.typingAttributes = document.typingAttributes
        }
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

/// The editor's text view. Files dropped on it open, as on the page, rather than being typed in as
/// their paths; dragged text still moves and copies as usual.
final class SourceTextView: NSTextView {
    var onDrop: ([URL]) -> Void = { _ in }

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
