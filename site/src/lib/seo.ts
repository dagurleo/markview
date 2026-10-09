import type { Page } from "@/lib/files"
import type { files } from "@/pages"

/** A page's title and description, for the browser tab, search engines and link previews. */
export function pageHead(file: (typeof files)[number]) {
  const title =
    file.path === "/"
      ? "Markview, a Markdown viewer for macOS"
      : `${file.page.title || file.name} · Markview`
  const description = file.page.description
  return {
    meta: [
      { title },
      { name: "description", content: description },
      { property: "og:title", content: title },
      { property: "og:description", content: description },
      { property: "og:type", content: "website" },
    ],
  }
}

export const notFoundPage: Page = {
  title: "Not found",
  description: "",
  headings: [],
  html: "<h1>Not found</h1><p>There is no page at this address. The site's pages are the files in the sidebar.</p>",
}
