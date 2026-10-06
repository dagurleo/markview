import Cocoa
import UniformTypeIdentifiers

final class ViewerWindowController: NSWindowController, DocumentOutline, DocumentActions {
    private let markdownView: MarkdownView
    private var didRunSmokeTestHooks = false
    private var showingSource = false

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
        window.backgroundColor = Theme.background
        window.contentView = markdownView
        window.center()
        super.init(window: window)

        let zoom = UserDefaults.standard.double(forKey: "pageZoom")
        markdownView.magnification = zoom > 0 ? zoom : 1
        markdownView.open = { [weak self] url in self?.open(url) }
        windowFrameAutosaveName = "Viewer"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var document: AnyObject? {
        didSet {
            render()
            if document != nil, !didRunSmokeTestHooks {
                didRunSmokeTestHooks = true
                runSmokeTestHooks()
            }
        }
    }

    func render() {
        guard let document = document as? MarkdownDocument, let file = document.fileURL else { return }
        if showingSource {
            markdownView.showSource(document.markdown)
        } else {
            markdownView.show(document.markdown, baseURL: file)
        }
    }

    // MARK: Source

    @objc func toggleSource(_ sender: Any?) {
        showingSource.toggle()
        render()
    }

    @objc func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleSource(_:)) { item.state = showingSource ? .on : .off }
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

    /// The page laid out at the width of the text column, in the light colours whatever
    /// the window shows, so what prints does not depend on the window's size or appearance.
    private func pageForPrinting() -> NSTextView {
        let storage = NSTextStorage(attributedString: markdownView.textView.attributedString())
        let layout = BoxedLayoutManager()
        storage.addLayoutManager(layout)
        let width = Theme.columnWidth + 48
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
    func jump(to anchor: String) { markdownView.jump(to: anchor) }

    private func open(_ url: URL) {
        if url.isFileURL {
            let file = URL(fileURLWithPath: url.path)
            if Links.markdownExtensions.contains(file.pathExtension.lowercased()) {
                var target = URLComponents(url: file, resolvingAgainstBaseURL: false)
                target?.fragment = url.fragment
                AppDelegate.open(target?.url ?? file)
            } else if FileManager.default.fileExists(atPath: file.path) {
                NSWorkspace.shared.activateFileViewerSelecting([file])
            } else {
                NSSound.beep()
            }
        } else if Links.webSchemes.contains(url.scheme ?? "") {
            NSWorkspace.shared.open(url)
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
    ///   MARKVIEW_FIND=<text>                 run a find
    ///   MARKVIEW_ANCHOR=<heading slug>       jump to a heading
    ///   MARKVIEW_LINK=<text>                 follow the first link whose target contains the text
    ///   MARKVIEW_SOURCE=1                    show the source instead of the page
    ///   MARKVIEW_PDF=<pdf path>              also export the page as a PDF
    private func runSmokeTestHooks() {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["MARKVIEW_SNAPSHOT"] else { return }
        let delay = environment["MARKVIEW_SNAPSHOT_DELAY"].flatMap(Double.init) ?? 0.5
        if let appearance = environment["MARKVIEW_APPEARANCE"] {
            NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        }
        if environment["MARKVIEW_SOURCE"] != nil { toggleSource(nil) }
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
            func write(_ view: NSView?, to path: String?) {
                guard let view, let path, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            write(self.markdownView, to: path)
            write(self.window?.contentView?.superview, to: environment["MARKVIEW_CHROME_SNAPSHOT"])
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
