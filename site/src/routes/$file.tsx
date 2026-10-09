import { createFileRoute, notFound } from "@tanstack/react-router"

import { Article } from "@/components/Article"
import { pageHead } from "@/lib/seo"
import { fileAt } from "@/pages"

/** Every file in the sidebar but the README, at /quick-look, /themes and so on. */
export const Route = createFileRoute("/$file")({
  // Only the address goes into the loader data, which the page carries for hydration; the
  // pages themselves are in the bundle already (src/pages.ts).
  loader: ({ params }) => {
    const file = fileAt(`/${params.file}`)
    if (!file || file.path === "/") throw notFound()
    return { path: file.path }
  },
  head: ({ loaderData }) => {
    const file = loaderData && fileAt(loaderData.path)
    return file ? pageHead(file) : {}
  },
  component: FilePage,
})

function FilePage() {
  const { path } = Route.useLoaderData()
  const file = fileAt(path)
  return file ? <Article page={file.page} /> : null
}
