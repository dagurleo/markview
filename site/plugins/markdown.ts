import { readFileSync } from "node:fs"
import type { Plugin } from "vite"

import { renderMarkdown } from "../src/lib/markdown.ts"

/**
 * Imports of `.md` files, or of any file with `?markdown` (LICENSE), give a Page, rendered here at
 * build time by src/lib/markdown.ts. With `?source` they give the Markdown itself, for the editor,
 * which loads it only when it opens. Each `replacements` key is replaced in the source first, for
 * values like the current version.
 */
export function markdown(replacements: Record<string, string>): Plugin {
  return {
    name: "markview-markdown",
    enforce: "pre",
    load(id) {
      const [file, query] = id.split("?")
      if (!file.endsWith(".md") && query !== "markdown" && query !== "source") return
      this.addWatchFile(file)
      let source = readFileSync(file, "utf8")
      for (const [key, value] of Object.entries(replacements))
        source = source.replaceAll(key, value)
      return `export default ${JSON.stringify(query === "source" ? source : renderMarkdown(source))}`
    },
  }
}
