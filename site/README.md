# Markview's site

The site is a Markview window. Each file in its sidebar is a page, each page is Markdown drawn in
Markview's own styles, and the menus at the top switch between the app's twelve themes. TanStack
Start prerenders every page to static HTML, and a Cloudflare Worker serves the files.

```sh
bun install
bun run dev       # http://localhost:3080
bun run build     # prerenders every page into dist/client
bun run deploy    # builds, then runs wrangler deploy
```

`bun run lint`, `bun run typecheck` and `bun run check` (formatting) should pass before a deploy.

- `content/` holds the pages as Markdown. A file's name is its name in the sidebar and its
  address: `Quick Look.md` is `/quick-look`. List a new file in `src/pages.ts` to put it in the
  sidebar. The changelog and licence pages are the repository's own `CHANGELOG.md` and `LICENSE`.
- `src/lib/markdown.ts` turns the Markdown into HTML, and `plugins/markdown.ts` runs it at build
  time: GitHub's alerts, heading anchors, highlight.js classes (coloured per theme in
  `src/styles.css`, as `HighlightEngine.swift` colours them), a copy button on each code block,
  and links between `.md` files turned into the site's links. `%VERSION%` and `%DOWNLOAD%` become
  the version in `../Info.plist` and the address of its disk image, so the download links follow
  each release.
- Edit (or E, or ⌘U) opens an editor beside the page, as in the app. `src/lib/editor.ts` is
  CodeMirror, coloured with the theme's roles as `SourceHighlighter.swift` colours the app's
  editor. It loads, with the renderer above, only when the editor first opens, and the page's
  Markdown comes from an import ending in `?source`. Edits last until the tab is closed or
  reloaded (`src/lib/edits.ts`); nothing is saved.
- `plugins/palettes.ts` reads `../Native/Palette.swift`, so the themes are the app's own. A
  picture can show in one appearance only, as on GitHub: end its address with
  `#gh-light-mode-only` or `#gh-dark-mode-only`.
- `public/shots` holds the screenshots. `shots/shoot.sh` takes them with the app's snapshot hooks
  (build the app first); the documents they show are in `shots/`. It passes every setting as a
  launch argument, so your own settings are neither used nor changed.

## Deploying

`wrangler.jsonc` deploys the Worker as `markview-site` on workers.dev, serving `dist/client` as
static assets with no server code. Log in once with `bunx wrangler login`. A custom domain is a
`routes` entry with `"custom_domain": true`.
