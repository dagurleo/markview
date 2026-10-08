import { HeadContent, Outlet, Scripts, createRootRoute } from "@tanstack/react-router"

import { Article } from "@/components/Article"
import { Window } from "@/components/Window"
import { notFoundPage } from "@/lib/seo"
import { paletteCSS, themeScript } from "@/lib/palettes"
import appCss from "../styles.css?url"

export const Route = createRootRoute({
  head: () => ({
    meta: [
      { charSet: "utf-8" },
      { name: "viewport", content: "width=device-width, initial-scale=1" },
      { name: "color-scheme", content: "light dark" },
      { title: "Markview" },
    ],
    links: [
      { rel: "stylesheet", href: appCss },
      { rel: "icon", href: "/favicon.png", type: "image/png" },
      { rel: "apple-touch-icon", href: "/apple-touch-icon.png" },
    ],
  }),
  shellComponent: RootDocument,
  component: () => (
    <Window>
      <Outlet />
    </Window>
  ),
  notFoundComponent: () => <Article page={notFoundPage} />,
})

function RootDocument({ children }: { children: React.ReactNode }) {
  return (
    // The theme script sets data-theme and data-appearance before React hydrates the page.
    <html lang="en" suppressHydrationWarning>
      <head>
        <HeadContent />
        {/* Markview's twelve themes as CSS variables, and the visitor's choice of them. */}
        <style dangerouslySetInnerHTML={{ __html: paletteCSS() }} />
        <script dangerouslySetInnerHTML={{ __html: themeScript }} />
      </head>
      <body>
        {children}
        <Scripts />
      </body>
    </html>
  )
}
