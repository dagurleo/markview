import { readFileSync } from "node:fs"
import { defineConfig } from "vite"
import { tanstackStart } from "@tanstack/react-start/plugin/vite"
import viteReact from "@vitejs/plugin-react"

import { markdown } from "./plugins/markdown.ts"
import { palettes } from "./plugins/palettes.ts"
import { downloadURL } from "./src/site.ts"

// Markview's site. The page is a Markview window: each file in its sidebar is a page, written in
// content/ as Markdown and rendered at build time. Every page is prerendered to static HTML in
// dist/client, which a Cloudflare Worker serves as static assets (wrangler.jsonc).

// The app's version, from the repository's Info.plist, so the download links follow releases.
const plist = readFileSync(new URL("../Info.plist", import.meta.url), "utf8")
const version = /<key>CFBundleShortVersionString<\/key>\s*<string>([^<]+)<\/string>/.exec(
  plist
)?.[1]
if (!version) throw new Error("No CFBundleShortVersionString in Info.plist")

const siteServer = { host: "localhost", port: 3080, strictPort: true }

export default defineConfig({
  resolve: { tsconfigPaths: true },
  define: { __MARKVIEW_VERSION__: JSON.stringify(version) },
  plugins: [
    markdown({ "%VERSION%": version, "%DOWNLOAD%": downloadURL(version) }),
    palettes(new URL("../Native/Palette.swift", import.meta.url)),
    tanstackStart({
      prerender: { enabled: true, crawlLinks: true, autoSubfolderIndex: false },
      pages: [{ path: "/404", prerender: { enabled: true, outputPath: "/404.html" } }],
    }),
    viteReact(),
  ],
  server: siteServer,
  preview: siteServer,
})
