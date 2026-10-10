import { useNavigate } from "@tanstack/react-router"

import { editorHandle, useEdit } from "@/lib/edits"
import type { Page } from "@/lib/files"

/**
 * A page's HTML, rendered at build time, or by the editor once it has been open on the page.
 * Clicks are handled here for the whole page: a code block's Copy button, and links to the site's
 * other pages, which open in the same window without reloading it, as Markview opens a linked
 * Markdown file. With the editor open, a double-click on a block goes to where it is written.
 */
export function Article({ page, path }: { page: Page; path?: string }) {
  const navigate = useNavigate()
  const edit = useEdit(path)

  const onClick = (event: React.MouseEvent<HTMLElement>) => {
    const target = event.target as HTMLElement

    const copy = target.closest<HTMLButtonElement>("button.copy")
    if (copy) {
      const code = copy.parentElement?.querySelector("pre")?.innerText ?? ""
      navigator.clipboard.writeText(code).then(
        () => {
          copy.textContent = "Copied"
          setTimeout(() => (copy.textContent = "Copy"), 1500)
        },
        () => (copy.textContent = "Select it")
      )
      return
    }

    const link = target.closest("a")
    const href = link?.getAttribute("href")
    if (!href || !href.startsWith("/") || href.startsWith("//")) return
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey)
      return
    event.preventDefault()
    void navigate({ href })
  }

  const onDoubleClick = (event: React.MouseEvent<HTMLElement>) => {
    const block = (event.target as HTMLElement).closest<HTMLElement>("[data-line]")
    if (block) editorHandle()?.reveal(Number(block.dataset.line))
  }

  return (
    // The clicks handled here come from links and buttons inside the page, which are focusable.
    // A double-click is a shortcut to the editor, which has its own keyboard routes.
    <article
      className="markdown"
      onClick={onClick}
      onDoubleClick={onDoubleClick}
      dangerouslySetInnerHTML={{ __html: (edit?.page ?? page).html }}
    />
  )
}
