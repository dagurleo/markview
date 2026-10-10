<div align="center" class="intro">
<img class="icon" src="/icon.png" width="128" height="128" alt="Markview's icon">
<h1>Markview</h1>
<p class="tagline">A small, native Markdown viewer and editor for macOS.</p>
<p><a class="download-button" href="%DOWNLOAD%">Download for Mac</a></p>
<p class="meta">Version %VERSION% · macOS 14 or later · Free and MIT licensed</p>
</div>

![Markview showing a project folder, with its files in the sidebar](/shots/hero-github-light.webp#gh-light-mode-only)
![Markview showing a project folder, with its files in the sidebar](/shots/hero-github-dark.webp#gh-dark-mode-only)

Open a `.md` file and read it the way GitHub shows it: tables, code, maths and Mermaid diagrams, drawn without a web view. Press ⌘U to write it in an [editor](Editor.md) beside the page, which follows as you type; ⌘U works on this site too. Markview follows the file as it changes on disk, draws the Quick Look preview when you press Space in Finder, and keeps itself up to date.

It installs with Homebrew too:

```sh
brew install --cask dagurleo/tap/markview
```

This site is a Markview window too. Each file in the sidebar is a page, the menu at the top switches between Markview's twelve [themes](Themes.md), and <kbd>?</kbd> lists the keyboard shortcuts.

## What it reads

| Syntax | What Markview does with it |
| --- | --- |
| GitHub Flavored Markdown | Tables, task lists, footnotes and the five alerts |
| Maths | `$…$`, `$$…$$` and `math` blocks, drawn by SwaTex ([more](Maths%20and%20diagrams.md)) |
| Diagrams | Every `mermaid` diagram type, drawn by MermaidKit |
| Code | 56 languages highlighted, each block with a copy button |
| Other dialects | Obsidian callouts, `[[wiki links]]`, `==highlights==`, `:emoji:` shortcodes, MkDocs and Docusaurus admonitions |
| README HTML | `<picture>`, `<details>`, centred blocks and sized images |
| Front matter | Simple YAML, shown as a table of its keys |

## What it does

- Edits beside the page, with the page following as you type. Type `/` for a menu of things to insert.
- Follows the file as it changes on disk, and keeps your place on the page.
- Reopens each document where you left off.
- Opens [folders](Folders.md), with their Markdown files in the sidebar.
- Draws the [Quick Look](Quick%20Look.md) preview in Finder.
- Find, zoom, a Go menu of headings, Print and Export as PDF.
- Opens files from the [terminal](Terminal.md), or shows what is piped to it.
- Keeps documents harmless. Markdown links open in Markview and web links in your browser, and any other file is only shown in Finder, so a document can never launch an app or run a script.

## Limitations

- Maths is not searchable, and diagrams are not interactive.
- Long code lines wrap instead of scrolling sideways.
- HTML support covers the elements a README tends to use. Other tags are dropped and their text kept.
