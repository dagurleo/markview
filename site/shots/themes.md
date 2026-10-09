# Field notes

Markview reads **Markdown** the way GitHub shows it, with [links](https://example.com),
`inline code` and ==highlights==.

> [!TIP]
> Every theme has a light and a dark side, and printing uses the light one.

```swift
struct Note: Identifiable {
    let id = UUID()
    var title: String
    var tags: [String] = ["markdown", "mac"]
    func render() -> String { "# \(title)" } // 42
}
```

| Keys | Does |
| ---- | ---- |
| ⌘F | Find in the page |
| ⌥⌘↓ | Next heading |

