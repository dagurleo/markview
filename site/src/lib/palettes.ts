import palettes from "virtual:palettes"

/** One of Markview's themes, read from Native/Palette.swift (plugins/palettes.ts). */
export type Palette = {
  id: string
  name: string
  light: Record<string, string>
  dark: Record<string, string>
}

export type Appearance = "system" | "light" | "dark"

export { palettes }
export const DEFAULT_THEME = "github"
export const THEME_KEY = "markview-site-theme"
export const APPEARANCE_KEY = "markview-site-appearance"

const variables = (colors: Record<string, string>) =>
  Object.entries(colors)
    .map(([role, hex]) => `--${role}:${hex}`)
    .join(";")

/**
 * Every theme's colours as CSS variables on the root element, chosen by its data-theme and
 * data-appearance attributes. Without them (no JavaScript yet) the default theme follows the system.
 */
export function paletteCSS(): string {
  const fallback = palettes.find((palette) => palette.id === DEFAULT_THEME) ?? palettes[0]
  const rules = palettes.flatMap((palette) =>
    (["light", "dark"] as const).map(
      (side) =>
        `:root[data-theme="${palette.id}"][data-appearance="${side}"]{${variables(palette[side])}}`
    )
  )
  return [
    `:root{${variables(fallback.light)}}`,
    `@media (prefers-color-scheme: dark){:root{${variables(fallback.dark)}}}`,
    ...rules,
  ].join("\n")
}

/**
 * Runs in the page's head before it is drawn, so a chosen theme shows without a flash of the
 * default one. Kept in step with applyTheme below.
 */
export const themeScript = `(function(){try{var r=document.documentElement,t=localStorage.getItem("${THEME_KEY}")||"${DEFAULT_THEME}",a=localStorage.getItem("${APPEARANCE_KEY}")||"system";r.dataset.theme=t;r.dataset.appearance=a==="system"?(matchMedia("(prefers-color-scheme: dark)").matches?"dark":"light"):a}catch(e){}})()`

export function resolveAppearance(appearance: Appearance): "light" | "dark" {
  if (appearance !== "system") return appearance
  return matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"
}

export function applyTheme(theme: string, appearance: Appearance) {
  const root = document.documentElement
  root.dataset.theme = theme
  root.dataset.appearance = resolveAppearance(appearance)
  try {
    localStorage.setItem(THEME_KEY, theme)
    localStorage.setItem(APPEARANCE_KEY, appearance)
  } catch {
    // Private windows may refuse storage; the choice then lasts for this page only.
  }
}

export function storedTheme(): { theme: string; appearance: Appearance } {
  try {
    return {
      theme: localStorage.getItem(THEME_KEY) ?? DEFAULT_THEME,
      appearance: (localStorage.getItem(APPEARANCE_KEY) as Appearance | null) ?? "system",
    }
  } catch {
    return { theme: DEFAULT_THEME, appearance: "system" }
  }
}
