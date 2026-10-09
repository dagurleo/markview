import Cocoa
import Quartz
import UniformTypeIdentifiers

final class ViewerWindowController: NSWindowController, DocumentOutline, DocumentActions {
    private let markdownView: MarkdownView
    private let sidebar = Sidebar()
    private var outline: OutlineList { sidebar.outline }
    private let outlineItem: NSSplitViewItem
    /// The folder the window shows the documents of, if it was opened on one (see Folders).
    private(set) var root: URL?
    private let divider = OutlineSplitView()
    /// A heading chosen in the outline stays marked while the page stays where it went: near
    /// the end of a document the page cannot bring it to the top.
    private var chosen: (index: Int, top: CGFloat)?
    /// Scripted checks show no outline, unless asked, and leave its setting alone.
    private let scripted = ProcessInfo.processInfo.environment["MARKVIEW_SNAPSHOT"] != nil
    private var didRunSmokeTestHooks = false
    /// The Markdown as written, beside the page, for editing (View > Show Editor). Every window opens
    /// without it but a new document's.
    private let editor = SourceEditor(frame: NSRect(x: 0, y: 0, width: 560, height: 600))
    private let editorItem: NSSplitViewItem
    private let editorSplit: NSSplitViewController
    private let editorDivider = OutlineSplitView()
    /// How much wider the window grew to make room for the editor, given back when it closes.
    private var roomForEditor: CGFloat?
    /// The page follows the editor once typing pauses.
    private var pendingUpdate: DispatchWorkItem?
    /// What to do once the reader has said what becomes of unsaved edits in the document left.
    private var pendingLeave: (() -> Void)?
    /// Scripted checks open documents at the top and leave the places alone, unless asked.
    private let keepsPlace = ProcessInfo.processInfo.environment["MARKVIEW_SNAPSHOT"] == nil
        || ProcessInfo.processInfo.environment["MARKVIEW_KEEP_PLACE"] != nil
    private var pendingPlace: DispatchWorkItem?
    /// Where the document was last read, gone back to once the window is on screen: until
    /// then its lines have not settled where they will be.
    private var placeToRestore: Int?
    /// The picture shown full size in the Quick Look panel, and where it sits on screen.
    private var preview: (file: URL, frame: NSRect)?

    var headings: [Heading] { markdownView.headings }

    init() {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 900
        let frame = NSRect(x: 0, y: 0, width: 880, height: min(1000, screenHeight - 60))
        let window = NSWindow(
            contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: true)
        markdownView = MarkdownView(frame: frame)
        window.contentMinSize = NSSize(width: 360, height: 240)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = markdownView.theme.background

        // The outline and the page side by side; the outline keeps its width as the window resizes.
        let split = NSSplitViewController()
        divider.isVertical = true
        divider.dividerStyle = .thin
        divider.color = markdownView.theme.border
        split.splitView = divider
        outlineItem = NSSplitViewItem(viewController: sidebar)
        outlineItem.canCollapse = true
        outlineItem.minimumThickness = 150
        outlineItem.maximumThickness = 400
        outlineItem.holdingPriority = NSLayoutConstraint.Priority(260)
        // Beside the outline, the editor and the page, side by side in a split of their own; the
        // page takes up a change in the window's width.
        editorSplit = NSSplitViewController()
        editorDivider.isVertical = true
        editorDivider.dividerStyle = .thin
        editorDivider.color = markdownView.theme.border
        editorSplit.splitView = editorDivider
        let source = NSViewController()
        source.view = editor
        editorItem = NSSplitViewItem(viewController: source)
        editorItem.canCollapse = true
        editorItem.minimumThickness = 280
        editorItem.holdingPriority = NSLayoutConstraint.Priority(255)
        editorItem.isCollapsed = true
        let page = NSViewController()
        page.view = markdownView
        let pageItem = NSSplitViewItem(viewController: page)
        pageItem.minimumThickness = 280
        editorSplit.addSplitViewItem(editorItem)
        editorSplit.addSplitViewItem(pageItem)
        let contentItem = NSSplitViewItem(viewController: editorSplit)
        contentItem.minimumThickness = 280
        split.addSplitViewItem(outlineItem)
        split.addSplitViewItem(contentItem)
        split.view.frame = frame
        if !scripted { divider.autosaveName = "Outline" }
        outlineItem.isCollapsed = scripted ? ProcessInfo.processInfo.environment["MARKVIEW_OUTLINE"] == nil
            : !UserDefaults.standard.bool(forKey: "showsOutline")
        window.contentViewController = split
        window.setContentSize(frame.size)
        window.center()
        super.init(window: window)

        let zoom = UserDefaults.standard.double(forKey: "pageZoom")
        markdownView.magnification = zoom > 0 ? zoom : 1
        markdownView.open = { [weak self] url in self?.open(url) }
        markdownView.openDropped = { [weak self] url in self?.openDropped(url) }
        editor.onDrop = { [weak self] files in files.forEach { self?.openDropped($0) } }
        markdownView.willFollowLink = { [weak self] in self?.leaving() }
        markdownView.onPreview = { [weak self] file, frame in self?.showPreview(of: file, from: frame) }
        markdownView.onScroll = { [weak self] in
            self?.scrolled()
            self?.markCurrentHeading()
        }
        markdownView.onShow = { [weak self] in
            guard let self else { return }
            outline.show(markdownView.headings)
            markCurrentHeading()
        }
        sidebar.files.onSelect = { [weak self] file in
            self?.leavingDocument(for: file) { [weak self] in
                guard let self else { return }
                leaving()
                show(file) { [weak self] _ in self?.window?.makeFirstResponder(self?.markdownView.textView) }
            }
        }
        outline.onSelect = { [weak self] heading in
            guard let self, let index = headings.firstIndex(where: { $0.anchor == heading.anchor }) else { return }
            leaving()
            show(headingAt: index)
            self.window?.makeFirstResponder(markdownView.textView)
        }
        windowFrameAutosaveName = "Viewer"
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            self?.rememberPlace()
            self?.editor.leave()
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.rememberPlace()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var document: AnyObject? {
        didSet {
            // The editor, if open, goes on to the document the window moves on to.
            if let document = document as? MarkdownDocument {
                if !editorItem.isCollapsed { editor.show(document) }
            } else {
                editor.leave()
            }
            render()
            sidebar.files.current = (document as? NSDocument)?.fileURL
            // A #heading the document was opened at comes after this, and wins. A document the
            // window moves on to, as it follows a link, starts at its top instead.
            if keepsPlace, window?.isVisible != true, let file = (document as? NSDocument)?.fileURL { placeToRestore = Places.place(of: file) }
            if document != nil, !didRunSmokeTestHooks {
                didRunSmokeTestHooks = true
                runSmokeTestHooks()
            }
        }
    }

    /// Shows the document again in another theme, keeping the place in it.
    func show(_ theme: Theme) {
        markdownView.theme = theme
        window?.backgroundColor = theme.background
        sidebar.apply(theme)
        divider.color = theme.border
        editorDivider.color = theme.border
        editor.apply(theme)
        render()
    }

    // MARK: Outline

    /// A window opened on a folder lists its documents in the sidebar, which it opens with, and
    /// names the folder under the document's name.
    func show(folder: URL, tree: FileNode) {
        root = folder
        sidebar.show(folder: folder, tree: tree)
        outlineItem.isCollapsed = false
        window?.subtitle = folder.lastPathComponent
    }

    /// The page narrows or widens as the outline comes and goes, and its lines rewrap; the
    /// place in it is kept by its character, as when the window is resized.
    @objc func toggleOutline(_ sender: Any?) {
        let place = markdownView.place
        NSAnimationContext.runAnimationGroup { _ in
            outlineItem.animator().isCollapsed.toggle()
        } completionHandler: { [self] in
            if place > 0 { markdownView.go(to: place) } else { markdownView.contentView.scroll(to: .zero) }
            markCurrentHeading()
        }
        if !scripted { UserDefaults.standard.set(!outlineItem.isCollapsed, forKey: "showsOutline") }
    }

    /// Goes to a heading, which the outline marks while the page stays there.
    private func show(headingAt index: Int) {
        markdownView.jump(to: headings[index].anchor)
        chosen = (index, markdownView.contentView.bounds.minY)
        if !outlineItem.isCollapsed { outline.mark(index) }
    }

    // MARK: Headings one at a time

    /// The heading after the one being read.
    @objc func goToNextHeading(_ sender: Any?) {
        let probe = markdownView.topCharacter(offset: 40)
        guard let next = headings.indices.first(where: { (markdownView.location(of: headings[$0].anchor) ?? 0) > probe }) else { return NSSound.beep() }
        show(headingAt: next)
    }

    /// The start of the section being read, or from its start, the heading before it.
    @objc func goToPreviousHeading(_ sender: Any?) {
        let probe = markdownView.topCharacter(offset: 40), top = markdownView.topCharacter()
        guard let current = headings.indices.last(where: { (markdownView.location(of: headings[$0].anchor) ?? .max) <= probe }) else { return NSSound.beep() }
        let atItsStart = (markdownView.location(of: headings[current].anchor) ?? 0) >= top
        guard !atItsStart || current > 0 else { return NSSound.beep() }
        show(headingAt: atItsStart ? current - 1 : current)
    }

    /// The heading being read is the last one to start above a point a little below the top of
    /// the page, so a heading just scrolled to counts as read.
    private func markCurrentHeading() {
        guard !outlineItem.isCollapsed else { return }
        if let chosen, chosen.top == markdownView.contentView.bounds.minY { return outline.mark(chosen.index) }
        chosen = nil
        let probe = markdownView.topCharacter(offset: 40)
        var current: Int?
        for (index, heading) in outline.headings.enumerated() {
            guard let location = markdownView.location(of: heading.anchor) else { continue }
            if location > probe { break }
            current = index
        }
        outline.mark(current)
    }

    func render() {
        guard let document = document as? MarkdownDocument, let baseURL else { return }
        markdownView.show(document.markdown, baseURL: baseURL)
    }

    /// Where the document's pictures and links are found from: its file, or for a new one not yet
    /// saved, the folder it was made from.
    private var baseURL: URL? {
        guard let document = document as? MarkdownDocument else { return nil }
        if let file = document.fileURL { return file }
        let folder = document.draftFolder ?? root ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return folder.appendingPathComponent("Untitled.md")
    }

    // MARK: Editor

    /// Opens the editor beside the page, or closes it. The window widens to make room for it if the
    /// screen has room, so the page keeps its width, and narrows again when it closes; otherwise
    /// the two share the window.
    @objc func toggleEditor(_ sender: Any?) {
        guard let window, let document = document as? MarkdownDocument else { return }
        let place = markdownView.place
        if editorItem.isCollapsed {
            editor.show(document)
            let width = CGFloat(UserDefaults.standard.double(forKey: "editorWidth")).clamped(to: 280...1200, default: 560)
            var frame = window.frame
            let room = width + editorDivider.dividerThickness
            if !window.styleMask.contains(.fullScreen), let screen = (window.screen ?? NSScreen.main)?.visibleFrame,
               frame.width + room <= screen.width {
                frame.size.width += room
                frame.origin.x = max(screen.minX, min(frame.origin.x, screen.maxX - frame.width))
                roomForEditor = room
                // The viewer's size, not the editor's, is the one new windows open at.
                windowFrameAutosaveName = ""
                window.setFrame(frame, display: true)
            }
            editorItem.isCollapsed = false
            let available = editorSplit.splitView.bounds.width
            editorSplit.splitView.setPosition(roomForEditor != nil ? width : min(width, floor(available / 2)), ofDividerAt: 0)
            window.makeFirstResponder(editor.textView)
            reflectChangeOnDisk()
        } else {
            let width = editor.frame.width
            if !scripted { UserDefaults.standard.set(Double(width), forKey: "editorWidth") }
            if let responder = window.firstResponder as? NSView, responder.isDescendant(of: editor) {
                window.makeFirstResponder(markdownView.textView)
            }
            editorItem.isCollapsed = true
            if roomForEditor != nil, !window.styleMask.contains(.fullScreen) {
                var frame = window.frame
                frame.size.width = max(window.minSize.width, frame.width - width - editorDivider.dividerThickness)
                window.setFrame(frame, display: true)
                if !scripted { windowFrameAutosaveName = "Viewer" }
            }
            roomForEditor = nil
        }
        invalidateRestorableState()
        // The page narrows or widens and its lines rewrap; the place in it is kept by its character.
        DispatchQueue.main.async { [self] in
            if place > 0 { markdownView.go(to: place) } else { markdownView.contentView.scroll(to: .zero) }
            markCurrentHeading()
        }
    }

    // A window put back after a relaunch opens without the editor, so it gives back the room it had
    // made for it.
    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        coder.encode(Double(roomForEditor ?? 0), forKey: "roomForEditor")
    }

    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)
        let room = CGFloat(coder.decodeDouble(forKey: "roomForEditor"))
        guard room > 0, editorItem.isCollapsed, let window else { return }
        var frame = window.frame
        frame.size.width = max(window.minSize.width, frame.width - room)
        window.setFrame(frame, display: true)
    }

    /// Opens the editor, as for a new document, if it is not open already.
    func showEditor() {
        if editorItem.isCollapsed { toggleEditor(nil) }
    }

    /// The text changed in an editor, or was read again from disk. The page follows once typing
    /// pauses: longer documents take longer to render, so they wait for a longer pause.
    func textChanged() {
        pendingUpdate?.cancel()
        let length = (document as? MarkdownDocument)?.length ?? 0
        let work = DispatchWorkItem { [weak self] in
            guard let self, let document = document as? MarkdownDocument, let baseURL else { return }
            markdownView.update(document.markdown, baseURL: baseURL)
        }
        pendingUpdate = work
        let pause = length < 50_000 ? 0.15 : length < 250_000 ? 0.4 : length < 1_000_000 ? 1 : 3
        DispatchQueue.main.asyncAfter(deadline: .now() + pause, execute: work)
    }

    /// The document was saved under a name, or its file renamed or moved.
    func documentMoved() {
        sidebar.files.current = (document as? NSDocument)?.fileURL
        editor.reflectChangeOnDisk()
        textChanged()
    }

    /// The file changed on disk under unsaved edits, or that was settled: the editor shows which to
    /// keep while it is not.
    func reflectChangeOnDisk() {
        if (document as? MarkdownDocument)?.changedOnDisk == true, editorItem.isCollapsed { return toggleEditor(nil) }
        editor.reflectChangeOnDisk()
    }

    /// Runs `body`, which moves the window to `file`, once the document on show can be left. Leaving
    /// closes it if no other window shows it, so with unsaved edits the reader is asked first
    /// whether to save them; nothing happens if they cancel.
    private func leavingDocument(for file: URL, _ body: @escaping () -> Void) {
        guard let current = document as? NSDocument, current.fileURL?.standardizedFileURL != file.standardizedFileURL,
              current.isDocumentEdited, current.windowControllers.count == 1 else { return body() }
        pendingLeave = body
        current.canClose(withDelegate: self, shouldClose: #selector(document(_:shouldClose:contextInfo:)), contextInfo: nil)
    }

    @objc private func document(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
        let body = pendingLeave
        pendingLeave = nil
        if shouldClose { body?() }
    }

    // MARK: Pictures full size

    private func showPreview(of file: URL, from frame: NSRect) {
        preview = (file, frame)
        markdownView.textView.passesPreviewPanel = true
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible { panel.reloadData() } else { panel.makeKeyAndOrderFront(nil) }
    }

    // The window's controller is in the responder chain, so the panel asks it what to show.
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { preview != nil }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
        preview = nil
        markdownView.textView.passesPreviewPanel = false
    }

    // MARK: Place

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        guard let place = placeToRestore else { return }
        placeToRestore = nil
        DispatchQueue.main.async { self.markdownView.go(to: place) }
    }

    private func scrolled() {
        pendingPlace?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.rememberPlace() }
        pendingPlace = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Not while a large document is still on its way to the place it opens at.
    private func rememberPlace() {
        guard keepsPlace, !markdownView.rendering, let file = (document as? NSDocument)?.fileURL else { return }
        Places.remember(markdownView.place, of: file)
    }

    @objc func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleEditor(_:)) { item.title = editorItem.isCollapsed ? "Show Editor" : "Hide Editor" }
        if item.action == #selector(showReplaceBar(_:)) { return document != nil }
        if item.action == #selector(toggleOutline(_:)) { item.title = outlineItem.isCollapsed ? "Show Sidebar" : "Hide Sidebar" }
        if item.action == #selector(goToNextHeading(_:)) || item.action == #selector(goToPreviousHeading(_:)) { return !headings.isEmpty }
        if item.action == #selector(goBack(_:)) { return !backStops.isEmpty }
        if item.action == #selector(goForward(_:)) { return !forwardStops.isEmpty }
        return true
    }

    // MARK: Printing

    @objc func printDocument(_ sender: Any?) {
        guard let window else { return }
        let operation = NSPrintOperation(view: pageForPrinting(), printInfo: printInfo())
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    @objc func exportPDF(_ sender: Any?) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = ((document as? NSDocument)?.fileURL?.deletingPathExtension().lastPathComponent ?? "Document") + ".pdf"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.writePDF(to: url)
        }
    }

    func writePDF(to url: URL) {
        let page = pageForPrinting()
        let operation = NSPrintOperation.pdfOperation(with: page, inside: page.bounds, toPath: url.path, printInfo: printInfo())
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.run()
    }

    /// The page laid out at the width of the text column, in the theme's light colours whatever
    /// the window shows, so what prints does not depend on the window's size or appearance.
    private func pageForPrinting() -> NSTextView {
        let column = markdownView.theme.columnWidth
        let text = markdownView.textView
        let storage = NativeRenderer.copy(text.attributedString(), tables: text.tables, fittedTo: column)
        if text.hasDrawings { NativeRenderer.fitDrawings(in: storage, width: column) }
        let layout = BoxedLayoutManager()
        storage.addLayoutManager(layout)
        let width = column + 48
        let container = NSTextContainer(size: NSSize(width: width - 48, height: CGFloat.greatestFiniteMagnitude))
        layout.addTextContainer(container)
        let page = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100), textContainer: container)
        page.textContainerInset = NSSize(width: 24, height: 24)
        page.appearance = NSAppearance(named: .aqua)
        page.drawsBackground = false
        layout.ensureLayout(for: container)
        page.frame.size.height = layout.usedRect(for: container).height + 48
        return page
    }

    private func printInfo() -> NSPrintInfo {
        let info = NSPrintInfo()
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = false
        info.topMargin = 36
        info.bottomMargin = 36
        info.leftMargin = 36
        info.rightMargin = 36
        return info
    }

    // MARK: Links

    /// Markdown opens here, web links go to the browser, and any other local file
    /// is only revealed in Finder, so a link in a document can never launch an app
    /// or script. A file dropped on the window follows the same rules.
    /// A heading chosen in the Go menu; the place left goes on the back list.
    func jump(to anchor: String) {
        leaving()
        markdownView.jump(to: anchor)
    }

    /// The heading a document was opened at.
    func open(fragment: String) { markdownView.jump(to: fragment) }

    /// Another Markdown document opens in this window, as a browser follows a link, or with ⌘
    /// held in a window of its own.
    private func open(_ url: URL) {
        if url.isFileURL {
            let file = URL(fileURLWithPath: url.path)
            if Links.markdownExtensions.contains(file.pathExtension.lowercased()) {
                if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                    var target = URLComponents(url: file, resolvingAgainstBaseURL: false)
                    target?.fragment = url.fragment
                    AppDelegate.open(target?.url ?? file)
                } else {
                    follow(file, to: url.fragment)
                }
            } else if FileManager.default.fileExists(atPath: file.path) {
                NSWorkspace.shared.activateFileViewerSelecting([file])
            } else {
                NSSound.beep()
            }
        } else if Links.webSchemes.contains(url.scheme ?? "") {
            NSWorkspace.shared.open(url)
        }
    }

    /// A file or folder dropped on the page opens in a window of its own, as one dropped on the Dock icon does.
    private func openDropped(_ url: URL) {
        if url.isFileURL, Folders.isFolder(url) || Links.markdownExtensions.contains(url.pathExtension.lowercased()) { AppDelegate.open(url) } else { open(url) }
    }

    // MARK: Back and forward

    /// A place to come back to: a document, and where in it.
    private struct Stop {
        let file: URL
        let place: Int
    }
    private var backStops: [Stop] = [], forwardStops: [Stop] = []

    private var here: Stop? {
        (document as? NSDocument)?.fileURL.map { Stop(file: $0, place: markdownView.place) }
    }

    /// Before a link is followed or a heading chosen: the place left goes on the back list.
    private func leaving() {
        guard let here else { return }
        backStops.append(here)
        if backStops.count > 100 { backStops.removeFirst() }
        forwardStops.removeAll()
    }

    private func follow(_ file: URL, to fragment: String?) {
        leavingDocument(for: file) { [weak self] in
            self?.leaving()
            self?.show(file) { [weak self] sameDocument in
                if let fragment { self?.markdownView.jump(to: fragment) } else if sameDocument { self?.markdownView.go(to: 0) }
            }
        }
    }

    @objc func goBack(_ sender: Any?) {
        guard let next = backStops.last else { return NSSound.beep() }
        leavingDocument(for: next.file) { [weak self] in
            guard let self, let stop = backStops.popLast() else { return }
            if let here { forwardStops.append(here) }
            show(stop.file) { [weak self] _ in self?.markdownView.go(to: stop.place) }
        }
    }

    @objc func goForward(_ sender: Any?) {
        guard let next = forwardStops.last else { return NSSound.beep() }
        leavingDocument(for: next.file) { [weak self] in
            guard let self, let stop = forwardStops.popLast() else { return }
            if let here { backStops.append(here) }
            show(stop.file) { [weak self] _ in self?.markdownView.go(to: stop.place) }
        }
    }

    // A mouse's back and forward buttons do the same.
    override func otherMouseDown(with event: NSEvent) {
        switch event.buttonNumber {
        case 3: goBack(nil)
        case 4: goForward(nil)
        default: super.otherMouseDown(with: event)
        }
    }

    /// Shows a document in this window: the one on show, or another, opened if need be, which
    /// the window then belongs to. The document it leaves closes if no other window shows it.
    /// `then` runs once it shows, told whether it was already on show.
    private func show(_ file: URL, then: @escaping (Bool) -> Void) {
        if (document as? NSDocument)?.fileURL?.standardizedFileURL == file.standardizedFileURL { return then(true) }
        NSDocumentController.shared.openDocument(withContentsOf: file, display: false) { [weak self] opened, _, error in
            guard let self else { return }
            guard let opened = opened as? MarkdownDocument else {
                if let error { NSApp.presentError(error) }
                return
            }
            rememberPlace()
            let previous = document as? NSDocument
            previous?.removeWindowController(self)
            opened.addWindowController(self)
            if let previous, previous.windowControllers.isEmpty { previous.close() }
            then(false)
        }
    }

    // MARK: Zoom

    @objc func zoomPageIn(_ sender: Any?) { setPageZoom(markdownView.magnification * 1.1) }
    @objc func zoomPageOut(_ sender: Any?) { setPageZoom(markdownView.magnification / 1.1) }
    @objc func resetPageZoom(_ sender: Any?) { setPageZoom(1) }

    private func setPageZoom(_ zoom: CGFloat) {
        markdownView.magnification = min(max(zoom, 0.5), 3)
        UserDefaults.standard.set(Double(markdownView.magnification), forKey: "pageZoom")
    }

    // MARK: Find

    // Each text view brings its own find bar; these only tell the one in use what to do: the
    // editor's while it has the focus, otherwise the page's.
    @objc func showFindBar(_ sender: Any?) { find(.showFindInterface) }
    @objc func findNext(_ sender: Any?) { find(.nextMatch) }
    @objc func findPrevious(_ sender: Any?) { find(.previousMatch) }

    /// Replacing is the editor's: it opens if need be.
    @objc func showReplaceBar(_ sender: Any?) {
        showEditor()
        window?.makeFirstResponder(editor.textView)
        find(.showReplaceInterface)
    }

    private func find(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        let editing = !editorItem.isCollapsed && (window?.firstResponder as? NSView)?.isDescendant(of: editor) == true
        (editing ? editor.textView : markdownView.textView).performTextFinderAction(item)
    }

    // MARK: Smoke tests

    /// For scripted checks. MARKVIEW_SNAPSHOT=<png path> writes an image of the
    /// rendered page, prints the open documents and quits, after
    /// MARKVIEW_SNAPSHOT_DELAY seconds (default 0.5). Optional extras, applied first:
    ///   MARKVIEW_CHROME_SNAPSHOT=<png path>  also capture the whole window
    ///   MARKVIEW_APPEARANCE=light|dark       override the system appearance
    ///   MARKVIEW_WIDTH=<points>              make the page this wide, leaving the saved window size alone
    ///   MARKVIEW_FIND=<text>                 run a find
    ///   MARKVIEW_ANCHOR=<heading slug>       jump to a heading
    ///   MARKVIEW_LINK=<text>                 follow the first link whose target contains the text
    ///   MARKVIEW_EDITOR=1                    open the editor beside the page
    ///   MARKVIEW_TYPE=<text>                 type the text at the start of the document, in the editor
    ///   MARKVIEW_PDF=<pdf path>              also export the page as a PDF
    ///   MARKVIEW_SETTINGS=<png path>         also capture the Settings window
    ///   MARKVIEW_SETTINGS_PANE=<n>           on its nth pane, counting from 0
    ///   MARKVIEW_KEEP_PLACE=1                open at the place last read and remember it, as the app does
    ///   MARKVIEW_OUTLINE=1                   show the outline beside the page
    private func runSmokeTestHooks() {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["MARKVIEW_SNAPSHOT"] else { return }
        let delay = environment["MARKVIEW_SNAPSHOT_DELAY"].flatMap(Double.init) ?? 0.5
        if let appearance = environment["MARKVIEW_APPEARANCE"] {
            NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        }
        if let width = environment["MARKVIEW_WIDTH"].flatMap(Double.init), let window {
            windowFrameAutosaveName = ""
            window.setContentSize(NSSize(width: width, height: window.contentLayoutRect.height))
        }
        if environment["MARKVIEW_EDITOR"] != nil || environment["MARKVIEW_TYPE"] != nil { showEditor() }
        if let text = environment["MARKVIEW_TYPE"] {
            editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
            editor.textView.insertText(text.replacingOccurrences(of: "\\n", with: "\n"), replacementRange: NSRange(location: 0, length: 0))
        }
        var settings: NSWindow?
        if environment["MARKVIEW_SETTINGS"] != nil {
            NSApp.sendAction(Selector(("showSettings:")), to: nil, from: nil)
            settings = NSApp.windows.first { $0.contentViewController is NSTabViewController }
            let tabs = settings?.contentViewController as? NSTabViewController
            tabs?.selectedTabViewItemIndex = environment["MARKVIEW_SETTINGS_PANE"].flatMap(Int.init) ?? 0
        }
        // The find bar searches for whatever is on the shared find pasteboard, so the
        // previous contents are put back before quitting.
        let findBoard = NSPasteboard(name: .find)
        let previousSearch = findBoard.string(forType: .string)
        if let query = environment["MARKVIEW_FIND"] {
            NSApp.activate(ignoringOtherApps: true)
            findBoard.clearContents()
            findBoard.setString(query, forType: .string)
            showFindBar(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay / 2) { self.findNext(nil) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay / 2) {
            if let anchor = environment["MARKVIEW_ANCHOR"] { self.markdownView.jump(to: anchor) }
            if let text = environment["MARKVIEW_LINK"], let storage = self.markdownView.textView.textStorage {
                storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) { link, range, stop in
                    guard let link = link as? URL, link.absoluteString.contains(text) else { return }
                    _ = self.markdownView.textView(self.markdownView.textView, clickedOnLink: link, at: range.location)
                    stop.pointee = true
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // At twice the size whatever display the window is on, so that snapshots compare.
            func write(_ view: NSView?, to path: String?) {
                guard let view, let path, var rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                let width = Int(view.bounds.width * 2), height = Int(view.bounds.height * 2)
                if rep.pixelsWide < width, let larger = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                    isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)?.retagging(with: rep.colorSpace) {
                    larger.size = view.bounds.size
                    rep = larger
                }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            write(self.markdownView, to: path)
            write(self.window?.contentView?.superview, to: environment["MARKVIEW_CHROME_SNAPSHOT"])
            write(settings?.contentView?.superview, to: environment["MARKVIEW_SETTINGS"])
            if let pdf = environment["MARKVIEW_PDF"] { self.writePDF(to: URL(fileURLWithPath: pdf)) }
            if environment["MARKVIEW_FIND"] != nil {
                findBoard.clearContents()
                if let previousSearch { findBoard.setString(previousSearch, forType: .string) }
            }
            print("open documents:", NSDocumentController.shared.documents.compactMap { $0.fileURL?.lastPathComponent })
            // Closed before quitting so that a test run leaves no windows for the next launch to restore.
            NSDocumentController.shared.documents.forEach { $0.close() }
            NSApp.terminate(nil)
        }
    }
}

extension ViewerWindowController: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { preview == nil ? 0 : 1 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! { preview?.file as NSURL? }

    // The panel zooms out of the picture on the page, and back into it.
    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: (any QLPreviewItem)!) -> NSRect { preview?.frame ?? .zero }
}

private extension CGFloat {
    /// A setting read from the defaults, which give 0 for one never set.
    func clamped(to range: ClosedRange<CGFloat>, default fallback: CGFloat) -> CGFloat {
        self == 0 ? fallback : Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
