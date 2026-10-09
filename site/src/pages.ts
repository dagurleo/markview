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

const entry = (name: string, page: Page) => ({ name, path: pathForFile(name), page })

/** The files in the sidebar, in its order. The name is the file's, as Markview lists it. */
export const files = [
  entry("README", readme),
  entry("Editor", editor),
  entry("Quick Look", quickLook),
  entry("Themes", themes),
  entry("Maths and diagrams", mathsAndDiagrams),
  entry("Folders", folders),
  entry("Terminal", terminal),
  entry("CHANGELOG", changelog),
  entry("LICENSE", license),
]

export function fileAt(path: string) {
  const clean = path.length > 1 ? path.replace(/\/$/, "") : path
  return files.find((file) => file.path === clean)
}
