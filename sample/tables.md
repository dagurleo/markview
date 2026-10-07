# Tables

## Sizes

A small table takes only the width it needs:

| Key   | Value |
|-------|------:|
| one   |     1 |
| two   |    22 |
| three |   333 |

A wide one spans the column and wraps its cells:

| Setting | Description | Default |
|---|---|---|
| `columnWidth` | The widest the text column gets, so lines stay a comfortable length to read even on a very wide window | 736 |
| `bodySize` | The size of body text, in points | 16 |

## Alignment

| Left | Centre | Right |
|:-----|:------:|------:|
| a | b | c |
| longer text | longer text | longer text |

## Content in cells

| Kind | Example |
|---|---|
| Emphasis | **bold**, *italic*, ~~struck~~ |
| Code | `let x = 1` |
| Link | [example](https://example.com) |
| Image | ![icon](icon.png) |
| Line break | first line<br>second line |

An empty cell keeps its place, the corner of a comparison too:

| | Small | Large |
|---|:-:|:-:|
| Fits in a bag | ✓ | |
| Needs a van | | ✓ |

## In quotes and alerts

> A quoted table:
>
> | A | B |
> |---|---|
> | 1 | 2 |

> [!TIP]
> An alert can hold a table too.
>
> | Yes | No |
> |---|---|
> | ✅ | ❌ |

## HTML table

<table>
  <tr><th>Header</th><th colspan="2">Spanning header</th></tr>
  <tr><td rowspan="2">Two rows</td><td>b1</td><td>c1</td></tr>
  <tr><td>b2</td><td>c2</td></tr>
</table>

## Many rows

| # | Name | Status |
|--:|------|--------|
| 1 | alpha | done |
| 2 | beta | done |
| 3 | gamma | in progress |
| 4 | delta | planned |
| 5 | epsilon | planned |
| 6 | zeta | done |
| 7 | eta | done |
| 8 | theta | in progress |
| 9 | iota | planned |
| 10 | kappa | done |
| 11 | lambda | done |
| 12 | mu | planned |
