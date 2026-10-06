import Foundation

/// Markview: SwiftPM gives a package's resources a `Bundle.module`, and Markview is built
/// without SwiftPM. The fonts are in the app's Contents/Resources/Fonts; the Quick Look
/// extension, which is inside the app, reads them from there too.
extension Bundle {
    static let module: Bundle = {
        var app = Bundle.main.bundleURL
        if app.pathExtension == "appex" {   // Markview.app/Contents/PlugIns/<extension>
            app = app.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        }
        return Bundle(url: app) ?? .main
    }()
}
