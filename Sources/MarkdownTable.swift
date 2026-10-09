import Foundation

/// A GitHub table as written: its rows of cells and how each column is aligned. Written out again,
/// its pipes line up, every row has every column, and the delimiter row is as wide as the column.
struct MarkdownTable {
    enum Alignment { case none, left, center, right }

    /// The header first, then the body. The delimiter row is not among them.
    var rows: [[String]]
    var alignments: [Alignment]
    /// How far in the table is, as written.
    var indent = ""

    var columns: Int { alignments.count }

    /// A table from its lines: a header row, then a delimiter row, then the body.
    init?(lines: [String]) {
        guard lines.count >= 2, Self.isDelimiterRow(lines[1]) else { return nil }
        let header = Self.cells(of: lines[0]), delimiter = Self.cells(of: lines[1])
        guard header.count == delimiter.count else { return nil }
        indent = String(lines[0].prefix { $0 == " " })
        alignments = delimiter.map { cell in
            switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
            case (true, true): .center
            case (true, false): .left
            case (false, true): .right
            case (false, false): .none
            }
        }
        rows = [header] + lines.dropFirst(2).map(Self.cells)
        // A body row with more cells than the header widens the table, rather than losing them.
        let widest = rows.map(\.count).max() ?? 0
        alignments += Array(repeating: .none, count: max(widest - alignments.count, 0))
        rows = rows.map { $0 + Array(repeating: "", count: columns - $0.count) }
    }

    /// Whether a line is a table's delimiter row, as in `| --- | :-: |`.
    static func isDelimiterRow(_ line: String) -> Bool {
        let cells = cells(of: line)
        guard line.contains("|"), !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let dashes = cell.drop { $0 == ":" }.reversed().drop { $0 == ":" }
            return !dashes.isEmpty && dashes.allSatisfy { $0 == "-" }
        }
    }

    /// A row's cells, trimmed. Pipes at the ends are optional; an escaped pipe is part of a cell.
    static func cells(of line: String) -> [String] {
        var cells: [String] = [], cell = "", escaped = false
        for character in line {
            if character == "|", !escaped {
                cells.append(cell)
                cell = ""
            } else {
                cell.append(character)
            }
            escaped = character == "\\" && !escaped
        }
        cells.append(cell)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { cells.removeFirst() }
        if trimmed.hasSuffix("|"), !trimmed.hasSuffix("\\|"), cells.count > 0 { cells.removeLast() }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Which cell of a line holds a location in it, counting from 0: the pipes before it.
    static func column(at location: Int, in line: String) -> Int {
        var pipes = 0, escaped = false, offset = 0
        for character in line {
            guard offset < location else { break }
            if character == "|", !escaped { pipes += 1 }
            escaped = character == "\\" && !escaped
            offset += character.utf16.count
        }
        let leading = line.trimmingCharacters(in: .whitespaces).hasPrefix("|")
        return max(pipes - (leading ? 1 : 0), 0)
    }

    /// The table written out with its columns lined up, and where each cell's text is in it, by
    /// row, as `rows` counts them.
    func formatted() -> (text: String, cells: [[NSRange]]) {
        var widths = (0..<columns).map { column in rows.map { Self.width(of: $0[column]) }.max() ?? 0 }
        widths = widths.map { max($0, 3) }
        var lines: [String] = [], cells: [[NSRange]] = [], location = 0
        func row(_ texts: [String], padding: (Int, String) -> (text: String, lead: Int)) -> (String, [NSRange]) {
            var line = indent + "|", ranges: [NSRange] = []
            for (column, text) in texts.enumerated() {
                let padded = padding(column, text)
                ranges.append(NSRange(location: location + (line as NSString).length + 1 + padded.lead, length: (text as NSString).length))
                line += " " + padded.text + " |"
            }
            return (line, ranges)
        }
        for (index, texts) in rows.enumerated() {
            let (line, ranges) = row(texts) { column, text in pad(text, to: widths[column], alignments[column]) }
            lines.append(line)
            cells.append(ranges)
            location += (line as NSString).length + 1
            if index == 0 {
                let (delimiter, _) = row(widths.map { String(repeating: "-", count: $0) }) { column, dashes in
                    switch alignments[column] {
                    case .none: (dashes, 0)
                    case .left: (":" + dashes.dropFirst(), 0)
                    case .right: (dashes.dropLast() + ":", 0)
                    case .center: (":" + dashes.dropFirst().dropLast() + ":", 0)
                    }
                }
                lines.append(delimiter)
                location += (delimiter as NSString).length + 1
            }
        }
        return (lines.joined(separator: "\n"), cells)
    }

    /// A cell's text with spaces to fill its column, and how many of them go before it.
    private func pad(_ text: String, to width: Int, _ alignment: Alignment) -> (text: String, lead: Int) {
        let room = max(width - Self.width(of: text), 0)
        let lead = switch alignment {
        case .right: room
        case .center: room / 2
        case .none, .left: 0
        }
        return (String(repeating: " ", count: lead) + text + String(repeating: " ", count: room - lead), lead)
    }

    /// How many columns of a monospaced font text takes: two for each wide East Asian character
    /// and emoji, one for anything else.
    static func width(of text: String) -> Int {
        text.reduce(0) { total, character in
            guard let scalar = character.unicodeScalars.first else { return total }
            let wide = scalar.properties.isEmojiPresentation || [0x1100...0x115F, 0x2E80...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF,
                                                                 0xFE30...0xFE4F, 0xFF00...0xFF60, 0xFFE0...0xFFE6, 0x20000...0x3FFFD]
                .contains { $0.contains(scalar.value) }
            return total + (wide ? 2 : 1)
        }
    }
}
