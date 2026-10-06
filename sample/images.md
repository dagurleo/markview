# Images

Markview shows an image at one point per pixel, as a browser does, and never
wider than the text column.

## Local files

A 96 px icon at its natural size:

![Markview icon](icon.png)

A 938 px screenshot, scaled down to the column:

![Screenshot](screenshot.png)

A local SVG:

![Diagram](diagram.svg)

## Sizes from HTML

Markdown has no syntax for a size, so `<img>` with a `width` does it:

<img src="icon.png" width="48"> <img src="icon.png" width="32"> <img src="icon.png" width="16">

<p align="center"><img src="screenshot.png" width="300" alt="centred, 300 wide"></p>

## Inline and linked

An icon inline in a sentence <img src="icon.png" width="20"> like this, and the
badge pattern, an image inside a link: [![Markview](icon.png)](https://example.com)
(click it).

[![Open the other sample](icon.png)](other.md)

## Remote

Fetched after the page is shown, so they appear a moment later:

![GitHub's avatar, a 200 px PNG](https://avatars.githubusercontent.com/u/9919?s=200&v=4)

![Build badge, an SVG](https://img.shields.io/badge/build-passing-brightgreen) ![Version badge](https://img.shields.io/badge/version-1.0-blue)

## In other places

- A list item with an image ![icon](icon.png)
- Another item

> A quote with an image:
>
> ![icon](icon.png)

| Icon | Name |
|---|---|
| ![icon](icon.png) | Natural size |
| <img src="icon.png" width="24"> | Sized with HTML |

## Missing

A file that does not exist shows its alt text: ![This image does not exist](nope.png)
