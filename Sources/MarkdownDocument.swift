import Cocoa

@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    /// The text, until an editor first shows it; from then on `source` holds it.
    private var text = ""
    /// The text as the editor shows and changes it, shared by every window showing the document.
    /// Made only when an editor first shows the document, so viewing costs nothing more.
    private(set) var source: NSTextStorage?
    private var highlighter: SourceHighlighter?
    /// How the file is written, so that saving writes it back the same way.
    private var format = TextFormat()
    /// The text as last read from the file or written to it. A change on disk that matches it is a
    /// save of our own, or no change at all.
    private var onDisk: String?
    /// Whether the file changed on disk under unsaved edits, until the reader chooses which to keep.
    private(set) var changedOnDisk = false
    private var watcher: FileWatcher?
    /// The folder a new document was made from: its pictures and links are looked for there until
    /// it is saved, and saving suggests it.
    var draftFolder: URL?

    // Edits are kept elsewhere until saved (see AppDelegate), never written to the file unasked.
    override class var autosavesInPlace: Bool { false }
    override var shouldRunSavePanelWithAccessoryView: Bool { false }

    var markdown: String { source?.string ?? text }
    /// The length of the text, in UTF-16 units, without copying it.
    var length: Int { source?.length ?? (text as NSString).length }

    private var viewers: [ViewerWindowController] { windowControllers.compactMap { $0 as? ViewerWindowController } }

    // Also fires when the file is renamed or moved while open, and when a new document is first saved.
    override var fileURL: URL? {
        didSet {
            guard fileURL != oldValue else { return }
            DispatchQueue.main.async { [weak self] in
                self?.watchFile()
                self?.viewers.forEach { $0.documentMoved() }
            }
        }
    }

    // MARK: Reading and writing

    override func read(from data: Data, ofType typeName: String) throws {
        let (text, format) = TextFormat.decode(data)
        self.format = format
        onDisk = text
        setText(text)
    }

    // The text is the file's again, whatever was said about it changing on disk.
    override func revert(toContentsOf url: URL, ofType typeName: String) throws {
        try super.revert(toContentsOf: url, ofType: typeName)
        resolveChangeOnDisk()
    }

    override func data(ofType typeName: String) throws -> Data {
        // Only a copy kept for safety gets here with characters the file's encoding lacks (see save).
        format.encode(markdown) ?? TextFormat().encode(markdown)!
    }

    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping ((any Error)?) -> Void) {
        if saveOperation == .autosaveElsewhereOperation {
            return write(to: keptAside(url), ofType: typeName, for: saveOperation, completionHandler: completionHandler)
        }
        let savesFile = saveOperation == .saveOperation || saveOperation == .saveAsOperation
        guard savesFile, format.encode(markdown) == nil else {
            return write(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)
        }
        // A file read as Latin-1, say, that now holds characters Latin-1 lacks.
        ask("“\(displayName ?? "")” can’t be saved as \(String.localizedName(of: format.encoding)).",
            "Some of its characters aren’t in that encoding. Save it as UTF-8 instead?",
            button: "Save as UTF-8", completionHandler: completionHandler) { [self] in
            format.encoding = .utf8
            write(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)
        }
    }

    /// Asks before saving, on the document's window: `then` runs if the reader goes ahead.
    private func ask(_ message: String, _ detail: String, button: String,
                     completionHandler: @escaping ((any Error)?) -> Void, then: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        let answer = { (response: NSApplication.ModalResponse) in
            guard response == .alertFirstButtonReturn else { return completionHandler(CocoaError(.userCancelled)) }
            then()
        }
        if let window = windowForSheet { alert.beginSheetModal(for: window, completionHandler: answer) } else { answer(alert.runModal()) }
    }

    /// Saves, and once the file holds the text, remembers it as what is on disk.
    private func write(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping ((any Error)?) -> Void) {
        let written = markdown
        let savesFile = saveOperation == .saveOperation || saveOperation == .saveAsOperation
        super.save(to: url, ofType: typeName, for: saveOperation) { error in
            if error == nil, savesFile {
                self.onDisk = written
                self.resolveChangeOnDisk()
            }
            completionHandler(error)
        }
    }

    /// Where unsaved edits are kept: the system's autosave folder. AppKit would keep those of a
    /// document that has a file beside it, as “Name (Autosaved).md”, where they would turn up in
    /// the folder, and in git.
    private func keptAside(_ url: URL) -> URL {
        let files = FileManager.default
        guard let folder = try? files.url(for: .autosavedInformationDirectory, in: .userDomainMask, appropriateFor: nil, create: true),
              url.deletingLastPathComponent().resolvingSymlinksInPath() != folder.resolvingSymlinksInPath() else { return url }
        let name = url.deletingPathExtension().lastPathComponent
        var aside = folder.appendingPathComponent(url.lastPathComponent), number = 2
        while files.fileExists(atPath: aside.path) {
            aside = folder.appendingPathComponent("\(name) \(number)").appendingPathExtension(url.pathExtension)
            number += 1
        }
        return aside
    }

    // A new document's file is Markdown, whether or not the system knows the type's extension.
    override func fileNameExtension(forType typeName: String, saveOperation: NSDocument.SaveOperationType) -> String? {
        typeName == "net.daringfireball.markdown" ? "md" : super.fileNameExtension(forType: typeName, saveOperation: saveOperation)
    }

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        if fileURL == nil, let draftFolder { savePanel.directoryURL = draftFolder }
        return super.prepareSavePanel(savePanel)
    }

    // MARK: Windows

    override func makeWindowControllers() {
        let viewer = ViewerWindowController()
        addWindowController(viewer)
        // Documents open as pages to read, except a new one, which has nothing to show but what is
        // typed, and one reopened with edits it had not saved.
        if fileURL == nil || isDocumentEdited { viewer.showEditor() }
    }

    override func close() {
        watcher = nil
        super.close()
        // Nothing left to show: quit rather than linger in the Dock.
        DispatchQueue.main.async {
            if NSDocumentController.shared.documents.isEmpty { NSApp.terminate(nil) }
        }
    }

    // MARK: The text

    /// The text for an editor to show, coloured in the theme.
    func editableSource(theme: Theme) -> NSTextStorage {
        if let source, let highlighter {
            highlighter.activate(theme: theme)
            return source
        }
        let storage = NSTextStorage(string: text)
        text = ""
        let highlighter = SourceHighlighter(storage: storage, theme: theme)
        highlighter.onTextChange = { [weak self] in self?.viewers.forEach { $0.textChanged() } }
        highlighter.activate(theme: theme)
        source = storage
        self.highlighter = highlighter
        return storage
    }

    /// The text typed with, before the highlighter colours it.
    var typingAttributes: [NSAttributedString.Key: Any] { highlighter?.typingAttributes ?? [:] }

    func apply(_ theme: Theme) { highlighter?.activate(theme: theme) }

    /// Colours the lines just edited, once the edit is done (see SourceHighlighter.colourEdits).
    func colourEdits() { highlighter?.colourEdits() }

    /// Puts new text in place of the old, as when the file is read again. In an editor only the part
    /// that differs is replaced, so the selection and the place in the text stay where they were.
    private func setText(_ new: String) {
        guard let source else {
            text = new
            return viewers.forEach { $0.render() }
        }
        let old = source.string as NSString, replacement = new as NSString
        let shorter = min(old.length, replacement.length)
        var prefix = 0
        while prefix < shorter, old.character(at: prefix) == replacement.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < shorter - prefix, old.character(at: old.length - 1 - suffix) == replacement.character(at: replacement.length - 1 - suffix) {
            suffix += 1
        }
        let changed = NSRange(location: prefix, length: old.length - prefix - suffix)
        source.replaceCharacters(in: changed, with: replacement.substring(with: NSRange(location: prefix, length: replacement.length - prefix - suffix)))
        colourEdits()
        // The edits the undo list holds were made to the text replaced.
        undoManager?.removeAllActions()
    }

    // MARK: Changes on disk

    private func watchFile() {
        // A document reopened with edits it had not saved was read from where they were kept; what is
        // on disk is read here, to tell later changes to the file from it.
        if isDocumentEdited, let url = fileURL, let data = try? Data(contentsOf: url) { onDisk = TextFormat.decode(data).text }
        watcher = fileURL.map { url in
            FileWatcher(url: url) { [weak self] in self?.reloadFromDisk() }
        }
    }

    private func reloadFromDisk() {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return }
        let (text, format) = TextFormat.decode(data)
        guard text != onDisk else { return }
        onDisk = text
        // Saving next overwrites what is on disk now without asking again.
        fileModificationDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard !isDocumentEdited else {
            // Unsaved edits, and a file that has moved on without them: the reader chooses.
            guard text != markdown else { return updateChangeCount(.changeCleared) }
            changedOnDisk = true
            return viewers.forEach { $0.reflectChangeOnDisk() }
        }
        self.format = format
        setText(text)
    }

    /// Throws the edits away for what is on disk now.
    func reloadDiscardingEdits() {
        guard let url = fileURL, let type = fileType else { return }
        do {
            try revert(toContentsOf: url, ofType: type)
        } catch {
            presentError(error)
        }
    }

    /// Keeps the edits; saving them replaces what is on disk.
    func keepEdits() { resolveChangeOnDisk() }

    private func resolveChangeOnDisk() {
        guard changedOnDisk else { return }
        changedOnDisk = false
        viewers.forEach { $0.reflectChangeOnDisk() }
    }
}

/// How a text file is written: its encoding, whether it starts with a byte order mark, and its line
/// endings. The text in between always has plain line feeds, whatever the file has.
struct TextFormat {
    var encoding: String.Encoding = .utf8
    var byteOrderMark = false
    var lineEnding = "\n"

    /// A byte order mark says UTF-16 or UTF-8; without one, a file is UTF-8 if it reads as UTF-8,
    /// else it is in one of the Western encodings of one byte a character. Latin-1 reads any bytes,
    /// so whatever a file holds, the text that is not edited is written back as it was.
    static func decode(_ data: Data) -> (text: String, format: TextFormat) {
        var format = TextFormat()
        var text: String
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]), let utf16 = String(data: data, encoding: .utf16) {
            text = utf16
            format.encoding = .utf16
        } else if let utf8 = String(data: data, encoding: .utf8) {
            text = utf8
            format.byteOrderMark = data.starts(with: [0xEF, 0xBB, 0xBF])
        } else {
            var decoded: NSString?
            let detected = NSString.stringEncoding(
                for: data, encodingOptions: [.suggestedEncodingsKey: [NSWindowsCP1252StringEncoding, NSMacOSRomanStringEncoding, NSISOLatin1StringEncoding],
                                             .useOnlySuggestedEncodingsKey: true, .allowLossyKey: false],
                convertedString: &decoded, usedLossyConversion: nil)
            if let decoded, detected != 0 {
                text = decoded as String
                format.encoding = String.Encoding(rawValue: detected)
            } else {
                text = String(data: data, encoding: .isoLatin1) ?? ""
                format.encoding = .isoLatin1
            }
        }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        if text.contains("\r\n") {
            format.lineEnding = "\r\n"
            text = text.replacingOccurrences(of: "\r\n", with: "\n")
        }
        return (text, format)
    }

    /// The text as the file holds it, or nil if the encoding lacks some of its characters.
    func encode(_ text: String) -> Data? {
        var text = lineEnding == "\n" ? text : text.replacingOccurrences(of: "\n", with: lineEnding)
        if byteOrderMark { text = "\u{FEFF}" + text }
        return text.data(using: encoding, allowLossyConversion: false)
    }
}
