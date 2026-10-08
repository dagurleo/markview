import { useCallback, useEffect, useRef, useState, useSyncExternalStore } from "react"
import { useNavigate, useRouterState } from "@tanstack/react-router"

import { ShortcutsDialog } from "@/components/ShortcutsDialog"
import { Sidebar } from "@/components/Sidebar"
import { ThemeMenu } from "@/components/ThemeMenu"
import { AppleIcon, DocumentIcon, GitHubIcon, SidebarIcon } from "@/components/icons"
import { scrollToHeading, useShortcuts } from "@/lib/shortcuts"
import { flipAppearance, stepTheme } from "@/lib/theme"
import { fileAt, files } from "@/pages"
import { REPOSITORY, downloadURL } from "@/site"

const NARROW = "(max-width: 820px)"

/**
 * The site drawn as a Markview window: a title bar naming the open file, the sidebar of files
 * (the site's pages) and the page itself. The title bar also carries the theme menu, the link to
 * the source and the download link, which the app's window doesn't need.
 */
export function Window({ children }: { children: React.ReactNode }) {
  const navigate = useNavigate()
  const pathname = useRouterState({ select: (state) => state.location.pathname })
  const current = fileAt(pathname)
  const narrow = useMediaQuery(NARROW)

  // The sidebar hides on wide screens, as Markview's does (⌃⌘S). On narrow screens it slides over
  // the page instead, and closes on a new page, on Escape, and when the page beside it is tapped.
  const [sidebarHidden, setSidebarHidden] = useState(false)
  const [sidebarOpen, setSidebarOpen] = useState(false)
  useEffect(() => setSidebarOpen(false), [pathname])
  useEffect(() => {
    if (!sidebarOpen) return
    const close = (event: KeyboardEvent) => event.key === "Escape" && setSidebarOpen(false)
    window.addEventListener("keydown", close)
    return () => window.removeEventListener("keydown", close)
  }, [sidebarOpen])
  const toggleSidebar = () => {
    if (matchMedia(NARROW).matches) setSidebarOpen((open) => !open)
    else setSidebarHidden((hidden) => !hidden)
  }

  const [themeMenuOpen, setThemeMenuOpen] = useState(false)
  const [helpOpen, setHelpOpen] = useState(false)
  const [notice, showNotice] = useNotice()

  useShortcuts({
    openFile: (index) => {
      const file = files.at(index)
      if (file) void navigate({ href: file.path })
    },
    stepFile: (step) => {
      const index = files.findIndex((file) => file.path === current?.path)
      const file = files.at(Math.min(Math.max(index + step, 0), files.length - 1))
      if (file && file !== current) void navigate({ href: file.path })
    },
    stepHeading: scrollToHeading,
    stepTheme: (step) => showNotice(stepTheme(step).name),
    flipAppearance: () => showNotice(flipAppearance() === "dark" ? "Dark" : "Light"),
    openThemeMenu: () => setThemeMenuOpen(true),
    toggleSidebar,
    toggleHelp: () => setHelpOpen((open) => !open),
  })

  const fileName = current
    ? current.name === "LICENSE"
      ? "LICENSE"
      : `${current.name}.md`
    : "Not found"

  return (
    <div className="window">
      <header className="titlebar">
        <span className="lights" aria-hidden="true">
          <i />
          <i />
          <i />
        </span>
        <button
          type="button"
          className="sidebar-toggle"
          aria-label="Sidebar"
          aria-expanded={narrow ? sidebarOpen : !sidebarHidden}
          aria-controls="sidebar"
          title="Show or hide the sidebar (S)"
          onClick={toggleSidebar}
        >
          <SidebarIcon />
        </button>
        <span className="title">
          <DocumentIcon />
          <span className="name">{fileName}</span>
          <span className="folder">– markview</span>
        </span>
        <ThemeMenu open={themeMenuOpen} onOpenChange={setThemeMenuOpen} />
        <a
          className="github"
          href={REPOSITORY}
          aria-label="Star Markview on GitHub"
          title="Star Markview on GitHub"
        >
          <GitHubIcon />
          <span className="github-label">Star</span>
        </a>
        <a className="download" href={downloadURL(__MARKVIEW_VERSION__)}>
          <AppleIcon />
          <span>
            Download<span className="for-mac"> for Mac</span>
          </span>
        </a>
      </header>
      <div className="body" data-sidebar={sidebarHidden ? "hidden" : "shown"}>
        <Sidebar current={current} open={sidebarOpen} onShowShortcuts={() => setHelpOpen(true)} />
        {/* A tap on the page closes the sidebar over it; Escape does the same from the keyboard. */}
        <main className="page" onClick={sidebarOpen ? () => setSidebarOpen(false) : undefined}>
          {children}
        </main>
      </div>
      <ShortcutsDialog open={helpOpen} onClose={() => setHelpOpen(false)} />
      <p className="notice" role="status" data-shown={notice.shown}>
        {notice.text}
      </p>
    </div>
  )
}

function useMediaQuery(query: string) {
  return useSyncExternalStore(
    (onChange) => {
      const list = matchMedia(query)
      list.addEventListener("change", onChange)
      return () => list.removeEventListener("change", onChange)
    },
    () => matchMedia(query).matches,
    () => false
  )
}

/** A short notice at the foot of the window, naming a theme chosen from the keyboard. */
function useNotice() {
  const [notice, setNotice] = useState({ text: "", shown: false })
  const timer = useRef<ReturnType<typeof setTimeout>>(undefined)
  useEffect(() => () => clearTimeout(timer.current), [])
  const show = useCallback((text: string) => {
    clearTimeout(timer.current)
    setNotice({ text, shown: true })
    timer.current = setTimeout(() => setNotice((last) => ({ ...last, shown: false })), 1400)
  }, [])
  return [notice, show] as const
}
