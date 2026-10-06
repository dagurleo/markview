# Extensions

Dialects add things CommonMark and GitHub lack. Markview understands these.

## Footnotes

Footnotes[^1] get a number and a link to the note at the end of the page, and a
named one[^named] works too. The same note again[^1] keeps its number.

[^1]: The note text, with *Markdown* in it.
[^named]: A named footnote.
    With a second line.

## Emoji shortcodes

:tada: :rocket: :+1: :white_check_mark: :warning: :coffee: and an unknown
:not_an_emoji: stays as written, as does `:code:` in a code span.

## Wiki links

Obsidian-style links: [[other]], [[other|with a label]], [[other#Other file]]
to a heading, an unresolved [[missing page]], and an embedded image ![[icon.png]].

## Highlight

Text with ==a highlighted phrase== in it, and `==not in code==`.

## Callouts

> [!tip] A custom title
> Obsidian callouts carry a title on the marker line.

> [!info]
> More kinds than GitHub's five: info, abstract, todo, success, question,
> failure, danger, bug, example and quote.

> [!success] Done
> Green.

> [!question] Why?
> Yellow.

> [!danger]- The fold sign is ignored
> Red, and always shown expanded.

> [!example]
> Purple.

> [!quote]
> Grey.

## Heading ids

### A heading with a custom id {#custom-id}

A [link to it](#custom-id) scrolls here.

## Admonitions

:::warning Docusaurus style
Lines until the closing fence become a callout.

With a second paragraph and `code`.
:::

!!! note "MkDocs style"
    The indented body becomes the callout.

    With a second paragraph.

After the admonitions.

## Headings in other files

[Open the other sample at its heading](other.md#other-file).
