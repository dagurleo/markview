import Foundation

/// Where a link in a document may lead: shared by the app, the Quick Look
/// preview and the service that opens links for it.
enum Links {
    static let markdownExtensions: Set = ["md", "markdown", "mdown", "mkd", "mdx", "mdwn", "mkdn", "rmd", "qmd"]
    static let webSchemes: Set = ["http", "https", "mailto"]
}
