import { readFileSync } from "node:fs"
import type { Plugin } from "vite"
import { unified } from "unified"
import remarkParse from "remark-parse"
import remarkGfm from "remark-gfm"
import remarkRehype from "remark-rehype"
import rehypeRaw from "rehype-raw"
import rehypeSlug from "rehype-slug"
import rehypeHighlight from "rehype-highlight"
import rehypeStringify from "rehype-stringify"
import { SKIP, visit } from "unist-util-visit"
import { toString } from "hast-util-to-string"
import type { Root as MdastRoot } from "mdast"
import type { Element, Root as HastRoot } from "hast"

import { pathForFile } from "../src/lib/files.ts"
import type { Page } from "../src/lib/files.ts"

// The site's pages are Markdown files, turned into HTML here at build time, so visitors download
// no Markdown or highlighting code. The output follows Markview's own rendering: GitHub's alerts,
// heading anchors, highlight.js classes (coloured per theme in styles.css, as HighlightEngine.swift
// does) and a copy button on each code block. Links to other .md files become the site's routes.

const alertTitles: Record<string, string> = {
  NOTE: "Note",
  TIP: "Tip",
  IMPORTANT: "Important",
  WARNING: "Warning",
  CAUTION: "Caution",
}

/** `> [!NOTE]` blockquotes become alerts with a coloured title. */
function remarkAlerts() {
  return (tree: MdastRoot) => {
    visit(tree, "blockquote", (node) => {
      const first = node.children.at(0)
      if (first?.type !== "paragraph") return
      const text = first.children.at(0)
      if (text?.type !== "text") return
      const marker = /^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*/.exec(text.value)
      if (!marker) return
      const kind = marker[1]
      text.value = text.value.slice(marker[0].length)
      if (!text.value) first.children.shift()
      if (first.children.length === 0) node.children.shift()
      node.data = {
        hName: "div",
        hProperties: { className: ["alert", `alert-${kind.toLowerCase()}`] },
      }
      node.children.unshift({
        type: "paragraph",
        data: { hProperties: { className: ["alert-title"] } },
        children: [{ type: "text", value: alertTitles[kind] }],
      })
    })
  }
}

/** Wraps each code block with a copy button, as Markview puts one on its code blocks. */
function rehypeCodeBlocks() {
  return (tree: HastRoot) => {
    visit(tree, "element", (node, index, parent) => {
      if (node.tagName !== "pre" || !parent || index === undefined) return
      const wrapper: Element = {
        type: "element",
        tagName: "div",
        properties: { className: ["code-block"] },
        children: [
          node,
          {
            type: "element",
            tagName: "button",
            properties: { type: "button", className: ["copy"] },
            children: [{ type: "text", value: "Copy" }],
          },
        ],
      }
      parent.children[index] = wrapper
      return [SKIP, index + 1]
    })
  }
}

/** Links to Markdown files beside this one point at their pages; pictures load lazily. */
function rehypeLinks() {
  return (tree: HastRoot) => {
    visit(tree, "element", (node) => {
      if (node.tagName === "a" && typeof node.properties.href === "string") {
        const [target, anchor] = node.properties.href.split("#")
        if (/^(?![a-z]+:)[^/]+\.md$/i.test(decodeURI(target)) || target === "LICENSE") {
          node.properties.href = pathForFile(decodeURI(target)) + (anchor ? `#${anchor}` : "")
        }
      }
      if (node.tagName === "img") {
        node.properties.loading = "lazy"
        node.properties.decoding = "async"
      }
    })
  }
}

const processor = unified()
  .use(remarkParse)
  .use(remarkGfm)
  .use(remarkAlerts)
  .use(remarkRehype, { allowDangerousHtml: true })
  .use(rehypeRaw)
  .use(rehypeSlug)
  .use(rehypeHighlight, { detect: false, plainText: ["math", "mermaid", "text"] })
  .use(rehypeCodeBlocks)
  .use(rehypeLinks)

export function renderMarkdown(source: string): Page {
  const tree = processor.runSync(processor.parse(source))
  let title = ""
  let description = ""
  const headings: Page["headings"] = []
  visit(tree, "element", (node, _index, parent) => {
    const level = /^h([1-3])$/.exec(node.tagName)
    if (level) {
      const text = toString(node)
      if (level[1] === "1" && !title) title = text
      else headings.push({ depth: Number(level[1]), id: String(node.properties.id ?? ""), text })
    }
    // The first plain paragraph describes the page, for search engines and link previews.
    if (node.tagName === "p" && !description && parent?.type === "root") {
      description = toString(node).replace(/\s+/g, " ").trim()
    }
  })
  return { title, description, headings, html: unified().use(rehypeStringify).stringify(tree) }
}

/**
 * Imports of `.md` files, or of any file with `?markdown` (LICENSE), give a Page. Each
 * `replacements` key is replaced in the source first, for values like the current version.
 */
export function markdown(replacements: Record<string, string>): Plugin {
  return {
    name: "markview-markdown",
    enforce: "pre",
    load(id) {
      const [file, query] = id.split("?")
      if (!file.endsWith(".md") && query !== "markdown") return
      this.addWatchFile(file)
      let source = readFileSync(file, "utf8")
      for (const [key, value] of Object.entries(replacements))
        source = source.replaceAll(key, value)
      return `export default ${JSON.stringify(renderMarkdown(source))}`
    },
  }
}
