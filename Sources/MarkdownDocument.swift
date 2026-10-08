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
        markdown = Self.text(of: data)
    }

    /// UTF-8 first; a file in another encoding is detected rather than shown with ? marks, and
    /// a byte order mark is dropped. The same when the file is read again after a change.
    private static func text(of data: Data) -> String {
        var decoded: NSString?
        let suggested = [NSUTF8StringEncoding, NSUTF16StringEncoding, NSISOLatin1StringEncoding, NSWindowsCP1252StringEncoding, NSMacOSRomanStringEncoding]
        _ = NSString.stringEncoding(for: data, encodingOptions: [.suggestedEncodingsKey: suggested, .useOnlySuggestedEncodingsKey: true],
                                    convertedString: &decoded, usedLossyConversion: nil)
        var text = (decoded as String?) ?? String(decoding: data, as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return text
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
        let text = Self.text(of: data)
        guard text != markdown else { return }
        markdown = text
        for case let viewer as ViewerWindowController in windowControllers { viewer.render() }
    }
}
