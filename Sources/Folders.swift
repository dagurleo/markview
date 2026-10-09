import Cocoa
import CoreServices

/// A folder's Markdown files as a tree: folders that hold some, at any depth, and the files.
final class FileNode {
    let url: URL
    let name: String
    /// Nil for a file.
    let children: [FileNode]?

    init(url: URL, children: [FileNode]?) {
        self.url = url
        self.children = children
        // A file shows without its extension, as a page title would; the Markdown ones all have one.
        name = children == nil ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
    }

    var isFolder: Bool { children != nil }

    /// The files in order, depth first, as the tree shows them.
    var files: [URL] { children.map { $0.flatMap(\.files) } ?? [url] }
}

/// Folders opened in windows of their own (File > Open…, the markview command, a folder dropped
/// on the Dock icon or a window). A folder's window shows one of its documents, and lists them all.
enum Folders {
    /// Folders not worth looking through for documents.
    private static let skipped: Set = ["node_modules", "Pods", "DerivedData", "build", ".build"]
    /// More than this many files makes a folder too large to list.
    static let limit = 5000

    static func isFolder(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            && (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage != true
    }

    /// The folder's Markdown files as a tree, or nil if it has none. Hidden files are left out,
    /// and so are folders of dependencies and build products. Called off the main thread.
    static func tree(of folder: URL) -> FileNode? {
        var count = 0
        func scan(_ folder: URL, depth: Int) -> FileNode? {
            guard depth < 12, count < limit, let entries = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey], options: [.skipsHiddenFiles]) else { return nil }
            var folders: [FileNode] = [], files: [FileNode] = []
            for entry in entries {
                if isFolder(entry) {
                    if !skipped.contains(entry.lastPathComponent), let node = scan(entry, depth: depth + 1) { folders.append(node) }
                } else if Links.markdownExtensions.contains(entry.pathExtension.lowercased()), count < limit {
                    count += 1
                    files.append(FileNode(url: entry, children: nil))
                }
            }
            guard !folders.isEmpty || !files.isEmpty else { return nil }
            let byName: (FileNode, FileNode) -> Bool = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return FileNode(url: folder, children: folders.sorted(by: byName) + files.sorted(by: byName))
        }
        return scan(folder, depth: 0)
    }

    /// The document a folder opens at: its README, else its index, else the first it lists.
    static func start(of tree: FileNode) -> URL? {
        let top = tree.children?.filter { !$0.isFolder }.map(\.url) ?? []
        for name in ["readme", "index"] {
            if let file = top.first(where: { $0.deletingPathExtension().lastPathComponent.lowercased() == name }) { return file }
        }
        return top.first ?? tree.files.first
    }

    /// Opens a folder in a window of its own, or brings forward the one it is already in.
    static func open(_ folder: URL) {
        let folder = folder.standardizedFileURL
        for window in NSApp.windows {
            if let viewer = window.windowController as? ViewerWindowController, viewer.root == folder {
                return window.makeKeyAndOrderFront(nil)
            }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let tree = tree(of: folder)
            DispatchQueue.main.async {
                guard let tree, let start = start(of: tree) else {
                    let alert = NSAlert()
                    alert.messageText = "There are no Markdown files in “\(folder.lastPathComponent)”."
                    alert.runModal()
                    return
                }
                NSDocumentController.shared.noteNewRecentDocumentURL(folder)
                NSDocumentController.shared.openDocument(withContentsOf: start, display: false) { document, _, error in
                    guard let document = document as? MarkdownDocument else {
                        if let error { NSApp.presentError(error) }
                        return
                    }
                    let viewer = ViewerWindowController()
                    viewer.show(folder: folder, tree: tree)
                    document.addWindowController(viewer)
                    viewer.showWindow(nil)
                }
            }
        }
    }
}

/// Opens folders as well as documents: File > Open… lets a folder be chosen, and a folder opened
/// any way (the Dock icon, the markview command, Open Recent) goes to a window of its own.
final class DocumentController: NSDocumentController {
    override func beginOpenPanel(_ openPanel: NSOpenPanel, forTypes inTypes: [String]?, completionHandler: @escaping (Int) -> Void) {
        openPanel.canChooseDirectories = true
        super.beginOpenPanel(openPanel, forTypes: inTypes, completionHandler: completionHandler)
    }

    override func runModalOpenPanel(_ openPanel: NSOpenPanel, forTypes types: [String]?) -> Int {
        openPanel.canChooseDirectories = true
        return super.runModalOpenPanel(openPanel, forTypes: types)
    }

    /// A new document made from a folder's window is saved there, and finds its pictures there meanwhile.
    override func makeUntitledDocument(ofType typeName: String) throws -> NSDocument {
        let document = try super.makeUntitledDocument(ofType: typeName)
        (document as? MarkdownDocument)?.draftFolder = (NSApp.mainWindow?.windowController as? ViewerWindowController)?.root
        return document
    }

    override func openDocument(withContentsOf url: URL, display displayDocument: Bool,
                               completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void) {
        guard Folders.isFolder(url) else { return super.openDocument(withContentsOf: url, display: displayDocument, completionHandler: completionHandler) }
        Folders.open(url)
        completionHandler(nil, false, nil)
    }
}

/// Calls back, on the main thread, when anything changes in a folder or below it.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let changed: () -> Void

    init(_ folder: URL, changed: @escaping () -> Void) {
        self.changed = changed
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue().changed()
        }
        stream = FSEventStreamCreate(nil, callback, &context, [folder.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                     0.5, FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer))
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
