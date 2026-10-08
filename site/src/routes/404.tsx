import { createFileRoute } from "@tanstack/react-router"

import { Article } from "@/components/Article"
import { notFoundPage } from "@/lib/seo"

// Prerendered to 404.html, which Cloudflare serves for any address without a page (wrangler.jsonc).
export const Route = createFileRoute("/404")({
  head: () => ({
    meta: [{ title: "Not found · Markview" }, { name: "robots", content: "noindex" }],
  }),
  component: () => <Article page={notFoundPage} />,
})
