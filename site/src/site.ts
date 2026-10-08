export const SITE_NAME = "Markview"
export const REPOSITORY = "https://github.com/dagurleo/markview"

/** The disk image of a release, as scripts/release.sh names it. */
export function downloadURL(version: string): string {
  return `${REPOSITORY}/releases/download/v${version}/Markview-${version}.dmg`
}
