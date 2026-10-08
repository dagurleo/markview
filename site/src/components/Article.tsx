import { useNavigate } from "@tanstack/react-router"

import type { Page } from "@/lib/files"

/**
 * A page's HTML, rendered at build time. Clicks are handled here for the whole page: a code
 * block's Copy button, and links to the site's other pages, which open in the same window
 * without reloading it, as Markview opens a linked Markdown file.
 */
export function Article({ page }: { page: Page }) {
  const navigate = useNavigate()

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

  return (
    // The clicks handled here come from links and buttons inside the page, which are focusable.
    <article
      className="markdown"
      onClick={onClick}
      dangerouslySetInnerHTML={{ __html: page.html }}
    />
  )
}
