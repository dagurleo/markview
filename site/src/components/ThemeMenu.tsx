import { useEffect, useRef } from "react"

import { ChevronIcon } from "@/components/icons"
import { palettes } from "@/lib/palettes"
import type { Appearance, Palette } from "@/lib/palettes"
import { setTheme, useTheme } from "@/lib/theme"

const appearances: { value: Appearance; label: string }[] = [
  { value: "system", label: "System" },
  { value: "light", label: "Light" },
  { value: "dark", label: "Dark" },
]

/**
 * The theme, chosen as in Markview's Settings: a tile per theme showing its light and dark sides,
 * and System, Light or Dark beneath. A button in the title bar opens it, and so does the comma key.
 */
export function ThemeMenu({
  open,
  onOpenChange,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
}) {
  const { theme, appearance } = useTheme()
  const button = useRef<HTMLButtonElement>(null)
  const panel = useRef<HTMLDivElement>(null)

  // Open, the panel takes focus at the chosen theme, and closes on Escape or a click elsewhere.
  useEffect(() => {
    if (!open) return
    panel.current?.querySelector<HTMLElement>('[aria-pressed="true"]')?.focus()
    const close = (event: PointerEvent) => {
      const target = event.target as Node
      if (!panel.current?.contains(target) && !button.current?.contains(target)) onOpenChange(false)
    }
    const escape = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return
      onOpenChange(false)
      button.current?.focus()
    }
    document.addEventListener("pointerdown", close)
    document.addEventListener("keydown", escape)
    return () => {
      document.removeEventListener("pointerdown", close)
      document.removeEventListener("keydown", escape)
    }
  }, [open, onOpenChange])

  const current = palettes.find((palette) => palette.id === theme) ?? palettes[0]

  return (
    <div className="theme-menu">
      <button
        ref={button}
        type="button"
        className="theme-button"
        aria-haspopup="dialog"
        aria-expanded={open}
        aria-label={`Theme: ${current.name}`}
        title="Theme (,)"
        onClick={() => onOpenChange(!open)}
      >
        <span
          className="swatch"
          style={{
            background: `linear-gradient(135deg, ${current.light.background} 50%, ${current.dark.background} 50%)`,
          }}
        />
        <span className="theme-name">{current.name}</span>
        <ChevronIcon />
      </button>
      {open && (
        <div ref={panel} className="theme-panel" role="dialog" aria-label="Theme">
          <p className="panel-label">Theme</p>
          <div className="theme-grid">
            {palettes.map((palette) => (
              <button
                key={palette.id}
                type="button"
                className="theme-tile"
                aria-pressed={palette.id === theme}
                onClick={() => setTheme({ theme: palette.id })}
              >
                <span className="sides">
                  <Side colors={palette.light} />
                  <Side colors={palette.dark} />
                </span>
                <span className="tile-name">{palette.name}</span>
              </button>
            ))}
          </div>
          <p className="panel-label">Appearance</p>
          <div className="segmented" role="radiogroup" aria-label="Appearance">
            {appearances.map((option) => (
              <button
                key={option.value}
                type="button"
                role="radio"
                aria-checked={appearance === option.value}
                onClick={() => setTheme({ appearance: option.value })}
              >
                {option.label}
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

/** One side of a theme, drawn as Markview's Settings draws it: "Aa" over lines of text. */
function Side({ colors }: { colors: Palette["light"] }) {
  return (
    <span className="side" style={{ background: colors.background, color: colors.text }}>
      Aa
      <i style={{ background: colors.text }} />
      <i style={{ background: colors.link }} />
    </span>
  )
}
