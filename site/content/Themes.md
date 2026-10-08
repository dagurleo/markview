# Themes

Markview has twelve themes, each with a light and a dark side: GitHub, Solarized, One, Monokai, Dracula, Nord, Tokyo Night, Catppuccin, Gruvbox, Ayu, Rosé Pine and Paper. Light or dark follows the system unless you choose one.

The theme menu at the top of this window uses the same colours, read from Markview's source. Try a few on this page: <kbd>T</kbd> steps through them and <kbd>A</kbd> switches between light and dark.

```swift
struct Note: Identifiable {
    let id = UUID()
    var title: String
    var tags: [String] = ["markdown", "mac"]

    // The note's title as a Markdown heading.
    func heading() -> String { "# \(title)" }
}
```

> [!NOTE]
> Each theme colours GitHub's alerts, too.

> [!TIP]
> Printing and PDFs use the theme's light side.

> [!WARNING]
> Monokai and Nord have no official light side. Markview's darkens their colours to read on a light page.

<p align="center"><img src="/shots/settings-window-light.webp" width="460" alt="Markview's Settings window, with the twelve themes"></p>

Settings (⌘,) also choose:

| Setting | |
| --- | --- |
| Text size | The whole page follows it, headings and code included |
| Text and code fonts | The fonts for prose and for code |
| Line length | How wide the column of text may grow |
| Line spacing | Tight, Default or Loose |

Changes show at once, in open windows and in Quick Look previews.
