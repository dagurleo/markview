/** A sheet with a folded corner, as Markview's sidebar shows a Markdown file. */
export function DocumentIcon() {
  return (
    <svg width="12" height="14" viewBox="0 0 12 14" fill="none" aria-hidden="true">
      <path
        d="M2 .75h5.2L10.25 3.8V12A1.25 1.25 0 0 1 9 13.25H2A1.25 1.25 0 0 1 .75 12V2A1.25 1.25 0 0 1 2 .75Z"
        stroke="currentColor"
        strokeWidth="1.3"
      />
      <path d="M7 1v3h3M3.25 7h5M3.25 9.5h5" stroke="currentColor" strokeWidth="1.1" />
    </svg>
  )
}

/** The Apple logo, for the download buttons. styles.css draws the same shape on the README's. */
export function AppleIcon() {
  return (
    <svg width="13" height="16" viewBox="0 0 17 20" fill="currentColor" aria-hidden="true">
      <path d="M14.1 10.6c0-2.6 2.1-3.8 2.2-3.9-1.2-1.8-3.1-2-3.7-2-1.6-.2-3.1.9-3.9.9-.8 0-2-.9-3.3-.9-1.7 0-3.3 1-4.2 2.5-1.8 3.1-.5 7.7 1.3 10.2.9 1.2 1.9 2.6 3.2 2.6 1.3-.1 1.8-.8 3.3-.8 1.6 0 2 .8 3.3.8 1.4 0 2.3-1.3 3.1-2.5 1-1.4 1.4-2.8 1.4-2.9 0 0-2.7-1-2.7-4zM11.6 3c.7-.9 1.2-2 1-3.2-1 0-2.2.7-3 1.5-.6.7-1.2 1.9-1 3.1 1.1.1 2.3-.6 3-1.4z" />
    </svg>
  )
}

/** GitHub's mark, for the link to the repository. */
export function GitHubIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0 0 16 8c0-4.42-3.58-8-8-8z" />
    </svg>
  )
}

/** The pair of arrows on a macOS pop-up button. */
export function ChevronIcon() {
  return (
    <svg width="8" height="11" viewBox="0 0 8 11" fill="none" aria-hidden="true">
      <path
        d="M1 4 4 1l3 3M1 7l3 3 3-3"
        stroke="currentColor"
        strokeWidth="1.3"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}

/** A window with its sidebar, for the button that shows the files on a narrow screen. */
export function SidebarIcon() {
  return (
    <svg width="18" height="14" viewBox="0 0 18 14" fill="none" aria-hidden="true">
      <rect
        x=".75"
        y=".75"
        width="16.5"
        height="12.5"
        rx="2.5"
        stroke="currentColor"
        strokeWidth="1.4"
      />
      <path d="M6.5 1v12" stroke="currentColor" strokeWidth="1.4" />
    </svg>
  )
}

/** A pencil, for the button that shows the editor. */
export function EditIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none" aria-hidden="true">
      <path
        d="M9.6 1.9a1.4 1.4 0 0 1 2 0l.5.5a1.4 1.4 0 0 1 0 2L5 11.5l-3.2.7.7-3.2 7.1-7.1Z"
        stroke="currentColor"
        strokeWidth="1.3"
        strokeLinejoin="round"
      />
      <path d="M8.5 3 11 5.5" stroke="currentColor" strokeWidth="1.3" />
    </svg>
  )
}
