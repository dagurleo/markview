import { useEffect, useRef, useState } from "react"

import type * as EditorModule from "@/lib/editor"
import type { File } from "@/pages"

export const MIN_EDITOR_WIDTH = 280

/** Loads the editor's code, or finds it loaded. Edit calls it on hover, to open without a wait. */
export const loadEditor = () => import("@/lib/editor")

/**
 * The editor beside the page, as ⌘U opens it in Markview. CodeMirror and the Markdown renderer
 * load the first time it opens (src/lib/editor.ts), so reading the site downloads neither. A bar
 * above it says the edits stay here, with a button to put an edited page back. It is there from
 * the start, so the first keystroke doesn't move the editor down to make room for it.
 */
export function Editor({
  file,
  edited,
  width,
  onResize,
}: {
  file: File
  edited: boolean
  width: number | undefined
  onResize: (width: number) => void
}) {
  const host = useRef<HTMLDivElement>(null)
  const [editor, setEditor] = useState<typeof EditorModule>()

  useEffect(() => {
    let cancelled = false
    let unmount: (() => void) | undefined
    void loadEditor().then((module) => {
      if (cancelled || !host.current) return
      unmount = module.mountEditor(host.current)
      setEditor(module)
    })
    return () => {
      cancelled = true
      unmount?.()
    }
  }, [])

  useEffect(() => {
    void editor?.show(file)
  }, [editor, file])

  return (
    <section id="editor" className="editor" aria-label="Editor">
      <p className="editor-bar">
        {"Edits made here aren't saved."}
        <button type="button" disabled={!edited} onClick={() => editor?.revert()}>
          Revert
        </button>
      </p>
      <div ref={host} className="editor-host" />
      <Divider width={width} onResize={onResize} />
    </section>
  )
}

/** The line between the editor and the page, dragged (or moved with the arrow keys) to resize. */
function Divider({
  width,
  onResize,
}: {
  width: number | undefined
  onResize: (width: number) => void
}) {
  const fit = (value: number) =>
    Math.round(Math.max(MIN_EDITOR_WIDTH, Math.min(value, innerWidth - MIN_EDITOR_WIDTH)))

  const onPointerDown = (event: React.PointerEvent<HTMLDivElement>) => {
    if (event.button !== 0) return
    event.preventDefault()
    const divider = event.currentTarget
    const left = divider.parentElement?.getBoundingClientRect().left ?? 0
    divider.setPointerCapture(event.pointerId)
    const move = (moved: PointerEvent) => onResize(fit(moved.clientX - left))
    const end = () => {
      divider.removeEventListener("pointermove", move)
      divider.removeEventListener("pointerup", end)
      divider.removeEventListener("pointercancel", end)
    }
    divider.addEventListener("pointermove", move)
    divider.addEventListener("pointerup", end)
    divider.addEventListener("pointercancel", end)
  }

  const onKeyDown = (event: React.KeyboardEvent<HTMLDivElement>) => {
    const step = event.key === "ArrowLeft" ? -16 : event.key === "ArrowRight" ? 16 : 0
    if (!step) return
    event.preventDefault()
    const current = event.currentTarget.parentElement?.getBoundingClientRect().width ?? 0
    onResize(fit(current + step))
  }

  return (
    // A window splitter: focusable, and moved with the arrow keys as well as the pointer.
    <div
      className="divider"
      role="separator"
      aria-orientation="vertical"
      aria-label="Editor width"
      aria-valuenow={width}
      aria-valuemin={MIN_EDITOR_WIDTH}
      tabIndex={0}
      onPointerDown={onPointerDown}
      onKeyDown={onKeyDown}
    />
  )
}
