import Cocoa
import Quartz

/// The Quick Look preview Finder shows when Space is pressed on a Markdown file.
/// It shows the document with the same native view as the app's windows.
///
/// To check it, `./build.sh install` and then `qlmanage -p sample/sample.md`:
/// Quick Look only runs the installed copy, which is the one that is registered.
@objc(PreviewViewController)
final class PreviewViewController: NSViewController, QLPreviewingController {
    private let markdownView = MarkdownView(frame: NSRect(x: 0, y: 0, width: 880, height: 640))
    private lazy var linkOpener: NSXPCConnection = {
        let connection = NSXPCConnection(serviceName: "com.dagurleo.markview.quicklook.LinkOpener")
        connection.remoteObjectInterface = NSXPCInterface(with: LinkOpening.self)
        connection.resume()
        return connection
    }()

    override func loadView() {
        // A preview only ever shows its own file, and its sandbox can't open
        // anything else: clicked links go to the LinkOpener service.
        markdownView.open = { [weak self] url in
            (self?.linkOpener.remoteObjectProxy as? LinkOpening)?.open(url)
        }
        view = markdownView
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        do {
            // Settings read afresh for each preview: the extension outlives a change made in the app.
            markdownView.theme = Settings.theme
            markdownView.appearance = Settings.appearance
            markdownView.show(String(decoding: try Data(contentsOf: url), as: UTF8.self), baseURL: url)
            handler(nil)
        } catch {
            handler(error)
        }
    }
}
