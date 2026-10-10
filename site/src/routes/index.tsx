import { createFileRoute } from "@tanstack/react-router"

import { Article } from "@/components/Article"
import { pageHead } from "@/lib/seo"
import { files } from "@/pages"

const readme = files[0]

export const Route = createFileRoute("/")({
  head: () => pageHead(readme),
  component: () => <Article page={readme.page} path={readme.path} />,
})
