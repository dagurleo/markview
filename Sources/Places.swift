import Foundation

/// Where each document was last read, so that opening it again goes back there. Kept in the
/// defaults as the character at the top of the window, for the last 200 documents read.
enum Places {
    private static let key = "places", limit = 200

    static func place(of file: URL) -> Int? {
        entries.first { $0["path"] as? String == file.path }?["at"] as? Int
    }

    /// The top of a document is no place to remember: it is where a document opens anyway.
    static func remember(_ place: Int, of file: URL) {
        if let latest = entries.first, latest["path"] as? String == file.path, latest["at"] as? Int == place { return }
        var entries = entries.filter { $0["path"] as? String != file.path }
        if place > 0 { entries.insert(["path": file.path, "at": place], at: 0) }
        UserDefaults.standard.set(Array(entries.prefix(limit)), forKey: key)
    }

    private static var entries: [[String: Any]] {
        UserDefaults.standard.array(forKey: key) as? [[String: Any]] ?? []
    }
}
