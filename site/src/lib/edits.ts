import { useSyncExternalStore } from "react"

import type { Page } from "@/lib/files"

// What the editor has made of the site's pages. Edits last as long as the tab, as the site saves
// nothing: a reload brings back the pages as published.

export type Edit = {
  /** The page drawn from the editor's Markdown, each block marked with its line. */
  page: Page
  /** Whether the Markdown differs from the page as published. */
  edited: boolean
}

/** What the rest of the site asks of the editor while it is open (src/lib/editor.ts). */
export type EditorHandle = {
  /** Puts the insertion point at a line, scrolled level with its block on the page. */
  reveal: (line: number) => void
  /** The line at the top of the editor. */
  topLine: () => number
}

const edits = new Map<string, Edit>()
const listeners = new Set<() => void>()
let handle: EditorHandle | undefined

function subscribe(listener: () => void) {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

export function setEdit(path: string, edit: Edit) {
  edits.set(path, edit)
  for (const listener of listeners) listener()
}

export function hasEdit(path: string) {
  return edits.has(path)
}

/** The edit of the page at a path, if the editor has been open on it. */
export function useEdit(path: string | undefined): Edit | undefined {
  return useSyncExternalStore(
    subscribe,
    () => (path === undefined ? undefined : edits.get(path)),
    () => undefined
  )
}

export function setEditorHandle(next: EditorHandle | undefined) {
  handle = next
}

export function editorHandle() {
  return handle
}
