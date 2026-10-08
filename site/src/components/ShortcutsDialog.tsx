import { Fragment, useEffect, useRef } from "react"

import { shortcutGroups } from "@/lib/shortcuts"

/** The keyboard shortcuts, as a modal panel. Esc, Done, ? or a click outside closes it. */
export function ShortcutsDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const dialog = useRef<HTMLDialogElement>(null)

  useEffect(() => {
    const element = dialog.current
    if (!element) return
    if (open && !element.open) element.showModal()
    if (!open && element.open) element.close()
  }, [open])

  return (
    <dialog
      ref={dialog}
      className="shortcuts"
      aria-labelledby="shortcuts-title"
      onClose={onClose}
      // A click on the dialog itself, not its content, is a click on the backdrop around it.
      onClick={(event) => event.target === dialog.current && onClose()}
    >
      <div className="shortcuts-body">
        <h2 id="shortcuts-title">Keyboard shortcuts</h2>
        <div className="shortcut-groups">
          {shortcutGroups.map((group) => (
            <section key={group.title}>
              <h3>{group.title}</h3>
              <dl>
                {group.rows.map((row) => (
                  <div key={row.label} className="shortcut">
                    <dt>{row.label}</dt>
                    <dd>
                      {row.keys.map((alternative, index) => (
                        <span key={index} className="alternative">
                          {index > 0 && <span className="or">or</span>}
                          {alternative.map((combination, step) => (
                            <Fragment key={step}>
                              {step > 0 && <span className="or">{row.joiner ?? "/"}</span>}
                              {/* One key cap per combination, as macOS menus write ⌥⌘↓. */}
                              <kbd>{combination.join("")}</kbd>
                            </Fragment>
                          ))}
                        </span>
                      ))}
                    </dd>
                  </div>
                ))}
              </dl>
            </section>
          ))}
        </div>
        <div className="shortcuts-footer">
          <button type="button" className="done" onClick={onClose}>
            Done
          </button>
        </div>
      </div>
    </dialog>
  )
}
