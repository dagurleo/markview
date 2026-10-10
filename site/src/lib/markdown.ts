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

// Imported by path, not as @/lib/files: plugins/markdown.ts runs this at build time, outside Vite.
import { pathForFile } from "./files.ts"
import type { Page } from "./files.ts"

// The site's pages are Markdown, turned into HTML at build time (plugins/markdown.ts), so readers
// download no Markdown or highlighting code. The editor loads this same renderer when it opens,
// so an edited page comes out as the build would have made it. The output follows Markview's own
// rendering: GitHub's alerts, heading anchors, highlight.js classes (coloured per theme in
// styles.css, as HighlightEngine.swift does) and a copy button on each code block. Links to other
// .md files become the site's routes.

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

const blocks = new Set([
  "paragraph",
  "heading",
  "code",
  "blockquote",
  "listItem",
  "tableRow",
  "thematicBreak",
])

/**
 * Marks each block with the line of the Markdown it starts on, as `data-line`, so the editor and
 * the page can scroll together, as Markview's do. Only the editor asks for it.
 */
function remarkSourceLines() {
  return (tree: MdastRoot) => {
    visit(tree, (node) => {
      if (!blocks.has(node.type) || !node.position) return
      node.data = {
        ...node.data,
        hProperties: { ...node.data?.hProperties, dataLine: node.position.start.line },
      }
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

function processor(sourceLines: boolean) {
  return unified()
    .use(remarkParse)
    .use(remarkGfm)
    .use(remarkAlerts)
    .use(sourceLines ? [remarkSourceLines] : [])
    .use(remarkRehype, { allowDangerousHtml: true })
    .use(rehypeRaw)
    .use(rehypeSlug)
    .use(rehypeHighlight, { detect: false, plainText: ["math", "mermaid", "text"] })
    .use(rehypeCodeBlocks)
    .use(rehypeLinks)
}

const processors = { page: processor(false), editor: processor(true) }

/** A page from its Markdown. `sourceLines` marks each block with its line, for the editor. */
export function renderMarkdown(source: string, { sourceLines = false } = {}): Page {
  const pipeline = sourceLines ? processors.editor : processors.page
  const tree = pipeline.runSync(pipeline.parse(source))
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
