# Markview

A small native macOS viewer for Markdown. Open a `.md` file and it is shown as a
read-only page that follows the file as it changes on disk. Press Space on a
Markdown file in Finder and the same renderer draws the Quick Look preview.

![Markview showing its sample document, with a search under way](sample/screenshot.png)

## Install

```sh
brew install --cask dagurleo/tap/markview
```

or download `Markview-<version>.dmg` from [Releases](https://github.com/dagurleo/markview/releases)
and drag Markview to Applications. It is signed and notarized, and runs on macOS 14
or later. Open it once so that macOS picks up its Quick Look preview; "Make Default
Markdown Viewer" in the Markview menu has Markdown files open in it.

## What it does

- Renders Markdown with Foundation's parser and TextKit, with no web view:
  headings, lists and task lists, tables, blockquotes and GitHub alerts, code
  blocks highlighted by highlight.js running in JavaScriptCore, images (local and
  remote), front matter, and the HTML a README tends to use (centred blocks,
  `<img>` with a size, `<details>`, HTML tables, inline tags). Badge links
  (`[![alt](image)](url)`) work.
- Draws math and diagrams natively, in the light or dark colours of the window:
  - Math is TeX between `$…$`, `$$…$$` or in a ```` ```math ```` block, as on GitHub,
    drawn by SwaTex, a Swift version of KaTeX with KaTeX's fonts, as the document
    renders: about 25 µs a formula. Equations number on through the document, and
    `\ce` writes chemistry.
  - ```` ```mermaid ```` blocks are drawn by MermaidKit: every Mermaid diagram type,
    in a few milliseconds each, just after the text shows.
  - A formula or diagram that cannot be drawn shows as written. Copying a drawn one
    copies its Markdown.
- Reads the common dialects too: footnotes, `:emoji:` shortcodes, `[[wiki links]]`
  resolved against the files around the document, `==highlights==`, Obsidian
  callouts with titles and kinds beyond GitHub's five, `{#custom-id}` on headings,
  and `:::note` or `!!! note` admonitions. Files in Latin-1 or with a byte order
  mark are read correctly.
- Keeps documents harmless. Links to other Markdown files open in Markview, web
  links go to the browser, and any other local file is only revealed in Finder,
  so a document can never launch an app or run a script. Files dropped on a
  window follow the same rules.
- Quick Look preview through an app extension. Links in the preview go through a
  small XPC helper because the extension's sandbox cannot open them itself.
- Find (⌘F), zoom (⌘+ ⌘- ⌘0), a Go menu listing the headings, View Source (⌘U),
  Print (⌘P) and Export as PDF (⇧⌘E), Open With, Reveal in Finder (⇧⌘R), Copy
  Path (⌥⌘C), Open Recent, and "Make Default Markdown Viewer" in the app menu.
  Markdown files show Markview's document icon once it is the default app.
- Large files show their beginning at once and finish rendering in the
  background.

## Limitations

- Math is not searchable, and diagrams are not interactive.
- Diagrams follow Mermaid's syntax but MermaidKit's look, not Mermaid's. A few
  things come out imperfectly: hexagon nodes, thick arrows, class stereotypes and
  multiplicities, and dates on a Gantt chart's axis.
- Long code lines wrap (the continuation is indented) instead of scrolling sideways.
- HTML support covers the common README elements; other tags are dropped and
  their text kept.

## Building

```sh
./build.sh            # builds build/Markview.app
./build.sh install    # copies it to /Applications and registers the Quick Look extension
```

Only the command line tools are needed: `build.sh` calls `swiftc` directly, there
is no Xcode project and no package. The first build takes two minutes longer, to
compile the vendored MermaidKit and SwaTex, which are then kept in `build/modules`.
The app runs on macOS 14 or later. `build.sh` signs it ad hoc, which is enough to run
it on the machine that built it.

## Releasing

```sh
scripts/release.sh
```

builds the app signed with a Developer ID certificate from the keychain (the newest,
or the one whose SHA-1 hash is in `IDENTITY`) and the hardened runtime, has Apple
notarize it and staples the ticket to it. It writes `build/release/Markview-<version>.zip`
for the Homebrew cask and `Markview-<version>.dmg` for downloading, both notarized,
with their SHA-256. It needs notarization credentials stored once in the keychain:

```sh
xcrun notarytool store-credentials markview --apple-id <Apple ID> --team-id <team ID>
```

The version is `CFBundleShortVersionString` in `Info.plist`; the Quick Look extension
and its service take theirs from it.

## Layout

| Folder | Contents |
|---|---|
| `Sources/` | The app's shell: app delegate and menu, document, file watcher, link rules |
| `Native/` | The renderer: `MarkdownView`, `NativeRenderer`, `HighlightEngine`, `Math`, `Diagrams`, `Theme`, the window controller and the Quick Look controller |
| `QuickLook/` | The extension's plist and entitlements, and the `LinkOpener` XPC service |
| `Resources/` | Icons, and the vendored highlight.js and emoji list. The Quick Look extension has its own copy of the `vendor` folder |
| `Vendor/MermaidKit/` | [MermaidKit](https://github.com/2389-research/MermaidKit) 2.2.0 (85fdc08), which draws diagrams: its `MermaidLayout` and `MermaidRender` sources as released, less `MermaidView.swift`, which needs SwiftUI. To update, copy both folders from a new release and drop that file again |
| `Vendor/SwaTex/` | [SwaTex](https://github.com/PhraseHQ/SwaTex) 0.5.0 (2b38d0b), which draws math: its `SwaTex` sources less the docs, and from `SwaTexRender` only `DisplayListRenderer.swift`, `KaTeXFontProvider.swift` and the fonts. Markview's changes are marked `Markview:` in the code: a `Mutex` that works on macOS 14, fonts read from the app, and KaTeX's `align` spacing, `\dots`, `\tag` text and placement, and equation numbering. To update, copy the same files from a new release and carry over what `grep -rn Markview: Vendor/SwaTex` finds |
| `scripts/` | `release.sh`, which builds, notarizes and zips a release, and `make-icon.swift`, which draws the app and document icons |
| `sample/` | Documents to try: `sample.md` has a bit of everything; `text.md`, `images.md`, `tables.md`, `code.md`, `html.md`, `extensions.md`, `math.md` and `diagrams.md` each show one kind of element |

## Scripted checks

The app reads a few environment variables so a shell script can
exercise it (see `runSmokeTestHooks` in `Native/ViewerWindowController.swift`):

```sh
MARKVIEW_SNAPSHOT=/tmp/page.png build/Markview.app/Contents/MacOS/Markview sample/sample.md
```

renders the page to a PNG, prints the open documents and quits after
`MARKVIEW_SNAPSHOT_DELAY` seconds (default 0.5). `MARKVIEW_CHROME_SNAPSHOT`
captures the whole window, `MARKVIEW_APPEARANCE=light|dark` overrides the
appearance, `MARKVIEW_FIND=<text>` runs a find, `MARKVIEW_ANCHOR=<slug>` jumps to a
heading, `MARKVIEW_LINK=<text>` follows the first link containing the text,
`MARKVIEW_SOURCE=1` shows the source instead of the page and `MARKVIEW_PDF=<path>`
also exports the page as a PDF.
`-pageZoom 1.5` after the file argument sets the zoom for that launch. The Quick
Look extension can be tried with `qlmanage -p file.md` once the app is installed.

## Licence

Markview is under the MIT licence; see [LICENSE](LICENSE). It is built with
[SwaTex](https://github.com/PhraseHQ/SwaTex) (MIT) and KaTeX's fonts (SIL Open Font
Licence 1.1), [MermaidKit](https://github.com/2389-research/MermaidKit) (MIT),
[highlight.js](https://highlightjs.org) (BSD 3-Clause) and the shortcode table of
[gemoji](https://github.com/github/gemoji) (MIT). Their licences are next to them in
`Vendor/` and `Resources/vendor/`, and the app's About window gives them all in full.
