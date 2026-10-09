import Foundation

/// What the editor's slash menu offers. Typing `/` at the start of a line or after a space opens
/// it, and the word typed after the slash finds a command by name.
///
/// A template marks the places to fill in as ⟨text⟩: the first is selected once the template is
/// in, and Tab goes on to the next. An empty ⟨⟩ is a place for the insertion point.
struct SlashCommand {
    enum Kind {
        /// Marks the line as a heading, a list item or a quote, in place of what it was.
        case line(String)
        /// Lines of their own, set apart from the text around them: a code block, a table.
        case block(String)
        /// Text where the slash was.
        case inline(String)
        /// A picture chosen from a file.
        case image
        /// A reference where the slash was, and its note at the end.
        case footnote
        /// Front matter, which goes at the top of the document whatever the line.
        case frontMatter
    }

    var title: String
    let symbol: String
    /// The Markdown it writes, shown beside its title.
    let hint: String
    /// The names it is found by besides its title. The first is the word typed before a choice,
    /// as in "/code swift".
    let keywords: [String]
    let kind: Kind
    /// A second choice, made after this one: a code block's language, a callout's kind.
    var choices: [SlashCommand]? = nil
    /// The title a choice has when found by its own name: "Swift code block".
    var fullTitle: String? = nil

    var word: String { keywords.first ?? title.lowercased() }

    var isFrontMatter: Bool {
        if case .frontMatter = kind { return true }
        return false
    }

    private static func choice(_ title: String, _ word: String, also others: [String] = [], symbol: String, hint: String? = nil,
                               full: String, _ template: String) -> SlashCommand {
        SlashCommand(title: title, symbol: symbol, hint: hint ?? word, keywords: [word] + others, kind: .block(template), fullTitle: full)
    }
}

extension SlashCommand {
    static let all: [SlashCommand] = [
        SlashCommand(title: "Heading 1", symbol: "number", hint: "#", keywords: ["h1", "heading", "title"], kind: .line("# ")),
        SlashCommand(title: "Heading 2", symbol: "number", hint: "##", keywords: ["h2", "heading", "subheading"], kind: .line("## ")),
        SlashCommand(title: "Heading 3", symbol: "number", hint: "###", keywords: ["h3", "heading"], kind: .line("### ")),
        SlashCommand(title: "Bulleted list", symbol: "list.bullet", hint: "-", keywords: ["ul", "bullet", "unordered"], kind: .line("- ")),
        SlashCommand(title: "Numbered list", symbol: "list.number", hint: "1.", keywords: ["ol", "ordered"], kind: .line("1. ")),
        SlashCommand(title: "Task list", symbol: "checklist", hint: "- [ ]", keywords: ["todo", "checkbox", "checklist"], kind: .line("- [ ] ")),
        SlashCommand(title: "Quote", symbol: "text.quote", hint: ">", keywords: ["blockquote", "citation"], kind: .line("> ")),
        codeBlock,
        SlashCommand(title: "Table", symbol: "tablecells", hint: "| |", keywords: ["grid", "columns"],
                     kind: .block("| ⟨Column 1⟩ | Column 2 | Column 3 |\n| -------- | -------- | -------- |\n|          |          |          |\n|          |          |          |")),
        SlashCommand(title: "Link", symbol: "link", hint: "[ ]( )", keywords: ["url", "hyperlink"], kind: .inline("[⟨text⟩](⟨url⟩)⟨⟩")),
        SlashCommand(title: "Image", symbol: "photo", hint: "![ ]( )", keywords: ["picture", "photo", "img"], kind: .image),
        SlashCommand(title: "Divider", symbol: "minus", hint: "---", keywords: ["hr", "rule", "line", "separator"], kind: .block("---⟨⟩")),
        SlashCommand(title: "Math", symbol: "function", hint: "$$", keywords: ["equation", "latex", "formula", "tex"], kind: .block("$$\n⟨E = mc^2⟩\n$$")),
        diagram,
        callout,
        SlashCommand(title: "Footnote", symbol: "textformat.superscript", hint: "[^1]", keywords: ["reference", "cite"], kind: .footnote),
        SlashCommand(title: "Front matter", symbol: "doc.text", hint: "---", keywords: ["frontmatter", "yaml", "metadata", "properties"],
                     kind: .frontMatter),
    ]

    private static let codeBlock: SlashCommand = {
        var code = SlashCommand(title: "Code block", symbol: codeSymbol, hint: "```",
                                keywords: ["code", "fence", "snippet", "pre"], kind: .block("```\n⟨⟩\n```"))
        code.choices = [
            ("Swift", "swift", []), ("Python", "python", ["py"]), ("JavaScript", "javascript", ["js", "jsx"]),
            ("TypeScript", "typescript", ["ts", "tsx"]), ("Shell", "bash", ["sh", "shell", "zsh", "terminal"]), ("JSON", "json", []),
            ("YAML", "yaml", ["yml"]), ("HTML", "html", ["xml"]), ("CSS", "css", ["scss"]), ("SQL", "sql", []), ("Go", "go", ["golang"]),
            ("Rust", "rust", ["rs"]), ("Ruby", "ruby", ["rb"]), ("Java", "java", []), ("Kotlin", "kotlin", ["kt"]), ("C", "c", []),
            ("C++", "cpp", ["c++"]), ("C#", "csharp", ["cs", "c#"]), ("PHP", "php", []), ("Diff", "diff", ["patch"]),
            ("Markdown", "markdown", ["md"]), ("Plain text", "text", ["plain", "txt"]),
        ].map { title, word, others in choice(title, word, also: others, symbol: codeSymbol, full: "\(title) code block", "```\(word)\n⟨⟩\n```") }
        return code
    }()

    private static let codeSymbol = "chevron.left.forwardslash.chevron.right"

    /// A code block in a language no choice has, as typed after "/code".
    static func codeBlock(in language: String) -> SlashCommand {
        choice(language, language, symbol: codeSymbol, full: "\(language) code block", "```\(language)\n⟨⟩\n```")
    }

    private static let diagram: SlashCommand = {
        let symbol = "point.3.connected.trianglepath.dotted"
        var diagram = SlashCommand(title: "Diagram", symbol: symbol, hint: "mermaid",
                                   keywords: ["diagram", "mermaid", "chart", "graph"], kind: .block("```mermaid\n⟨⟩\n```"))
        let today = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        diagram.choices = [
            ("Flowchart", "flowchart", ["flow"], "flowchart TD\n    A[⟨Start⟩] --> B{Ready?}\n    B -->|Yes| C[Go]\n    B -->|No| D[Wait]\n    D --> B"),
            ("Sequence diagram", "sequence", [], "sequenceDiagram\n    ⟨Alice⟩->>Bob: Hello, Bob\n    Bob-->>Alice: Hi, Alice"),
            ("Class diagram", "class", [], "classDiagram\n    class ⟨Animal⟩ {\n        +String name\n        +eat()\n    }\n    Animal <|-- Dog"),
            ("State diagram", "state", [], "stateDiagram-v2\n    [*] --> ⟨Idle⟩\n    Idle --> Running: start\n    Running --> Idle: stop\n    Running --> [*]"),
            ("Entity relationship", "er", ["entity", "relationship"], "erDiagram\n    ⟨CUSTOMER⟩ ||--o{ ORDER : places\n    ORDER ||--|{ LINE_ITEM : contains"),
            ("Gantt chart", "gantt", ["schedule", "timeline"], "gantt\n    title ⟨Plan⟩\n    dateFormat YYYY-MM-DD\n    section Work\n    Design :a1, \(today), 7d\n    Build  :after a1, 14d"),
            ("Pie chart", "pie", [], "pie title ⟨Pets⟩\n    \"Dogs\" : 40\n    \"Cats\" : 35\n    \"Birds\" : 25"),
            ("Mind map", "mindmap", ["mind"], "mindmap\n  root((⟨Idea⟩))\n    One\n    Two\n      Detail"),
        ].map { title, word, others, body in choice(title, word, also: others, symbol: symbol, hint: "", full: title, "```mermaid\n\(body)\n```") }
        return diagram
    }()

    private static let callout: SlashCommand = {
        var callout = SlashCommand(title: "Callout", symbol: "exclamationmark.bubble", hint: "> [!]",
                                   keywords: ["callout", "alert", "admonition"], kind: .block("> [!NOTE]\n> ⟨⟩"))
        callout.choices = [
            ("Note", "info.circle"), ("Tip", "lightbulb"), ("Important", "exclamationmark.bubble"),
            ("Warning", "exclamationmark.triangle"), ("Caution", "exclamationmark.octagon"),
        ].map { title, symbol in
            let kind = title.uppercased()
            return choice(title, title.lowercased(), symbol: symbol, hint: "[!\(kind)]", full: "\(title) callout", "> [!\(kind)]\n> ⟨⟩")
        }
        return callout
    }()

    /// The commands a query finds, best first. "code swift" picks a command's choices, and a
    /// choice is found by its own name too: "swift" finds the Swift code block.
    static func matches(_ query: String, allowingFrontMatter: Bool = true) -> [SlashCommand] {
        let query = query.lowercased()
        let commands = all.filter { allowingFrontMatter || !$0.isFrontMatter }
        if let space = query.firstIndex(of: " ") {
            let word = String(query[..<space]), rest = query[query.index(after: space)...].trimmingCharacters(in: .whitespaces)
            guard let command = commands.first(where: { $0.choices != nil && $0.keywords.contains(word) }) else { return [] }
            var found = ranked(command.choices!, by: rest)
            // Any language highlight.js may know, as typed.
            if command.word == "code", !rest.isEmpty, !rest.contains(" "), !found.contains(where: { $0.keywords.contains(rest) }) {
                found.append(codeBlock(in: rest))
            }
            return found
        }
        guard !query.isEmpty else { return commands }
        let choices = commands.flatMap { $0.choices ?? [] }.map { choice in
            var full = choice
            full.title = choice.fullTitle ?? choice.title
            return full
        }
        return ranked(commands + choices, by: query)
    }

    /// Commands that match a query: by a keyword exactly, by the start of the title, of a word of
    /// it or of a keyword, then, from two letters on, anywhere in the title, in that order and
    /// otherwise as listed.
    private static func ranked(_ commands: [SlashCommand], by query: String) -> [SlashCommand] {
        guard !query.isEmpty else { return commands }
        func score(_ command: SlashCommand) -> Int? {
            let title = command.title.lowercased()
            if command.keywords.contains(query) || title == query { return 0 }
            if title.hasPrefix(query) { return 1 }
            if title.split(separator: " ").contains(where: { $0.hasPrefix(query) }) { return 2 }
            if command.keywords.contains(where: { $0.hasPrefix(query) }) { return 3 }
            if query.count >= 2, title.contains(query) { return 4 }
            return nil
        }
        return commands.enumerated().compactMap { index, command in score(command).map { ($0, index, command) } }
            .sorted { ($0.0, $0.1) < ($1.0, $1.1) }.map(\.2)
    }

    /// A template's text without its ⟨fields⟩, and where each field is in it.
    static func fill(_ template: String) -> (text: String, fields: [NSRange]) {
        var text = "", fields: [NSRange] = [], length = 0, start: Int?
        for character in template {
            switch character {
            case "⟨": start = length
            case "⟩":
                fields.append(NSRange(location: start ?? length, length: length - (start ?? length)))
                start = nil
            default:
                text.append(character)
                length += character.utf16.count
            }
        }
        return (text, fields)
    }
}
