/** A page of the site: one Markdown file, rendered at build time (plugins/markdown.ts). */
export type Page = {
  title: string
  description: string
  /** The headings below the title, for the sidebar's Contents tab. */
  headings: { depth: number; id: string; text: string }[]
  html: string
}

/** The address of a file's page: README.md is the home page, "Quick Look.md" is /quick-look. */
export function pathForFile(file: string): string {
  const name = file.replace(/\.md$/i, "")
  if (name === "README") return "/"
  return "/" + name.toLowerCase().replace(/\s+/g, "-")
}
