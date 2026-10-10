import readme from "../content/README.md"
import editor from "../content/Editor.md"
import quickLook from "../content/Quick Look.md"
import themes from "../content/Themes.md"
import mathsAndDiagrams from "../content/Maths and diagrams.md"
import folders from "../content/Folders.md"
import terminal from "../content/Terminal.md"
// The app's own changelog and licence, from the repository.
import changelog from "../../CHANGELOG.md"
import license from "../../LICENSE?markdown"

import { pathForFile } from "@/lib/files"
import type { Page } from "@/lib/files"

type Source = () => Promise<{ default: string }>

const entry = (name: string, page: Page, source: Source) => ({
  name,
  path: pathForFile(name),
  page,
  /** The page's Markdown, loaded when the editor opens on it. */
  source: async () => (await source()).default,
})

/** The files in the sidebar, in its order. The name is the file's, as Markview lists it. */
export const files = [
  entry("README", readme, () => import("../content/README.md?source")),
  entry("Editor", editor, () => import("../content/Editor.md?source")),
  entry("Quick Look", quickLook, () => import("../content/Quick Look.md?source")),
  entry("Themes", themes, () => import("../content/Themes.md?source")),
  entry(
    "Maths and diagrams",
    mathsAndDiagrams,
    () => import("../content/Maths and diagrams.md?source")
  ),
  entry("Folders", folders, () => import("../content/Folders.md?source")),
  entry("Terminal", terminal, () => import("../content/Terminal.md?source")),
  entry("CHANGELOG", changelog, () => import("../../CHANGELOG.md?source")),
  entry("LICENSE", license, () => import("../../LICENSE?source")),
]

export type File = (typeof files)[number]

export function fileAt(path: string) {
  const clean = path.length > 1 ? path.replace(/\/$/, "") : path
  return files.find((file) => file.path === clean)
}
