import Cocoa
import SwiftUI

/// The window shown while no document is open: at launch without a file, once the last window
/// closes, and on a click on the Dock icon. It starts a new document, opens one, or reopens a
/// recent one. Turned off (Settings > General), Markview asks for a file at launch instead, and
/// quits once its last window closes. Closing the start window itself quits.
final class StartWindow: NSWindowController, NSWindowDelegate {
    static let key = "startWindow"
    /// On unless turned off in Settings.
    static var isOn: Bool { Settings.defaults.object(forKey: key) as? Bool ?? true }
    /// How Markview quits, which a test replaces.
    static var quit: () -> Void = { NSApp.terminate(nil) }
    private(set) static var shown: StartWindow?
    private var documentObserver: NSObjectProtocol?

    /// Nothing is left open: shows the start window, or quits.
    static func nothingOpen() {
        guard NSDocumentController.shared.documents.isEmpty else { return }
        // A scripted run quits once it has closed what it opened.
        if isOn, ProcessInfo.processInfo.environment["MARKVIEW_SNAPSHOT"] == nil { show() } else { quit() }
    }

    static func show() {
        let start = shown ?? StartWindow()
        shown = start
        start.showWindow(nil)
        NSApp.activate()
    }

    private convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 440),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        window.title = "Welcome to Markview"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        // It can only be closed: there is nothing to miniaturise or zoom.
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.contentViewController = NSHostingController(rootView: StartView(recents: Self.recents))
        window.center()
        self.init(window: window)
        window.delegate = self
        // A document's window, once it shows, takes this one's place.
        documentObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeMainNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                if (note.object as? NSWindow)?.windowController is ViewerWindowController { self?.close() }
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        documentObserver.map(NotificationCenter.default.removeObserver)
        documentObserver = nil
        Self.shown = nil
        // Closed with nothing open, and nothing being chosen: Markview is done.
        DispatchQueue.main.async {
            let choosing = NSApp.windows.contains { $0 is NSOpenPanel && $0.isVisible }
            if NSDocumentController.shared.documents.isEmpty, !choosing { Self.quit() }
        }
    }

    /// The documents and folders opened lately that are still there, newest first.
    static var recents: [URL] {
        NSDocumentController.shared.recentDocumentURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    fileprivate static func open(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }
}

private struct StartView: View {
    let recents: [URL]
    @AppStorage(StartWindow.key) private var showsStartWindow = true
    @State private var selection: URL?

    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Spacer()
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 112, height: 112)
                Text("Markview")
                    .font(.system(size: 32, weight: .semibold))
                Text("Version \(version)")
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                VStack(spacing: 4) {
                    StartAction(symbol: "square.and.pencil", title: "New Document", detail: "Write Markdown, with the page beside it") {
                        NSDocumentController.shared.newDocument(nil)
                    }
                    StartAction(symbol: "folder", title: "Open…", detail: "A Markdown file, or a folder of them") {
                        // Modal, so that this window stays until a choice is made.
                        NSDocumentController.shared.urlsFromRunningOpenPanel()?.forEach(StartWindow.open)
                    }
                }
                .frame(width: 330)
                .padding(.top, 28)
                Spacer()
                Toggle("Show this window when no document is open", isOn: $showsStartWindow)
                    .toggleStyle(.checkbox)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 18)
            }
            .frame(width: 420)
            recentList
                .frame(width: 300)
        }
        .frame(height: 440)
    }

    /// Double-click or Return opens a recent document.
    private var recentList: some View {
        List(recents, id: \.self, selection: $selection) { url in
            RecentRow(url: url)
        }
        .listStyle(.sidebar)
        .contextMenu(forSelectionType: URL.self) { urls in
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(Array(urls)) }
        } primaryAction: { urls in
            urls.forEach(StartWindow.open)
        }
        .overlay {
            if recents.isEmpty { Text("No recent documents").foregroundStyle(.secondary) }
        }
    }
}

/// One of the start window's two buttons: a symbol, what it does, and a line on it.
private struct StartAction: View {
    let symbol: String, title: String, detail: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline)
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A recent document or folder: its icon, its name, and the folder it is in.
private struct RecentRow: View {
    let url: URL

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .padding(.vertical, 3)
        .help(url.path)
    }
}
