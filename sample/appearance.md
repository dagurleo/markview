# Light and dark

READMEs on GitHub often carry two versions of a logo or a diagram, one for light pages and
one for dark. Markview shows the one that suits the window, and switches when the
appearance does. Each logo below says which one it is.

## A picture element

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="logo-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="logo-light.png">
  <img alt="Markview" src="logo-light.png">
</picture>

## Images for one appearance

Two images, of which only one shows:

![Markview](logo-light.png#gh-light-mode-only)
![Markview](logo-dark.png#gh-dark-mode-only)

## Centred and sized, as READMEs do it

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="logo-dark.png">
    <img alt="Markview" src="logo-light.png" width="240">
  </picture>
</p>

<p align="center">
  <img src="logo-light.png#gh-light-mode-only" width="180">
  <img src="logo-dark.png#gh-dark-mode-only" width="180">
</p>

The end.
