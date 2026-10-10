/// <reference types="vite/client" />

// Markdown files are rendered at build time by plugins/markdown.ts.
declare module "*.md" {
  import type { Page } from "@/lib/files"

  const page: Page
  export default page
}

declare module "*?markdown" {
  import type { Page } from "@/lib/files"

  const page: Page
  export default page
}

// The Markdown of a page, for the editor (plugins/markdown.ts).
declare module "*?source" {
  const source: string
  export default source
}

// Markview's themes, from Native/Palette.swift (plugins/palettes.ts).
declare module "virtual:palettes" {
  import type { Palette } from "@/lib/palettes"

  const palettes: Palette[]
  export default palettes
}

/** The app's version, from the repository's Info.plist (vite.config.ts). */
declare const __MARKVIEW_VERSION__: string
