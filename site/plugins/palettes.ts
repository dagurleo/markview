import { readFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import type { Plugin } from "vite"

import type { Palette } from "../src/lib/palettes.ts"

// The site's themes are the app's: `virtual:palettes` reads Native/Palette.swift at build time,
// so a colour changed there changes here too.

/** The palettes in the order of `Palette.all`, each role as a light and a dark hex colour. */
export function parsePalettes(swift: string): Palette[] {
  const all = /static let all: \[Palette\] = \[([^\]]+)\]/.exec(swift)
  if (!all) throw new Error("Palette.swift: no `static let all`")
  const blocks = swift.split("static let ")
  return all[1].split(",").map((entry) => {
    const name = entry.trim().replace(/^\./, "")
    const block = blocks.find((part) => part.startsWith(`${name} = Palette(`))
    if (!block) throw new Error(`Palette.swift: no palette ${name}`)
    const id = /id: "([^"]+)"/.exec(block)?.[1] ?? name
    const title = /name: "([^"]+)"/.exec(block)?.[1] ?? name
    const light: Record<string, string> = {}
    const dark: Record<string, string> = {}
    for (const [, role, lightHex, darkHex] of block.matchAll(
      /(\w+): \(0x([0-9a-fA-F]{6}), 0x([0-9a-fA-F]{6})\)/g
    )) {
      light[role] = `#${lightHex.toLowerCase()}`
      dark[role] = `#${darkHex.toLowerCase()}`
    }
    return { id, name: title, light, dark }
  })
}

export function palettes(swiftFile: URL): Plugin {
  const id = "virtual:palettes"
  const path = fileURLToPath(swiftFile)
  return {
    name: "markview-palettes",
    resolveId(source) {
      return source === id ? `\0${id}` : undefined
    },
    load(resolved) {
      if (resolved !== `\0${id}`) return
      this.addWatchFile(path)
      return `export default ${JSON.stringify(parsePalettes(readFileSync(path, "utf8")))}`
    },
  }
}
