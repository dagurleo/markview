import { useSyncExternalStore } from "react"

import { DEFAULT_THEME, applyTheme, palettes, resolveAppearance, storedTheme } from "@/lib/palettes"
import type { Appearance } from "@/lib/palettes"

// The visitor's theme, shared by the theme menu and the keyboard shortcuts. The page drew the
// stored choice before React started (themeScript), so the store starts from it too.

type ThemeState = { theme: string; appearance: Appearance }

const initial: ThemeState = { theme: DEFAULT_THEME, appearance: "system" }
let state: ThemeState = typeof window === "undefined" ? initial : storedTheme()
const listeners = new Set<() => void>()

function subscribe(listener: () => void) {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

export function useTheme(): ThemeState {
  return useSyncExternalStore(
    subscribe,
    () => state,
    () => initial
  )
}

export function setTheme(next: Partial<ThemeState>) {
  state = { ...state, ...next }
  applyTheme(state.theme, state.appearance)
  for (const listener of listeners) listener()
}

/** The next or previous of the twelve themes, in the order of Markview's Settings. */
export function stepTheme(step: 1 | -1) {
  const index = palettes.findIndex((palette) => palette.id === state.theme)
  const next = palettes[(index + step + palettes.length) % palettes.length]
  setTheme({ theme: next.id })
  return next
}

/** Light if the page is dark now, dark if it is light. */
export function flipAppearance() {
  const next = resolveAppearance(state.appearance) === "dark" ? "light" : "dark"
  setTheme({ appearance: next })
  return next
}

// Following the system means following it when it changes, too.
if (typeof window !== "undefined") {
  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
    if (state.appearance === "system") applyTheme(state.theme, "system")
  })
}
