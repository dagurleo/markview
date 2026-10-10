import { useEffect, useState } from "react"
import { Link } from "@tanstack/react-router"

import { DocumentIcon } from "@/components/icons"
import { files } from "@/pages"
import type { Page } from "@/lib/files"

type Tab = "files" | "contents"

/** Files and Contents, as in Markview's sidebar: the site's pages, and the open page's headings. */
export function Sidebar({
  headings,
  open,
  onShowShortcuts,
}: {
  /** The open page's headings, as edited if it has been. */
  headings: Page["headings"]
  open: boolean
  onShowShortcuts: () => void
}) {
  const [tab, setTab] = useState<Tab>("files")

  return (
    <nav id="sidebar" className="sidebar" data-open={open} aria-label="Files">
      <div className="tabs" role="tablist">
        {(["files", "contents"] as const).map((name) => (
          <button
            key={name}
            type="button"
            role="tab"
            aria-selected={tab === name}
            onClick={() => setTab(name)}
          >
            {name === "files" ? "Files" : "Contents"}
          </button>
        ))}
      </div>
      {tab === "files" ? (
        <ul>
          {files.map((file) => (
            <li key={file.path}>
              {file.path === "/" ? (
                <Link
                  to="/"
                  className="row"
                  activeProps={{ className: "on" }}
                  activeOptions={{ exact: true }}
                >
                  <DocumentIcon />
                  {file.name}
                </Link>
              ) : (
                <Link
                  to="/$file"
                  params={{ file: file.path.slice(1) }}
                  className="row"
                  activeProps={{ className: "on" }}
                >
                  <DocumentIcon />
                  {file.name}
                </Link>
              )}
            </li>
          ))}
        </ul>
      ) : (
        <Outline headings={headings} />
      )}
      <button type="button" className="shortcuts-button" onClick={onShowShortcuts}>
        Keyboard shortcuts <kbd>?</kbd>
      </button>
    </nav>
  )
}

/** The open page's headings, marking the section being read, as Markview's outline does. */
function Outline({ headings }: { headings: Page["headings"] }) {
  const active = useActiveHeading(headings)
  if (headings.length === 0) return <p className="empty">This page has no headings.</p>
  return (
    <ul className="outline">
      {headings.map((heading) => (
        <li key={heading.id} data-depth={heading.depth}>
          <a href={`#${heading.id}`} className={heading.id === active ? "row on" : "row"}>
            {heading.text}
          </a>
        </li>
      ))}
    </ul>
  )
}

/** The last heading that has scrolled up to the top of the page, under the title bar. */
function useActiveHeading(headings: Page["headings"]) {
  const [active, setActive] = useState<string>()
  useEffect(() => {
    let frame = 0
    const update = () => {
      frame = 0
      let found: string | undefined
      for (const heading of headings) {
        const element = document.getElementById(heading.id)
        if (element && element.getBoundingClientRect().top < 120) found = heading.id
      }
      setActive(found)
    }
    const schedule = () => {
      if (!frame) frame = requestAnimationFrame(update)
    }
    update()
    window.addEventListener("scroll", schedule, { passive: true })
    return () => {
      window.removeEventListener("scroll", schedule)
      cancelAnimationFrame(frame)
    }
  }, [headings])
  return active
}
