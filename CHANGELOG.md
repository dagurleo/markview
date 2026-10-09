# Changes

## 0.5.0 (not released yet)

- An editor beside the page: View > Show Editor (⌘U) opens the Markdown as written,
  coloured in the theme, and the page follows a moment after you stop typing. Documents
  still open as pages to read. File > New (⌘N) starts a new document, with the editor
  open. Save (⌘S), Save As… and Revert to Saved write the file only when asked; unsaved
  edits are kept aside every few seconds and come back after a crash, and a file is
  written back in the encoding, byte order mark and line endings it had. If another app
  changes the file under unsaved edits, a bar above the editor asks which to keep.
  Following a link or going back from unsaved edits asks first. View Source is gone; the
  editor shows the same.
- A short file in Latin-1 is no longer read as UTF-8 with its accented letters replaced.

## 0.4.0

- Folders open too, from File > Open…, the `markview` command, or by dropping one on the
  Dock icon or a window. The window starts at the folder's README and lists its Markdown
  files in the sidebar, which now has Files and Contents tabs (View > Show Sidebar).
- Links to other Markdown files open in the same window, as in a browser; ⌘-click
  opens a new one. Go > Back (⌘[) and Forward (⌘]), or a mouse's side buttons, return
  to the exact place left, also after a jump to a heading.
- Clicking a picture shows it full size in a Quick Look panel, and clicking a Mermaid
  diagram shows it as a PDF that stays sharp however far it is zoomed.
- Coming from 0.2.0? Version 0.3.0 added an outline of the headings, reopening documents
  where they were left, a copy button on code blocks, 20 more highlighted languages, the
  `markview` command and more; its notes are on the 0.3.0 release.

## 0.3.0

- An outline of the document's headings beside the page: View > Show Outline (⌃⌘S). It
  marks the section being read, and clicking a heading goes to it.
- Documents reopen where they were last read.
- Pointing at a link shows where it leads in the corner of the window. Code blocks have a
  copy button, and a heading's context menu has Copy Link to Heading.
- A `markview` command opens files from a terminal, or shows Markdown piped to it.
- READMEs' images for light and dark windows show the right one, and switch with the
  appearance: `<picture>` elements with `prefers-color-scheme` sources, and images marked
  `#gh-light-mode-only` or `#gh-dark-mode-only`, of which only one now shows.
- A file in Latin-1 or another older encoding no longer turns garbled when it changes on disk.
- Images from the web stay in place when the page is shown again, after a save or a change
  of settings, instead of being fetched anew.
- Code in 20 more languages is highlighted, among them Dockerfile, PowerShell, Scala, Dart,
  Haskell, Elixir, Groovy and Gradle, Protobuf, Nginx and LaTeX.
- Front matter that is simple YAML shows as a table of its keys and values, as on GitHub.
- Go > Next Heading (⌥⌘↓) and Previous Heading (⌥⌘↑) step through the document.
- Links to headings far down a large document now land on the heading rather than a
  screen short of it.

## 0.2.0

- Settings (⌘,) in the Markview menu. Choose one of twelve themes (GitHub, Solarized,
  One, Monokai, Dracula, Nord, Tokyo Night, Catppuccin, Gruvbox, Ayu, Rosé Pine or Paper,
  each with a light and a dark side), light or dark
  whatever the system shows, the text size, the text and code fonts, the line length
  and the line spacing. Changes show at once, in Quick Look previews too, and printing
  uses the theme's light colours. General settings turn automatic update checks on or
  off and make Markview the default Markdown viewer.
- Tables keep their natural width, and pictures shrink to fit, in a window narrower
  than the text column.

## 0.1.1

- Markview now updates itself. It asks on its second launch whether to check for
  updates automatically, and Check for Updates… is in the Markview menu.
- Diagrams drawn with box-drawing characters no longer wrap and fall apart; they
  shrink to fit the column instead.
- Tables with empty cells keep each cell in its column, and text after a table no
  longer touches its bottom edge.

## 0.1.0

- First release.
