import Cocoa

/// Quick Look's sandbox stops a preview from opening anything, so clicked links
/// come to this XPC service instead. It applies the same rules as the app's
/// windows: web links go to the browser, Markdown opens in Markview, and any
/// other local file is only revealed in Finder.
final class LinkOpener: NSObject, LinkOpening, NSXPCListenerDelegate {
    /// The copy of Markview this service is bundled in, six levels up:
    /// Markview.app/Contents/PlugIns/<appex>/Contents/XPCServices/<this service>.
    private let markview = (0..<6).reduce(Bundle.main.bundleURL) { url, _ in url.deletingLastPathComponent() }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: LinkOpening.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func open(_ url: URL) {
        if url.isFileURL {
            let file = URL(fileURLWithPath: url.path)
            if Links.markdownExtensions.contains(file.pathExtension.lowercased()) {
                NSWorkspace.shared.open([file], withApplicationAt: markview, configuration: NSWorkspace.OpenConfiguration())
            } else if FileManager.default.fileExists(atPath: file.path) {
                NSWorkspace.shared.activateFileViewerSelecting([file])
            }
        } else if Links.webSchemes.contains(url.scheme ?? "") {
            NSWorkspace.shared.open(url)
        }
    }
}

let opener = LinkOpener()
let listener = NSXPCListener.service()
listener.delegate = opener
listener.resume()
