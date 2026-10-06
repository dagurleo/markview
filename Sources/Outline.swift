import Foundation

/// A heading of the open document, for the Go menu.
struct Heading {
    let level: Int
    let title: String
    let anchor: String
}

/// What the Go menu asks of a document window.
protocol DocumentOutline: AnyObject {
    var headings: [Heading] { get }
    func jump(to anchor: String)
}

/// Actions the File and View menus send to a document window. A protocol, so the menu
/// can name them without depending on the window controller.
@objc protocol DocumentActions {
    func printDocument(_ sender: Any?)
    func exportPDF(_ sender: Any?)
    func toggleSource(_ sender: Any?)
}
