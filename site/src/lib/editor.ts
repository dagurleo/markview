import { EditorSelection, EditorState } from "@codemirror/state"
import type { Extension } from "@codemirror/state"
import { EditorView, drawSelection, highlightSpecialChars, keymap } from "@codemirror/view"
import type { ViewUpdate } from "@codemirror/view"
import { defaultKeymap, history, historyKeymap, indentLess, indentMore } from "@codemirror/commands"
import { HighlightStyle, indentUnit, syntaxHighlighting, syntaxTree } from "@codemirror/language"
import { markdown, markdownLanguage } from "@codemirror/lang-markdown"
import { languages } from "@codemirror/language-data"
import { Tag, styleTags, tags } from "@lezer/highlight"

import { hasEdit, setEdit, setEditorHandle } from "@/lib/edits"
import { renderMarkdown } from "@/lib/markdown"
import type { File } from "@/pages"

// The editor beside the page, loaded when it first opens. It is CodeMirror, coloured with the
// theme's roles as SourceHighlighter.swift colours Markview's editor, and it keeps Markview's
// habits: Return carries a list or quote on, Tab nests a list item, ⌘B ⌘I ⌘E ⇧⌘X mark the
// selection, and the page follows a moment after typing stops, scrolling with the editor.

// Marks Markview colours apart from the rest: list and quote marks, a link's address, and the
// text of a code block, which keeps the text colour where its language has none.
const listMark = Tag.define()
const quoteMark = Tag.define()
const linkAddress = Tag.define()
const codeBlockText = Tag.define()

const markdownTags = {
  props: [
    styleTags({
      ListMark: listMark,
      QuoteMark: quoteMark,
      "Link/URL Image/URL": linkAddress,
      "FencedCode/CodeText": codeBlockText,
    }),
  ],
}

// Theme roles, as CSS variables, so a change of theme recolours the editor with the page.
const colours = HighlightStyle.define([
  {
    tag: [tags.heading1, tags.heading2, tags.heading3, tags.heading4, tags.heading5, tags.heading6],
    color: "var(--keyword)",
    fontWeight: "bold",
  },
  // A link's colour reaches its marks and address too, so the marks' colour comes after it and
  // takes over, as it does in a heading.
  { tag: [tags.link, tags.url], color: "var(--link)" },
  { tag: [tags.processingInstruction, tags.contentSeparator, linkAddress], color: "var(--muted)" },
  { tag: listMark, color: "var(--builtin)" },
  { tag: quoteMark, color: "var(--tag)" },
  { tag: tags.emphasis, fontStyle: "italic" },
  { tag: tags.strong, fontWeight: "bold" },
  { tag: tags.strikethrough, textDecoration: "line-through" },
  { tag: [tags.monospace, tags.labelName], color: "var(--literal)" },
  { tag: tags.comment, color: "var(--comment)" },
  { tag: [tags.tagName, tags.angleBracket, tags.attributeName], color: "var(--tag)" },
  // Code in a code block, as styles.css colours highlight.js's classes on the page.
  { tag: [tags.keyword, tags.typeName], color: "var(--keyword)" },
  {
    tag: [tags.function(tags.variableName), tags.definition(tags.function(tags.variableName))],
    color: "var(--title)",
  },
  { tag: tags.className, color: "var(--title)" },
  { tag: [tags.number, tags.bool, tags.null, tags.atom, tags.meta], color: "var(--literal)" },
  { tag: [tags.string, tags.regexp, tags.attributeValue], color: "var(--string)" },
  {
    tag: [tags.standard(tags.variableName), tags.special(tags.variableName)],
    color: "var(--builtin)",
  },
])

const look = EditorView.theme({
  "&": { height: "100%", color: "var(--text)", backgroundColor: "var(--background)" },
  "&.cm-focused": { outline: "none" },
  ".cm-scroller": {
    fontFamily: "var(--mono)",
    fontSize: "13.6px",
    lineHeight: "1.55",
    overscrollBehavior: "contain",
  },
  ".cm-content": { padding: "24px 0", caretColor: "var(--text)" },
  ".cm-line": { padding: "0 20px" },
  ".cm-cursor, .cm-dropCursor": { borderLeftColor: "var(--text)", borderLeftWidth: "1.5px" },
  ".cm-selectionBackground": {
    backgroundColor: "color-mix(in srgb, var(--text) 12%, transparent) !important",
  },
  "&.cm-focused > .cm-scroller > .cm-selectionLayer .cm-selectionBackground": {
    backgroundColor: "color-mix(in srgb, var(--link) 24%, transparent) !important",
  },
})

// MARK: Lists and marks, as SourceTextView.swift does them

const listItem = /^(\s*)([-*+]|\d{1,9}[.)])(\s+)/

const columns = (space: string) =>
  [...space].reduce((sum, character) => sum + (character === "\t" ? 4 : 1), 0)

const contentColumn = (item: RegExpExecArray) =>
  columns(item[1]) + item[2].length + columns(item[3])

/** The closest list item above a line whose indentation is at most `column`. */
function itemAbove(state: EditorState, lineNumber: number, column: number) {
  for (let number = lineNumber - 1; number >= 1; number--) {
    const text = state.doc.line(number).text
    if (!text.trim()) continue
    const item = listItem.exec(text)
    // A line of an item's text is indented under it; anything at the left margin ends the list.
    if (!item) {
      if (!/^\s/.test(text)) return undefined
      continue
    }
    if (columns(item[1]) <= column) return item
  }
  return undefined
}

type SyntaxNode = { name: string; parent: SyntaxNode | null }

function inCode(state: EditorState, position: number) {
  let node: SyntaxNode | null = syntaxTree(state).resolveInner(position, 1)
  for (; node; node = node.parent) {
    if (node.name === "FencedCode" || node.name === "CodeBlock") return true
  }
  return false
}

function reindent(view: EditorView, lineNumber: number, from: string, to: string) {
  const line = view.state.doc.line(lineNumber)
  view.dispatch({
    changes: { from: line.from, to: line.from + from.length, insert: to },
    userEvent: "input.indent",
  })
}

/** Tab nests a list item under the item above, at its text; elsewhere it puts in four spaces. */
function tab(view: EditorView) {
  const { state } = view
  const { from, to } = state.selection.main
  const line = state.doc.lineAt(from)
  if (line.number !== state.doc.lineAt(to).number) return indentMore(view)
  const item = inCode(state, from) ? null : listItem.exec(line.text)
  if (!item) {
    view.dispatch(state.replaceSelection("    "), { scrollIntoView: true, userEvent: "input" })
    return true
  }
  const parent = itemAbove(state, line.number, columns(item[1]))
  if (parent && contentColumn(parent) > columns(item[1]))
    reindent(view, line.number, item[1], " ".repeat(contentColumn(parent)))
  return true
}

/** Shift-Tab takes a list item out to the item it was nested under. */
function untab(view: EditorView) {
  const { state } = view
  const { from, to } = state.selection.main
  const line = state.doc.lineAt(from)
  const item = listItem.exec(line.text)
  if (line.number !== state.doc.lineAt(to).number || !item) return indentLess(view)
  const column = columns(item[1])
  if (column > 0)
    reindent(view, line.number, item[1], itemAbove(state, line.number, column - 1)?.[1] ?? "")
  return true
}

/**
 * Puts a mark either side of the selection, or takes it away if it is there already, just inside
 * the selection or just outside it. Stars are counted, so italic and bold go on and off each
 * other: an odd number either side is italic, two or more bold.
 */
function toggle(mark: string) {
  return (view: EditorView) => {
    const { doc } = view.state
    const { from, to } = view.state.selection.main
    const character = mark[0]
    const length = mark.length
    const star = character === "*"
    const run = (position: number, step: 1 | -1) => {
      let found = 0
      for (let at = step > 0 ? position : position - 1; at >= 0 && at < doc.length; at += step) {
        if (doc.sliceString(at, at + 1) !== character) break
        found++
      }
      return found
    }
    const marked = (before: number, after: number) =>
      star
        ? length === 1
          ? Math.min(before, after) % 2 === 1
          : Math.min(before, after) >= 2
        : Math.min(before, after) >= 1

    const selected = doc.sliceString(from, to)
    const [before, after] = [run(from, -1), run(to, 1)]
    const outside = star ? [before, after] : [before >= length ? 1 : 0, after >= length ? 1 : 0]
    if (marked(outside[0], outside[1]) && (star || doc.sliceString(from - length, from) === mark)) {
      view.dispatch({
        changes: [
          { from: from - length, to: from },
          { from: to, to: to + length },
        ],
        selection: EditorSelection.range(from - length, to - length),
        userEvent: "input",
      })
      return true
    }
    const inner = selected.length - selected.replace(new RegExp(`^\\${character}+`), "").length
    const innerEnd = selected.length - selected.replace(new RegExp(`\\${character}+$`), "").length
    if (
      selected.length >= 2 * length &&
      inner < selected.length &&
      (star ? marked(inner, innerEnd) : selected.startsWith(mark) && selected.endsWith(mark))
    ) {
      const unmarked = selected.slice(length, selected.length - length)
      view.dispatch({
        changes: { from, to, insert: unmarked },
        selection: EditorSelection.range(from, from + unmarked.length),
        userEvent: "input",
      })
      return true
    }
    view.dispatch({
      changes: { from, to, insert: mark + selected + mark },
      selection: EditorSelection.range(from + length, to + length),
      userEvent: "input",
    })
    return true
  }
}

// MARK: The editor

let view: EditorView | undefined
let file: File | undefined
let focusOnShow = false
/** Each page's editor, kept for the tab's life, so its edits, selection and undo stay. */
const states = new Map<string, EditorState>()
/** Each page's Markdown as published, to tell an edited page from one that isn't. */
const originals = new Map<string, string>()
let renderTimer: ReturnType<typeof setTimeout> | undefined

const extensions: Extension = [
  history(),
  drawSelection(),
  highlightSpecialChars(),
  EditorView.lineWrapping,
  // Four spaces, Markview's default, for ⇧Tab and Tab over several lines.
  indentUnit.of("    "),
  markdown({
    base: markdownLanguage,
    codeLanguages: languages,
    extensions: markdownTags,
    completeHTMLTags: false,
  }),
  syntaxHighlighting(colours),
  look,
  EditorView.contentAttributes.of({ "aria-label": "Markdown" }),
  keymap.of([
    { key: "Tab", run: tab, shift: untab },
    { key: "Mod-b", run: toggle("**") },
    { key: "Mod-i", run: toggle("*") },
    { key: "Mod-e", run: toggle("`") },
    { key: "Mod-Shift-x", run: toggle("~~") },
    // ⌘U shows and hides the editor, as in Markview, rather than undoing a selection.
    ...historyKeymap.filter((binding) => binding.key !== "Mod-u"),
    ...defaultKeymap.filter((binding) => binding.key !== "Mod-u"),
  ]),
  EditorView.updateListener.of(onUpdate),
]

function onUpdate(update: ViewUpdate) {
  if (update.view !== view || !file) return
  states.set(file.path, update.state)
  if (update.docChanged) {
    clearTimeout(renderTimer)
    renderTimer = setTimeout(render, 150)
  }
}

/** Draws the page from the editor's Markdown, as it is now. */
function render() {
  clearTimeout(renderTimer)
  renderTimer = undefined
  if (!view || !file) return
  const line = view.state.doc.lineAt(view.state.selection.main.head).number
  publish(file.path, view.state.doc.toString())
  requestAnimationFrame(() => pageShows(line))
}

function publish(path: string, source: string) {
  const page = renderMarkdown(source, { sourceLines: true })
  setEdit(path, { page, edited: source !== originals.get(path) })
}

/** Makes the editor inside `parent`, until the function it returns is called. */
export function mountEditor(parent: HTMLElement) {
  const made = new EditorView({ parent })
  view = made
  focusOnShow = true
  made.scrollDOM.addEventListener("scroll", onEditorScroll, { passive: true })
  window.addEventListener("scroll", onPageScroll, { passive: true })
  setEditorHandle({ reveal, topLine })
  return () => {
    if (renderTimer) render()
    made.scrollDOM.removeEventListener("scroll", onEditorScroll)
    window.removeEventListener("scroll", onPageScroll)
    setEditorHandle(undefined)
    made.destroy()
    if (view === made) view = undefined
    file = undefined
  }
}

/** Shows a page's Markdown, as published or as last edited in this tab. */
export async function show(next: File) {
  if (!view || next === file) return
  if (renderTimer) render()
  file = next
  let state = states.get(next.path)
  if (!state) {
    const source = await next.source()
    // The editor may have closed, or moved on to another page, while the Markdown loaded.
    if (!showing(next)) return
    originals.set(next.path, source)
    state = EditorState.create({ doc: source, extensions })
    states.set(next.path, state)
  }
  view.setState(state)
  // The page's blocks need their lines for the two to scroll together.
  if (!hasEdit(next.path)) publish(next.path, state.doc.toString())
  const focus = focusOnShow
  focusOnShow = false
  requestAnimationFrame(() => {
    if (!view || file !== next) return
    editorFollowsPage()
    if (!focus) return
    // The insertion point goes where the page was being read, unless it is in view already.
    const { from, to } = view.viewport
    const head = view.state.selection.main.head
    if (head < from || head > to) {
      const top = view.lineBlockAtHeight(view.scrollDOM.scrollTop).from
      view.dispatch({ selection: { anchor: top } })
    }
    view.focus()
  })
}

function showing(page: File) {
  return view !== undefined && file === page
}

/** Puts the page back as published. Revert can be undone, like any other edit. */
export function revert() {
  const original = file && originals.get(file.path)
  if (!view || original === undefined) return
  view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: original } })
  render()
}

function reveal(line: number) {
  if (!view || line > view.state.doc.lines) return
  editorFollowsPage()
  const anchor = view.state.doc.line(line).from
  view.dispatch({
    selection: { anchor },
    effects: EditorView.scrollIntoView(anchor, { y: "nearest", yMargin: 24 }),
  })
  view.focus()
}

function topLine() {
  if (!view) return 1
  return view.state.doc.lineAt(view.lineBlockAtHeight(view.scrollDOM.scrollTop).from).number
}

// MARK: Scrolling together

// The page's blocks carry their lines (data-line), so each block's place on the page pairs with
// its line's place in the editor, and anything between two of them is interpolated. A position is
// a scroll offset: a line rests at the top of the editor when its scrollTop is the line's top, as
// a block rests at the top of the page when scrollY is its distance below the page's first.

const NARROW = "(max-width: 820px)"
let expectedEditor: number | undefined
let expectedPage: number | undefined
let frame = 0

type Anchor = { editor: number; page: number }

function anchors(): Anchor[] {
  const article = document.querySelector<HTMLElement>(".page .markdown")
  if (!view || !article) return []
  const { doc } = view.state
  const scroller = view.scrollDOM
  const maxEditor = scroller.scrollHeight - scroller.clientHeight
  const maxPage = document.documentElement.scrollHeight - innerHeight
  const top = article.getBoundingClientRect().top
  const found: Anchor[] = [{ editor: 0, page: 0 }]
  for (const block of article.querySelectorAll<HTMLElement>("[data-line]")) {
    const line = Number(block.dataset.line)
    const rect = block.getBoundingClientRect()
    if (!(line >= 1 && line <= doc.lines) || rect.height === 0) continue
    found.push({ editor: view.lineBlockAt(doc.line(line).from).top, page: rect.top - top })
  }
  found.push({ editor: maxEditor, page: maxPage })
  // Only places both sides can scroll to, rising on both: a side that can't scroll would otherwise
  // pair its one place with all of the other's.
  const kept: Anchor[] = []
  for (const anchor of found) {
    const last = kept.at(-1)
    if (anchor.editor > maxEditor || anchor.page > maxPage) continue
    if (last && (anchor.editor <= last.editor || anchor.page <= last.page)) continue
    kept.push(anchor)
  }
  return kept
}

function convert(position: number, from: keyof Anchor, to: keyof Anchor) {
  const list = anchors()
  let index = list.length - 1
  while (index > 0 && list[index][from] > position) index--
  const start = list.at(index)
  const end = list.at(index + 1)
  if (!start) return undefined
  if (!end || end[from] === start[from]) return start[to]
  return start[to] + ((position - start[from]) / (end[from] - start[from])) * (end[to] - start[to])
}

/**
 * After an edit the page keeps still, as everything above the edit is as it was. Only when the
 * edited block is out of sight does the page move, bringing it level with its line in the editor.
 */
function pageShows(line: number) {
  const article = document.querySelector<HTMLElement>(".page .markdown")
  if (!view || !article || matchMedia(NARROW).matches) return
  let block: HTMLElement | undefined
  for (const each of article.querySelectorAll<HTMLElement>("[data-line]")) {
    if (Number(each.dataset.line) > line) break
    block = each
  }
  if (!block) return
  const rect = block.getBoundingClientRect()
  const titlebar = document.querySelector(".titlebar")?.getBoundingClientRect().bottom ?? 0
  if (rect.bottom > titlebar && rect.top < innerHeight) return
  const { doc } = view.state
  const written = doc.line(Math.min(Number(block.dataset.line), doc.lines))
  window.scrollBy(0, rect.top - (view.lineBlockAt(written.from).top + view.documentTop))
  expectedPage = scrollY
}

function pageFollowsEditor() {
  if (!view || matchMedia(NARROW).matches) return
  const y = convert(view.scrollDOM.scrollTop, "editor", "page")
  if (y === undefined) return
  window.scrollTo(0, y)
  expectedPage = scrollY
}

function editorFollowsPage() {
  if (!view || matchMedia(NARROW).matches) return
  const y = convert(scrollY, "page", "editor")
  if (y === undefined) return
  view.scrollDOM.scrollTop = y
  expectedEditor = view.scrollDOM.scrollTop
}

/** Brings the other side level once a frame, whichever was scrolled last. */
function follow(leader: () => void) {
  cancelAnimationFrame(frame)
  frame = requestAnimationFrame(leader)
}

// A scroll made by following is not followed back.
function onEditorScroll() {
  const expected = expectedEditor
  expectedEditor = undefined
  if (view && expected !== undefined && Math.abs(view.scrollDOM.scrollTop - expected) < 2) return
  follow(pageFollowsEditor)
}

function onPageScroll() {
  const expected = expectedPage
  expectedPage = undefined
  if (expected !== undefined && Math.abs(scrollY - expected) < 2) return
  follow(editorFollowsPage)
}
