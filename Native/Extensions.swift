import Foundation

/// Markdown the parser does not know, rewritten into the Markdown and HTML it does:
/// math, admonitions, footnotes, wiki links, highlights, heading ids and emoji shortcodes.
/// Fenced code and code spans are left as written.
enum MarkdownExtensions {
    /// A formula written inline, which the text is left holding a marker for: the
    /// characters `formulaStart`, its index in the list, and `formulaEnd`.
    struct Formula {
        let tex: String
        let display: Bool
        var written: String { display ? "$$\(tex)$$" : "$\(tex)$" }
    }
    static let formulaStart: Character = "\u{E000}", formulaEnd: Character = "\u{E001}"

    static func apply(_ markdown: String, baseURL: URL, formulas: inout [Formula]) -> String {
        var text = markdown
        // First, so that nothing after it reads the inside of a formula as Markdown.
        if text.contains("$") { text = math(text, into: &formulas) }
        if text.contains(":::") || text.contains("!!! ") { text = admonitions(text) }
        if text.contains("[^") { text = footnotes(text) }
        if text.contains("[[") { text = wikiLinks(text, from: baseURL) }
        if text.contains("==") {
            text = rewrite(text, highlight) { match, source in "<mark>\(source.substring(with: match.range(at: 1)))</mark>" }
        }
        if text.contains("{#") {
            text = rewrite(text, headingID) { match, source in
                "\(source.substring(with: match.range(at: 1))) <a id=\"\(source.substring(with: match.range(at: 2)))\"></a>"
            }
        }
        text = rewrite(text, shortcode) { match, source in emoji[source.substring(with: match.range(at: 1))] }
        return text
    }

    /// GitHub's heading slug: lowercase, punctuation dropped, spaces to hyphens.
    static func slug(_ heading: String) -> String {
        let lowered = heading.trimmingCharacters(in: .whitespaces).lowercased()
        return String(lowered.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || " _-".unicodeScalars.contains($0) })
            .replacingOccurrences(of: " ", with: "-")
    }

    // MARK: Math

    /// `$$` on lines of their own becomes a ```math fence, and `$…$`, `$$…$$` and `` $`…`$ ``
    /// within a line become markers. A single `$` is read as Pandoc and GitHub read it: the
    /// opening one followed by a non-space, the closing one preceded by a non-space and not
    /// followed by a digit, so "$5 and $10" stays as written.
    private static func math(_ text: String, into formulas: inout [Formula]) -> String {
        let text = blockMath.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil ? mathBlocks(text) : text
        let source = text as NSString
        let characters = Array(text.utf16)
        let length = characters.count
        let protected = Protected(text)
        let dollar = unichar(36), backtick = unichar(96), newline = unichar(10)
        func at(_ index: Int) -> unichar { index < length ? characters[index] : 0 }
        func isSpace(_ character: unichar) -> Bool { character == 32 || character == 9 || character == newline || character == 13 }
        func escaped(_ index: Int) -> Bool {
            var count = 0, before = index - 1
            while before >= 0, at(before) == 92 { count += 1; before -= 1 }
            return count % 2 == 1
        }
        /// The next `$` from `start` that is not escaped, within the paragraph and before any code.
        func nextDollar(from start: Int) -> Int? {
            let code = protected.next(from: start)
            var index = start
            while index < min(length, code) {
                let character = at(index)
                if character == newline, at(index + 1) == newline { return nil }
                if character == dollar, !escaped(index) { return index }
                index += 1
            }
            return nil
        }

        var result = "", position = 0, index = 0
        func replace(through end: Int, with formula: Formula) {
            result += source.substring(with: NSRange(location: position, length: index - position))
            result += "\(formulaStart)\(formulas.count)\(formulaEnd)"
            formulas.append(formula)
            position = end
            index = end
        }
        while index < length {
            guard at(index) == dollar, !protected.contains(index), !escaped(index) else { index += 1; continue }
            if at(index + 1) == backtick {
                // $`…`$: the code span keeps the TeX safe from Markdown.
                let rest = NSRange(location: index + 2, length: length - index - 2)
                let close = source.range(of: "`$", range: rest)
                if close.location != NSNotFound, close.location > index + 2,
                   !source.substring(with: NSRange(location: index + 2, length: close.location - index - 2)).contains("\n") {
                    let tex = source.substring(with: NSRange(location: index + 2, length: close.location - index - 2))
                    replace(through: close.location + 2, with: Formula(tex: tex, display: false))
                    continue
                }
            } else if at(index + 1) == dollar {
                if let close = nextDollar(from: index + 2), at(close + 1) == dollar, close > index + 2 {
                    let tex = source.substring(with: NSRange(location: index + 2, length: close - index - 2))
                    if !tex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        replace(through: close + 2, with: Formula(tex: tex, display: true))
                        continue
                    }
                }
                index += 2
                continue
            } else if index + 1 < length, !isSpace(at(index + 1)), let close = nextDollar(from: index + 1),
                      !isSpace(at(close - 1)), !(48...57).contains(at(close + 1)), at(close + 1) != dollar {
                replace(through: close + 1, with: Formula(tex: source.substring(with: NSRange(location: index + 1, length: close - index - 1)), display: false))
                continue
            }
            index += 1
        }
        guard position > 0 else { return text }
        return result + source.substring(from: position)
    }

    private static let blockMath = try! NSRegularExpression(pattern: #"(?m)^[ \t>]*\$\$"#)

    /// `$$` blocks on lines of their own, in a quote or a list item too, as ```math fences.
    private static func mathBlocks(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var result: [String] = []
        var inFence = false, fence = ""
        var index = 0
        func split(_ line: Substring) -> (prefix: Substring, rest: Substring) {
            let prefix = line.prefix { $0 == " " || $0 == "\t" || $0 == ">" }
            return (prefix, line.dropFirst(prefix.count))
        }
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.drop { $0 == " " }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if inFence { if trimmed.hasPrefix(fence) { inFence = false } } else { inFence = true; fence = String(trimmed.prefix(3)) }
            }
            let (prefix, rest) = split(line)
            let opening = rest.dropFirst(2).trimmingCharacters(in: .whitespaces)
            // `$$x$$ and more` is inline, and left to the pass above.
            if !inFence, rest.hasPrefix("$$"), !opening.dropLast(2).contains("$$"), opening.hasSuffix("$$") || !opening.contains("$$") {
                var body: [String] = []
                var end: Int?
                if opening.hasSuffix("$$"), opening.count > 2 {
                    body = [String(opening.dropLast(2))]
                    end = index
                } else if opening.isEmpty || !opening.hasSuffix("$$") {
                    if !opening.isEmpty { body.append(opening) }
                    var next = index + 1
                    while next < lines.count {
                        let content = split(lines[next]).rest.trimmingCharacters(in: .whitespaces)
                        if content.isEmpty { break }   // a blank line ends the paragraph before the math does
                        if content.hasSuffix("$$") {
                            if content.count > 2 { body.append(String(content.dropLast(2))) }
                            end = next
                            break
                        }
                        body.append(content)
                        next += 1
                    }
                }
                if let end, !body.joined().trimmingCharacters(in: .whitespaces).isEmpty {
                    result.append(prefix + "```math")
                    result += body.map { String(prefix) + $0 }
                    result.append(prefix + "```")
                    index = end + 1
                    continue
                }
            }
            result.append(String(line))
            index += 1
        }
        return result.joined(separator: "\n")
    }

    // MARK: Admonitions

    private static let docusaurus = try! NSRegularExpression(pattern: #"^:{3,}([A-Za-z]+)(?:\[([^\]]*)\]|[ \t]+(.*?))?[ \t]*$"#)
    private static let mkdocs = try! NSRegularExpression(pattern: #"^!!! +([A-Za-z]+)(?: +"([^"]*)")?[ \t]*$"#)

    /// `:::note Title … :::` (Docusaurus) and `!!! note "Title"` with an indented body (MkDocs)
    /// become callout blockquotes.
    private static func admonitions(_ text: String) -> String {
        var result: [Substring] = []
        var inFence = false, fence = ""
        var open: (mkdocs: Bool, blankBefore: Bool)?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.drop { $0 == " " }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if inFence { if trimmed.hasPrefix(fence) { inFence = false } } else { inFence = true; fence = String(trimmed.prefix(3)) }
            }
            if let state = open {
                if state.mkdocs {
                    if line.isEmpty { result.append(">"); open?.blankBefore = true; continue }
                    if line.hasPrefix("    ") { result.append("> " + line.dropFirst(4)); open?.blankBefore = false; continue }
                    if line.hasPrefix("\t") { result.append("> " + line.dropFirst()); open?.blankBefore = false; continue }
                    open = nil
                    result.append("")   // otherwise the line would continue the quote
                } else {
                    if !inFence, trimmed.hasPrefix(":::"), trimmed.drop(while: { $0 == ":" }).allSatisfy(\.isWhitespace) {
                        open = nil
                        result.append("")
                        continue
                    }
                    result.append(line.isEmpty ? ">" : "> " + line)
                    continue
                }
            }
            if !inFence {
                let whole = NSRange(location: 0, length: (line as NSString).length)
                if let match = docusaurus.firstMatch(in: String(line), range: whole) ?? mkdocs.firstMatch(in: String(line), range: whole) {
                    let source = line as NSString
                    let kind = source.substring(with: match.range(at: 1))
                    let title = (2..<match.numberOfRanges).compactMap { match.range(at: $0).location == NSNotFound ? nil : source.substring(with: match.range(at: $0)) }.first ?? ""
                    result.append("> [!\(kind)] \(title)")
                    open = (mkdocs: trimmed.hasPrefix("!!!"), blankBefore: false)
                    continue
                }
            }
            result.append(line)
        }
        return result.joined(separator: "\n")
    }

    // MARK: Footnotes

    private static let definition = try! NSRegularExpression(pattern: #"^\[\^([^\]\s]+)\]:[ \t]*(.*)$"#)
    private static let reference = try! NSRegularExpression(pattern: #"\[\^([^\]\s]+)\](?!:)"#)

    /// `[^id]` becomes a numbered superscript link, and the definitions move to a list at the end.
    private static func footnotes(_ text: String) -> String {
        var notes: [String: String] = [:]
        var kept: [Substring] = []
        var inFence = false, fence = ""
        var current: String?, blankAbsorbed = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.drop { $0 == " " }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if inFence { if trimmed.hasPrefix(fence) { inFence = false } } else { inFence = true; fence = String(trimmed.prefix(3)) }
            }
            if let id = current {
                if line.hasPrefix("    ") || line.hasPrefix("\t") {
                    notes[id]! += (blankAbsorbed ? "\n\n" : "\n") + line.drop { $0 == " " || $0 == "\t" }
                    blankAbsorbed = false
                    continue
                }
                if line.isEmpty { blankAbsorbed = true; continue }
                current = nil
                if blankAbsorbed { kept.append("") }
            }
            if !inFence, line.hasPrefix("[^"), let match = definition.firstMatch(in: String(line), range: NSRange(location: 0, length: (line as NSString).length)) {
                let source = line as NSString
                let id = source.substring(with: match.range(at: 1))
                notes[id] = source.substring(with: match.range(at: 2))
                current = id
                blankAbsorbed = false
                continue
            }
            kept.append(line)
        }
        guard !notes.isEmpty else { return text }
        var numbers: [String: Int] = [:], used: [String] = []
        let body = rewrite(kept.joined(separator: "\n"), reference) { match, source in
            let id = source.substring(with: match.range(at: 1))
            guard notes[id] != nil else { return nil }
            let number = numbers[id] ?? { used.append(id); numbers[id] = used.count; return used.count }()
            return "<sup><a href=\"#fn-\(id)\" id=\"fnref-\(id)\">\(number)</a></sup>"
        }
        guard !used.isEmpty else { return body }
        var section = "\n\n---\n\n"
        for (index, id) in used.enumerated() {
            let note = notes[id]!.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: "\n   ")
            section += "\(index + 1). <a id=\"fn-\(id)\"></a>\(note) [↩](#fnref-\(id))\n"
        }
        return body + section
    }

    // MARK: Wiki links

    private static let wikiLink = try! NSRegularExpression(pattern: #"(!?)\[\[([^\]\[|#]+)(?:#([^\]\[|]+))?(?:\|([^\]\[]+))?\]\]"#)
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "svg", "webp", "bmp", "tiff", "heic"]

    /// `[[Page]]`, `[[Page#Heading]]`, `[[Page|Label]]` and `![[image.png]]`, resolved against
    /// the files around the document.
    private static func wikiLinks(_ text: String, from baseURL: URL) -> String {
        let index = FolderIndex(root: baseURL.deletingLastPathComponent())
        return rewrite(text, wikiLink) { match, source in
            func group(_ number: Int) -> String? {
                let range = match.range(at: number)
                return range.location == NSNotFound ? nil : source.substring(with: range)
            }
            let name = (group(2) ?? "").trimmingCharacters(in: .whitespaces)
            let heading = group(3)?.trimmingCharacters(in: .whitespaces)
            let label = group(4)?.trimmingCharacters(in: .whitespaces) ?? (heading.map { "\(name) › \($0)" } ?? name)
            let hasExtension = !(name as NSString).pathExtension.isEmpty
            var destination = index.resolve(name) ?? (hasExtension ? name : name + ".md")
            if let heading { destination += "#" + slug(heading) }
            let picture = imageExtensions.contains((destination as NSString).pathExtension.lowercased())
            return (match.range(at: 1).length > 0 && picture ? "!" : "") + "[\(label)](<\(destination)>)"
        }
    }

    /// The files under the document's folder, by name, for wiki links. Built on first use.
    private final class FolderIndex {
        private let root: URL
        private var paths: [String: String]?

        init(root: URL) { self.root = root }

        func resolve(_ name: String) -> String? {
            if paths == nil { build() }
            let key = name.lowercased()
            let plain = (key as NSString).deletingPathExtension
            return paths?[key] ?? paths?[plain] ?? paths?[(plain as NSString).lastPathComponent]
        }

        private func build() {
            var found: [String: String] = [:]
            let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                            options: [.skipsHiddenFiles, .skipsPackageDescendants])
            var count = 0
            while let url = enumerator?.nextObject() as? URL, count < 5000 {
                if url.lastPathComponent == "node_modules" { enumerator?.skipDescendants(); continue }
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                count += 1
                let relative = String(url.path.dropFirst(root.path.count + 1)).lowercased()
                let keys = [relative, (relative as NSString).deletingPathExtension, url.lastPathComponent.lowercased(),
                            url.deletingPathExtension().lastPathComponent.lowercased()]
                for key in keys where found[key] == nil { found[key] = url.path }
            }
            paths = found
        }
    }

    // MARK: Inline

    private static let highlight = try! NSRegularExpression(pattern: #"(?<!=)==([^=\n]+?)==(?!=)"#)
    private static let headingID = try! NSRegularExpression(pattern: #"(?m)^(#{1,6}[ \t]+.*?)[ \t]*\{#([A-Za-z0-9_\-:.]+)\}[ \t]*$"#)
    private static let shortcode = try! NSRegularExpression(pattern: #":([a-z0-9_+\-]+):"#)
    private static let codeSpan = try! NSRegularExpression(pattern: #"`[^`\n]+`"#)

    private static let emoji: [String: String] = {
        guard let url = Bundle.main.url(forResource: "emoji", withExtension: "tsv", subdirectory: "vendor"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var table: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            if parts.count == 2 { table[String(parts[0])] = String(parts[1]) }
        }
        return table
    }()

    /// Replaces the matches of a pattern outside code; a nil replacement leaves the match as it is.
    private static func rewrite(_ text: String, _ regex: NSRegularExpression,
                                _ replacement: (NSTextCheckingResult, NSString) -> String?) -> String {
        let source = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return text }
        let protected = Protected(text)
        var result = "", position = 0
        for match in matches where match.range.location >= position && !protected.contains(match.range.location) {
            guard let replaced = replacement(match, source) else { continue }
            result += source.substring(with: NSRange(location: position, length: match.range.location - position))
            result += replaced
            position = match.range.location + match.range.length
        }
        guard position > 0 else { return text }
        return result + source.substring(from: position)
    }

    /// Where fenced code and code spans are, so nothing inside them is rewritten.
    private struct Protected {
        private let ranges: [NSRange]

        // Read as UTF-16 units: line by line as strings, this took 70 ms a megabyte, and it runs
        // once for each extension a document uses.
        init(_ text: String) {
            let characters = Array(text.utf16)
            let length = characters.count
            var found: [NSRange] = []
            var fenceStart: Int?, fence: unichar = 0
            var lineStart = 0
            while lineStart < length {
                var lineEnd = lineStart
                while lineEnd < length, characters[lineEnd] != 10, characters[lineEnd] != 13 { lineEnd += 1 }
                var first = lineStart
                while first < lineEnd, characters[first] == 32 { first += 1 }
                // A fence is three backticks or tildes after any spaces; it closes on three of the same.
                let mark = first + 2 < lineEnd ? characters[first] : 0
                let isFence = (mark == 96 || mark == 126) && characters[first + 1] == mark && characters[first + 2] == mark
                if let start = fenceStart {
                    if isFence, mark == fence {
                        found.append(NSRange(location: start, length: lineEnd - start))
                        fenceStart = nil
                    }
                } else if isFence {
                    fence = mark
                    fenceStart = lineStart
                }
                lineStart = lineEnd + 1
            }
            if let start = fenceStart { found.append(NSRange(location: start, length: length - start)) }
            found += codeSpan.matches(in: text, range: NSRange(location: 0, length: length)).map(\.range)
            ranges = found.sorted { $0.location < $1.location }
        }

        /// Where the first range at or after a location starts.
        func next(from location: Int) -> Int {
            var low = 0, high = ranges.count
            while low < high {
                let middle = (low + high) / 2
                if ranges[middle].location + ranges[middle].length <= location { low = middle + 1 } else { high = middle }
            }
            return low < ranges.count ? ranges[low].location : Int.max
        }

        func contains(_ location: Int) -> Bool {
            var low = 0, high = ranges.count - 1
            while low <= high {
                let middle = (low + high) / 2
                let range = ranges[middle]
                if location < range.location { high = middle - 1 }
                else if location >= range.location + range.length { low = middle + 1 }
                else { return true }
            }
            return false
        }
    }
}
