import Cocoa

@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    private(set) var markdown = ""
    private var watcher: FileWatcher?

    override class var autosavesInPlace: Bool { false }

    // Also fires when the file is renamed or moved while open.
    override var fileURL: URL? {
        didSet {
            guard fileURL != oldValue else { return }
            DispatchQueue.main.async { [weak self] in self?.watchFile() }
        }
    }

    override func read(from data: Data, ofType typeName: String) throws {
        // UTF-8 first; a file in another encoding is detected rather than shown with ? marks.
        var decoded: NSString?
        let suggested = [NSUTF8StringEncoding, NSUTF16StringEncoding, NSISOLatin1StringEncoding, NSWindowsCP1252StringEncoding, NSMacOSRomanStringEncoding]
        _ = NSString.stringEncoding(for: data, encodingOptions: [.suggestedEncodingsKey: suggested, .useOnlySuggestedEncodingsKey: true],
                                    convertedString: &decoded, usedLossyConversion: nil)
        markdown = (decoded as String?) ?? String(decoding: data, as: UTF8.self)
        if markdown.hasPrefix("\u{FEFF}") { markdown.removeFirst() }
    }

    override func makeWindowControllers() {
        addWindowController(ViewerWindowController())
    }

    override func close() {
        watcher = nil
        super.close()
        // Nothing left to show: quit rather than linger in the Dock.
        DispatchQueue.main.async {
            if NSDocumentController.shared.documents.isEmpty { NSApp.terminate(nil) }
        }
    }

    private func watchFile() {
        watcher = fileURL.map { url in
            FileWatcher(url: url) { [weak self] in self?.reloadFromDisk() }
        }
    }

    private func reloadFromDisk() {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return }
        let text = String(decoding: data, as: UTF8.self)
        guard text != markdown else { return }
        markdown = text
        for case let viewer as ViewerWindowController in windowControllers { viewer.render() }
    }
}
