import Foundation

/// How the preview hands a clicked link to the `LinkOpener` service.
@objc protocol LinkOpening {
    func open(_ url: URL)
}
