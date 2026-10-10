import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  useSyncExternalStore,
} from "react"
import { useNavigate, useRouterState } from "@tanstack/react-router"

import { Editor, MIN_EDITOR_WIDTH, loadEditor } from "@/components/Editor"
import { ShortcutsDialog } from "@/components/ShortcutsDialog"
import { Sidebar } from "@/components/Sidebar"
import { ThemeMenu } from "@/components/ThemeMenu"
import { AppleIcon, DocumentIcon, EditIcon, GitHubIcon, SidebarIcon } from "@/components/icons"
import { editorHandle, useEdit } from "@/lib/edits"
import { scrollToHeading, useShortcuts } from "@/lib/shortcuts"
import { flipAppearance, stepTheme } from "@/lib/theme"
import { fileAt, files } from "@/pages"
import { REPOSITORY, downloadURL } from "@/site"

const NARROW = "(max-width: 820px)"
const EDITOR_WIDTH_KEY = "markview-site-editor-width"

/**
 * The site drawn as a Markview window: a title bar naming the open file, the sidebar of files
 * (the site's pages), the editor when it is open, and the page itself. The title bar also carries
 * the theme menu, the link to the source and the download link, which the app's window doesn't
 * need.
 */
export function Window({ children }: { children: React.ReactNode }) {
  const navigate = useNavigate()
  const pathname = useRouterState({ select: (state) => state.location.pathname })
  const current = fileAt(pathname)
  const edit = useEdit(current?.path)
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

  // The editor opens beside the page, as ⌘U opens it in Markview, and stays open from page to
  // page. On narrow screens it takes the page's place. Either way the page keeps its place.
  const [editorShown, setEditorShown] = useState(false)
  const [editorWidth, setEditorWidth] = useStoredWidth()
  const restorePlace = useRef<() => void>(undefined)
  const toggleEditor = () => {
    if (!current) return
    restorePlace.current = narrow ? (editorShown ? placeOfEditor() : undefined) : placeOnPage()
    setEditorShown((shown) => !shown)
  }
  useLayoutEffect(() => {
    restorePlace.current?.()
    restorePlace.current = undefined
  }, [editorShown])

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
    toggleEditor,
    // ⌘S would save the web page; with the editor open it says what becomes of the edits instead.
    save: () => {
      if (!editorShown) return false
      showNotice("Edits made here aren't saved")
      return true
    },
    toggleHelp: () => setHelpOpen((open) => !open),
  })

  const fileName = current
    ? current.name === "LICENSE"
      ? "LICENSE"
      : `${current.name}.md`
    : "Not found"
  const edited = edit?.edited ?? false
  const showsEditor = editorShown && current !== undefined

  return (
    <div className="window">
      <header className="titlebar">
        {/* An edited document's window has a dot in its close button. */}
        <span className="lights" data-edited={edited} aria-hidden="true">
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
          {edited && <span className="edited">— Edited</span>}
        </span>
        <button
          type="button"
          className="editor-toggle"
          aria-pressed={showsEditor}
          aria-label="Edit"
          title="Show or hide the editor (E or ⌘U)"
          disabled={!current}
          onClick={toggleEditor}
          onPointerEnter={() => void loadEditor()}
          onFocus={() => void loadEditor()}
        >
          <EditIcon />
          <span className="editor-toggle-label">Edit</span>
        </button>
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
      <div
        className="body"
        data-sidebar={sidebarHidden ? "hidden" : "shown"}
        data-editor={showsEditor ? "shown" : "hidden"}
        style={
          showsEditor && editorWidth
            ? ({ "--editor-width": `${editorWidth}px` } as React.CSSProperties)
            : undefined
        }
      >
        <Sidebar
          headings={(edit?.page ?? current?.page)?.headings ?? []}
          open={sidebarOpen}
          onShowShortcuts={() => setHelpOpen(true)}
        />
        {editorShown && current && (
          <Editor file={current} edited={edited} width={editorWidth} onResize={setEditorWidth} />
        )}
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

/** The editor's width once its divider has been dragged, kept for the next visit as Markview does. */
function useStoredWidth() {
  const [width, setWidth] = useState<number | undefined>(() => {
    if (typeof window === "undefined") return undefined
    try {
      const stored = Number(localStorage.getItem(EDITOR_WIDTH_KEY))
      return stored >= MIN_EDITOR_WIDTH ? stored : undefined
    } catch {
      return undefined
    }
  })
  const store = useCallback((next: number) => {
    setWidth(next)
    try {
      localStorage.setItem(EDITOR_WIDTH_KEY, String(next))
    } catch {
      // Private windows may refuse storage; the width then lasts for this page only.
    }
  }, [])
  return [width, store] as const
}

/**
 * Where the page is being read: the first block showing below the title bar, and how far down
 * the window it is. The function returned scrolls that block back there once the page has
 * reflowed around the editor.
 */
function placeOnPage() {
  const titlebar = document.querySelector(".titlebar")?.getBoundingClientRect().bottom ?? 0
  const blocks = document.querySelectorAll<HTMLElement>(".page .markdown > *")
  const block = Array.from(blocks).find((each) => each.getBoundingClientRect().bottom > titlebar)
  if (!block) return undefined
  const top = block.getBoundingClientRect().top
  return () => window.scrollBy(0, block.getBoundingClientRect().top - top)
}

/**
 * On narrow screens, where the editor stood in for the page: the block written at the editor's
 * top line, which the page scrolls to as it comes back.
 */
function placeOfEditor() {
  const line = editorHandle()?.topLine()
  if (line === undefined) return undefined
  return () => {
    const blocks = document.querySelectorAll<HTMLElement>(".page .markdown [data-line]")
    const block = Array.from(blocks)
      .filter((each) => Number(each.dataset.line) <= line)
      .at(-1)
    const titlebar = document.querySelector(".titlebar")?.getBoundingClientRect().bottom ?? 0
    if (block) window.scrollBy(0, block.getBoundingClientRect().top - titlebar - 16)
  }
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
