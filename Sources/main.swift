import Cocoa
import Sparkle
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private static let markdown = UTType("net.daringfireball.markdown")

    /// Sparkle reads the appcast attached to the newest release (SUFeedURL in Info.plist), and on
    /// the second launch asks whether to look for updates by itself. Scripted checks leave it
    /// stopped, so that a test run neither asks nor looks.
    private let updater = SPUStandardUpdaterController(
        startingUpdater: ProcessInfo.processInfo.environment["MARKVIEW_SNAPSHOT"] == nil, updaterDelegate: nil, userDriverDelegate: nil)
    private lazy var settingsWindow = SettingsWindowController(updater: updater.updater)
    /// What the open windows show, so that only a change of settings shows them again.
    private var shownTheme = Settings.theme
    private var shownEditorSettings = EditorSettings.current
    private var shownAppearance: String?
    private var pendingSettings: DispatchWorkItem?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        // Unsaved edits are kept in the system's autosave folder every few seconds, and come back
        // after a crash; a document's own file is written only when it is saved.
        NSDocumentController.shared.autosavingDelay = 5
        shownAppearance = Settings.defaults.string(forKey: Settings.Key.appearance)
        NSApp.appearance = Settings.appearance
        NotificationCenter.default.addObserver(self, selector: #selector(defaultsChanged), name: UserDefaults.didChangeNotification, object: nil)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // Launching without a file asks for one, rather than starting a new document (File > New).
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        let controller = NSDocumentController.shared
        controller.beginOpenPanel { urls in
            guard let urls, !urls.isEmpty else {
                // Unless a new document was started meanwhile.
                if controller.documents.isEmpty { NSApp.terminate(nil) }
                return
            }
            urls.forEach(Self.open)
        }
        return true
    }

    /// Opens a file, and goes to the heading its URL's fragment names, if any.
    static func open(_ url: URL) {
        let fragment = url.fragment
        let file = URL(fileURLWithPath: url.path)
        NSDocumentController.shared.openDocument(withContentsOf: file, display: true) { document, _, error in
            if let error { NSApp.presentError(error) }
            if let fragment, let controller = document?.windowControllers.first as? ViewerWindowController {
                controller.open(fragment: fragment)
            }
        }
    }

    // MARK: Settings

    @objc private func showSettings(_ sender: Any?) {
        settingsWindow.showWindow(sender)
    }

    /// Any default changing, window frames included, lands here. A slider sends a change at every
    /// step, so the windows are shown again only once the changes pause.
    @objc private func defaultsChanged(_ notification: Notification) {
        DispatchQueue.main.async { [self] in
            pendingSettings?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.showSettingsChanges() }
            pendingSettings = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }
    }

    private func showSettingsChanges() {
        let appearance = Settings.defaults.string(forKey: Settings.Key.appearance)
        if appearance != shownAppearance {
            shownAppearance = appearance
            NSApp.appearance = Settings.appearance
        }
        let editorSettings = EditorSettings.current
        if editorSettings != shownEditorSettings {
            shownEditorSettings = editorSettings
            for controller in viewers { controller.apply(editorSettings) }
        }
        let theme = Settings.theme
        guard theme != shownTheme else { return }
        shownTheme = theme
        for controller in viewers { controller.show(theme) }
    }

    private var viewers: [ViewerWindowController] {
        NSDocumentController.shared.documents.flatMap { $0.windowControllers.compactMap { $0 as? ViewerWindowController } }
    }

    /// View > Show Line Numbers, which Settings > Editor offers too.
    @objc private func toggleLineNumbers(_ sender: Any?) {
        Settings.defaults.set(!EditorSettings.current.lineNumbers, forKey: EditorSettings.Key.lineNumbers)
    }

    // MARK: Menu

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let menu = NSMenu(title: title)
            main.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = menu
            return menu
        }

        let app = submenu("Markview")
        app.add("About Markview", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        app.add("Check for Updates…", #selector(SPUStandardUpdaterController.checkForUpdates(_:))).target = updater
        app.addItem(.separator())
        app.add("Settings…", #selector(showSettings(_:)), key: ",").target = self
        app.addItem(.separator())
        app.add("Make Default Markdown Viewer", #selector(makeDefaultViewer(_:))).target = self
        app.addItem(.separator())
        app.add("Hide Markview", #selector(NSApplication.hide(_:)), key: "h")
        app.add("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option])
        app.add("Show All", #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator())
        app.add("Quit Markview", #selector(NSApplication.terminate(_:)), key: "q")

        let file = submenu("File")
        file.add("New", #selector(NSDocumentController.newDocument(_:)), key: "n")
        file.add("Open…", #selector(NSDocumentController.openDocument(_:)), key: "o")
        let recent = NSMenu(title: "Open Recent")
        recent.delegate = self
        file.add("Open Recent", nil).submenu = recent
        file.addItem(.separator())
        let openWith = NSMenu(title: "Open With")
        openWith.delegate = self
        file.add("Open With", nil).submenu = openWith
        file.add("Reveal in Finder", #selector(revealInFinder(_:)), key: "r", modifiers: [.command, .shift]).target = self
        file.add("Copy Path", #selector(copyPath(_:)), key: "c", modifiers: [.command, .option]).target = self
        file.addItem(.separator())
        file.add("Close", #selector(NSWindow.performClose(_:)), key: "w")
        file.add("Save", #selector(NSDocument.save(_:)), key: "s")
        file.add("Save As…", #selector(NSDocument.saveAs(_:)), key: "s", modifiers: [.command, .shift])
        file.add("Revert to Saved", #selector(NSDocument.revertToSaved(_:)))
        file.addItem(.separator())
        // Printing and the editor belong to the document window.
        file.add("Export as PDF…", #selector(DocumentActions.exportPDF(_:)), key: "e", modifiers: [.command, .shift])
        file.add("Print…", #selector(DocumentActions.printDocument(_:)), key: "p")

        let edit = submenu("Edit")
        edit.add("Undo", Selector(("undo:")), key: "z")
        edit.add("Redo", Selector(("redo:")), key: "z", modifiers: [.command, .shift])
        edit.addItem(.separator())
        edit.add("Cut", #selector(NSText.cut(_:)), key: "x")
        edit.add("Copy", #selector(NSText.copy(_:)), key: "c")
        edit.add("Paste", #selector(NSText.paste(_:)), key: "v")
        edit.add("Delete", #selector(NSText.delete(_:)))
        edit.add("Select All", #selector(NSText.selectAll(_:)), key: "a")
        edit.addItem(.separator())
        edit.add("Find…", #selector(ViewerWindowController.showFindBar(_:)), key: "f")
        edit.add("Find and Replace…", #selector(ViewerWindowController.showReplaceBar(_:)), key: "f", modifiers: [.command, .option])
        edit.add("Find Next", #selector(ViewerWindowController.findNext(_:)), key: "g")
        edit.add("Find Previous", #selector(ViewerWindowController.findPrevious(_:)), key: "g", modifiers: [.command, .shift])
        edit.addItem(.separator())
        let spelling = NSMenu(title: "Spelling and Grammar")
        spelling.add("Show Spelling and Grammar", #selector(NSText.showGuessPanel(_:)), key: ":")
        spelling.add("Check Document Now", #selector(NSText.checkSpelling(_:)), key: ";")
        spelling.addItem(.separator())
        spelling.add("Check Spelling While Typing", #selector(NSTextView.toggleContinuousSpellChecking(_:)))
        spelling.add("Check Grammar With Spelling", #selector(NSTextView.toggleGrammarChecking(_:)))
        spelling.add("Correct Spelling Automatically", #selector(NSTextView.toggleAutomaticSpellingCorrection(_:)))
        edit.add("Spelling and Grammar", nil).submenu = spelling
        let substitutions = NSMenu(title: "Substitutions")
        substitutions.add("Show Substitutions", #selector(NSTextView.orderFrontSubstitutionsPanel(_:)))
        substitutions.addItem(.separator())
        substitutions.add("Smart Quotes", #selector(NSTextView.toggleAutomaticQuoteSubstitution(_:)))
        substitutions.add("Smart Dashes", #selector(NSTextView.toggleAutomaticDashSubstitution(_:)))
        substitutions.add("Text Replacement", #selector(NSTextView.toggleAutomaticTextReplacement(_:)))
        edit.add("Substitutions", nil).submenu = substitutions

        // The editor's; enabled while it has the focus.
        let format = submenu("Format")
        format.add("Bold", #selector(SourceTextView.toggleBold(_:)), key: "b")
        format.add("Italic", #selector(SourceTextView.toggleItalic(_:)), key: "i")
        format.add("Strikethrough", #selector(SourceTextView.toggleStrikethrough(_:)), key: "x", modifiers: [.command, .shift])
        format.add("Code", #selector(SourceTextView.toggleCode(_:)), key: "e")
        format.addItem(.separator())
        format.add("Link", #selector(SourceTextView.insertLink(_:)), key: "k")

        let view = submenu("View")
        view.add("Show Sidebar", #selector(ViewerWindowController.toggleOutline(_:)), key: "s", modifiers: [.command, .control])
        view.addItem(.separator())
        view.add("Actual Size", #selector(ViewerWindowController.resetPageZoom(_:)), key: "0")
        view.add("Zoom In", #selector(ViewerWindowController.zoomPageIn(_:)), key: "+")
        view.add("Zoom Out", #selector(ViewerWindowController.zoomPageOut(_:)), key: "-")
        view.addItem(.separator())
        view.add("Show Editor", #selector(DocumentActions.toggleEditor(_:)), key: "u")
        view.add("Show Line Numbers", #selector(toggleLineNumbers(_:)), key: "l", modifiers: [.command, .option]).target = self
        view.addItem(.separator())
        view.add("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), key: "f", modifiers: [.command, .control])

        let go = submenu("Go")
        go.delegate = self
        addHeadingSteps(to: go)

        let window = submenu("Window")
        window.add("Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m")
        window.add("Zoom", #selector(NSWindow.performZoom(_:)))
        window.addItem(.separator())
        window.add("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
        NSApp.windowsMenu = window

        return main
    }

    /// The front document window, even while another app is active (menus can be read then too).
    private var frontWindow: NSWindow? { NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.orderedWindows.first { $0.windowController != nil } }
    private var currentFile: URL? { (frontWindow?.windowController?.document as? NSDocument)?.fileURL }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        switch menu.title {
        case "Open Recent":
            for url in NSDocumentController.shared.recentDocumentURLs {
                let item = menu.add(url.lastPathComponent, #selector(openRecent(_:)))
                item.target = self
                item.representedObject = url
                item.toolTip = url.path
            }
            menu.addItem(.separator())
            menu.add("Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:)))
        case "Open With":
            guard let file = currentFile else { return }
            var seen = Set<String>()
            let apps = NSWorkspace.shared.urlsForApplications(toOpen: file)
                .filter { Bundle(url: $0)?.bundleIdentifier != Bundle.main.bundleIdentifier && seen.insert($0.lastPathComponent).inserted }
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            for app in apps {
                let item = menu.add(app.deletingPathExtension().lastPathComponent, #selector(openWith(_:)))
                item.target = self
                item.representedObject = app
                let icon = NSWorkspace.shared.icon(forFile: app.path)
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
            if apps.isEmpty { menu.add("No Applications", nil) }
        case "Go":
            addHeadingSteps(to: menu)
            let headings = (frontWindow?.windowController as? DocumentOutline)?.headings ?? []
            for heading in headings {
                let item = menu.add(heading.title, #selector(goToHeading(_:)))
                item.target = self
                item.representedObject = heading.anchor
                item.indentationLevel = max(0, heading.level - 1)
            }
            if headings.isEmpty { menu.add("No Headings", nil) }
        default:
            break
        }
    }

    /// Back, Forward, Next and Previous Heading head the Go menu, above the headings themselves.
    /// They are there from the start, so their keys work before the menu is first opened.
    private func addHeadingSteps(to menu: NSMenu) {
        func arrow(_ key: Int) -> String { String(Character(Unicode.Scalar(UInt32(key))!)) }
        menu.add("Back", #selector(ViewerWindowController.goBack(_:)), key: "[")
        menu.add("Forward", #selector(ViewerWindowController.goForward(_:)), key: "]")
        menu.addItem(.separator())
        menu.add("Next Heading", #selector(ViewerWindowController.goToNextHeading(_:)), key: arrow(NSDownArrowFunctionKey), modifiers: [.command, .option])
        menu.add("Previous Heading", #selector(ViewerWindowController.goToPreviousHeading(_:)), key: arrow(NSUpArrowFunctionKey), modifiers: [.command, .option])
        menu.addItem(.separator())
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { Self.open(url) }
    }

    @objc private func openWith(_ sender: NSMenuItem) {
        guard let file = currentFile, let app = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open([file], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func goToHeading(_ sender: NSMenuItem) {
        guard let anchor = sender.representedObject as? String else { return }
        (frontWindow?.windowController as? DocumentOutline)?.jump(to: anchor)
    }

    @objc private func revealInFinder(_ sender: Any?) {
        if let file = currentFile { NSWorkspace.shared.activateFileViewerSelecting([file]) }
    }

    @objc private func copyPath(_ sender: Any?) {
        guard let file = currentFile else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(file.path, forType: .string)
    }

    // "Make Default Markdown Viewer" is ticked while Markview already is the default.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(revealInFinder(_:)) || item.action == #selector(copyPath(_:)) { return currentFile != nil }
        if item.action == #selector(makeDefaultViewer(_:)) { item.state = Self.isDefaultViewer ? .on : .off }
        if item.action == #selector(toggleLineNumbers(_:)) { item.title = EditorSettings.current.lineNumbers ? "Hide Line Numbers" : "Show Line Numbers" }
        return true
    }

    static var isDefaultViewer: Bool {
        let handler = markdown.flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
        return handler.flatMap { Bundle(url: $0)?.bundleIdentifier } == Bundle.main.bundleIdentifier
    }

    @objc private func makeDefaultViewer(_ sender: Any?) { Self.makeDefaultViewer() }

    /// Calls back on the main thread once the switch is made or refused.
    static func makeDefaultViewer(then done: @escaping () -> Void = {}) {
        guard let markdown else { return }
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: markdown) { error in
            // macOS asks the user to confirm the switch itself; declining is not a failure.
            let underlying = (error as NSError?)?.userInfo[NSUnderlyingErrorKey] as? NSError
            if underlying?.code == userCanceledErr { return DispatchQueue.main.async(execute: done) }
            DispatchQueue.main.async {
                defer { done() }
                let alert = NSAlert()
                alert.messageText = error == nil
                    ? "Markview now opens Markdown files by default."
                    : "Couldn’t change the default app."
                alert.informativeText = error?.localizedDescription ?? ""
                alert.runModal()
            }
        }
    }
}

private extension NSMenu {
    @discardableResult
    func add(_ title: String, _ action: Selector?, key: String = "",
             modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = addItem(withTitle: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}

// The first document controller made is the app's: this one also opens folders.
_ = DocumentController()
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
