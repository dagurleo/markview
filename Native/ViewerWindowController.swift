import Cocoa
import Quartz
import UniformTypeIdentifiers

final class ViewerWindowController: NSWindowController, DocumentOutline, DocumentActions {
    private let markdownView: MarkdownView
    private let outline = OutlineSidebar()
    private let outlineItem: NSSplitViewItem
    private let divider = OutlineSplitView()
    /// A heading chosen in the outline stays marked while the page stays where it went: near
    /// the end of a document the page cannot bring it to the top.
    private var chosen: (index: Int, top: CGFloat)?
    /// Scripted checks show no outline, unless asked, and leave its setting alone.
    private let scripted = ProcessInfo.processInfo.environment["MARKVIEW_SNAPSHOT"] != nil
    private var didRunSmokeTestHooks = false
    private var showingSource = false
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
        outlineItem = NSSplitViewItem(viewController: outline)
        outlineItem.canCollapse = true
        outlineItem.minimumThickness = 150
        outlineItem.maximumThickness = 400
        outlineItem.holdingPriority = NSLayoutConstraint.Priority(260)
        let page = NSViewController()
        page.view = markdownView
        let pageItem = NSSplitViewItem(viewController: page)
        pageItem.minimumThickness = 280
        split.addSplitViewItem(outlineItem)
        split.addSplitViewItem(pageItem)
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
        outline.onSelect = { [weak self] heading in
            guard let self, let index = headings.firstIndex(where: { $0.anchor == heading.anchor }) else { return }
            leaving()
            show(headingAt: index)
            self.window?.makeFirstResponder(markdownView.textView)
        }
        windowFrameAutosaveName = "Viewer"
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            self?.rememberPlace()
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.rememberPlace()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var document: AnyObject? {
        didSet {
            render()
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
        outline.apply(theme)
        divider.color = theme.border
        render()
    }

    // MARK: Outline

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
        guard let document = document as? MarkdownDocument, let file = document.fileURL else { return }
        if showingSource {
            markdownView.showSource(document.markdown)
        } else {
            markdownView.show(document.markdown, baseURL: file)
        }
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

    /// Not while the source shows, whose characters are not the page's, nor while a large
    /// document is still on its way to the place it opens at.
    private func rememberPlace() {
        guard keepsPlace, !showingSource, !markdownView.rendering, let file = (document as? NSDocument)?.fileURL else { return }
        Places.remember(markdownView.place, of: file)
    }

    // MARK: Source

    @objc func toggleSource(_ sender: Any?) {
        showingSource.toggle()
        render()
    }

    @objc func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleSource(_:)) { item.state = showingSource ? .on : .off }
        if item.action == #selector(toggleOutline(_:)) { item.title = outlineItem.isCollapsed ? "Show Outline" : "Hide Outline" }
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

    /// A file dropped on the page opens in a window of its own, as one dropped on the Dock icon does.
    private func openDropped(_ url: URL) {
        if url.isFileURL, Links.markdownExtensions.contains(url.pathExtension.lowercased()) { AppDelegate.open(url) } else { open(url) }
    }

    // MARK: Back and forward

    /// A place to come back to: a document, and where in it.
    private struct Stop {
        let file: URL
        let place: Int
    }
    private var backStops: [Stop] = [], forwardStops: [Stop] = []

    private var here: Stop? {
        (document as? NSDocument)?.fileURL.map { Stop(file: $0, place: showingSource ? 0 : markdownView.place) }
    }

    /// Before a link is followed or a heading chosen: the place left goes on the back list.
    private func leaving() {
        guard let here else { return }
        backStops.append(here)
        if backStops.count > 100 { backStops.removeFirst() }
        forwardStops.removeAll()
    }

    private func follow(_ file: URL, to fragment: String?) {
        leaving()
        show(file) { [weak self] sameDocument in
            if let fragment { self?.markdownView.jump(to: fragment) } else if sameDocument { self?.markdownView.go(to: 0) }
        }
    }

    @objc func goBack(_ sender: Any?) {
        guard let stop = backStops.popLast() else { return NSSound.beep() }
        if let here { forwardStops.append(here) }
        show(stop.file) { [weak self] _ in self?.markdownView.go(to: stop.place) }
    }

    @objc func goForward(_ sender: Any?) {
        guard let stop = forwardStops.popLast() else { return NSSound.beep() }
        if let here { backStops.append(here) }
        show(stop.file) { [weak self] _ in self?.markdownView.go(to: stop.place) }
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
            showingSource = false
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

    // The text view brings its own find bar; these only tell it what to do.
    @objc func showFindBar(_ sender: Any?) { find(.showFindInterface) }
    @objc func findNext(_ sender: Any?) { find(.nextMatch) }
    @objc func findPrevious(_ sender: Any?) { find(.previousMatch) }

    private func find(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        markdownView.textView.performTextFinderAction(item)
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
    ///   MARKVIEW_SOURCE=1                    show the source instead of the page
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
        if environment["MARKVIEW_SOURCE"] != nil { toggleSource(nil) }
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
