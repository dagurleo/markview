import { useEffect, useRef } from "react"

// The site's keyboard shortcuts. Where Markview has one for the same thing, the site takes it:
// ⌥⌘↓ and ⌥⌘↑ for the next and previous heading, ⌃⌘S for the sidebar, and the browser's own
// ⌘[ and ⌘] for Back and Forward. The rest are single keys, which work unless a field has focus.

export type ShortcutActions = {
  openFile: (index: number) => void
  stepFile: (step: 1 | -1) => void
  stepHeading: (step: 1 | -1) => void
  stepTheme: (step: 1 | -1) => void
  flipAppearance: () => void
  openThemeMenu: () => void
  toggleSidebar: () => void
  toggleHelp: () => void
}

type ShortcutRow = {
  label: string
  /** Alternatives, each one or more combinations of keys, shown joined by `joiner` ("/"). */
  keys: string[][][]
  joiner?: string
}

/** What the shortcuts panel lists. */
export const shortcutGroups: { title: string; rows: ShortcutRow[] }[] = [
  {
    title: "Pages",
    rows: [
      { label: "Open a file in the sidebar", keys: [[["1"], ["9"]]], joiner: "to" },
      { label: "Next or previous file", keys: [[["J"], ["K"]]] },
      {
        label: "Back or Forward",
        keys: [
          [
            ["⌘", "["],
            ["⌘", "]"],
          ],
        ],
      },
    ],
  },
  {
    title: "Headings",
    rows: [
      {
        label: "Next or previous heading",
        keys: [
          [["N"], ["P"]],
          [
            ["⌥", "⌘", "↓"],
            ["⌥", "⌘", "↑"],
          ],
        ],
      },
    ],
  },
  {
    title: "Themes",
    rows: [
      { label: "Next or previous theme", keys: [[["T"], ["⇧", "T"]]] },
      { label: "Switch between light and dark", keys: [[["A"]]] },
      { label: "Open the theme menu", keys: [[[","]]] },
    ],
  },
  {
    title: "Window",
    rows: [
      { label: "Show or hide the sidebar", keys: [[["S"]], [["⌃", "⌘", "S"]]] },
      { label: "Show these shortcuts", keys: [[["?"]]] },
      { label: "Close a menu or panel", keys: [[["esc"]]] },
    ],
  },
]

function isTyping(target: EventTarget | null) {
  if (!(target instanceof HTMLElement)) return false
  return target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName)
}

/** Listens for the shortcuts on the whole page, always calling the latest actions. */
export function useShortcuts(actions: ShortcutActions) {
  const latest = useRef(actions)
  latest.current = actions

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.defaultPrevented || event.isComposing || isTyping(event.target)) return
      const act = latest.current
      const { metaKey: command, altKey: option, ctrlKey: control, key } = event
      let action: (() => void) | undefined

      if (command && option && !control && key === "ArrowDown") action = () => act.stepHeading(1)
      else if (command && option && !control && key === "ArrowUp")
        action = () => act.stepHeading(-1)
      else if (command && control && !option && key.toLowerCase() === "s")
        action = act.toggleSidebar
      else if (!command && !option && !control) {
        if (/^[1-9]$/.test(key)) action = () => act.openFile(Number(key) - 1)
        else {
          const single: Record<string, (() => void) | undefined> = {
            j: () => act.stepFile(1),
            k: () => act.stepFile(-1),
            n: () => act.stepHeading(1),
            p: () => act.stepHeading(-1),
            t: () => act.stepTheme(1),
            T: () => act.stepTheme(-1),
            a: act.flipAppearance,
            ",": act.openThemeMenu,
            s: act.toggleSidebar,
            "?": act.toggleHelp,
          }
          action = single[key]
        }
      }

      if (!action) return
      event.preventDefault()
      action()
    }
    window.addEventListener("keydown", onKeyDown)
    return () => window.removeEventListener("keydown", onKeyDown)
  }, [])
}

/**
 * Scrolls to the next or previous heading of the page, the way Markview's Go > Next Heading does.
 * Headings come to rest below the title bar (their scroll-margin-top in styles.css).
 */
export function scrollToHeading(step: 1 | -1) {
  const headings = Array.from(
    document.querySelectorAll<HTMLElement>(".markdown h2[id], .markdown h3[id]")
  )
  const first = headings.at(0)
  if (!first) return
  const restingLine = parseFloat(getComputedStyle(first).scrollMarginTop) || 0
  const behavior = matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth"
  const target =
    step > 0
      ? headings.find((heading) => heading.getBoundingClientRect().top > restingLine + 2)
      : headings.reverse().find((heading) => heading.getBoundingClientRect().top < restingLine - 2)
  if (target) target.scrollIntoView({ behavior, block: "start" })
  else if (step < 0) window.scrollTo({ top: 0, behavior })
}
