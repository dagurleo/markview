# Diagrams

A `mermaid` code block is drawn as a diagram, natively by MermaidKit, in the light or
the dark colours of the window.

## Flowchart

```mermaid
flowchart LR
    A[Open a file] --> B{Markdown?}
    B -->|Yes| C[Show it]
    B -->|No| D[Reveal in Finder]
    C --> E((Done))
    D --> E
```

## Sequence

```mermaid
sequenceDiagram
    participant Finder
    participant Markview
    participant Browser
    Finder->>Markview: Open README.md
    Markview-->>Finder: Window
    Markview->>Browser: Web link
    Note right of Browser: Links to the web open here
```

## Class

```mermaid
classDiagram
    class NSDocument
    class MarkdownDocument {
        +String markdown
        +read(data)
    }
    NSDocument <|-- MarkdownDocument
    MarkdownDocument --> ViewerWindowController : shows
```

## State

```mermaid
stateDiagram-v2
    [*] --> Closed
    Closed --> Open : open
    Open --> Rendering : changed on disk
    Rendering --> Open
    Open --> Closed : close
```

## Entity relationship

```mermaid
erDiagram
    FOLDER ||--o{ DOCUMENT : holds
    DOCUMENT ||--o{ IMAGE : shows
    DOCUMENT }o--o{ DOCUMENT : links
```

## Gantt

```mermaid
gantt
    title Releases
    dateFormat YYYY-MM-DD
    axisFormat %b %d
    tickInterval 1week
    section Viewer
    Native engine     :done, 2026-09-20, 14d
    Markdown gaps     :done, 2026-10-04, 2d
    Math and diagrams :active, 2026-10-06, 3d
    section Release
    Notarize          :2026-10-09, 2d
```

## Pie

```mermaid
pie title Time spent
    "Reading" : 70
    "Writing" : 20
    "Waiting" : 10
```

## Mind map

```mermaid
mindmap
  root((Markview))
    Markdown
      Tables
      Footnotes
      Math
    Viewer
      Go menu
      Find
    Quick Look
```

## A diagram in a quote

> ```mermaid
> graph TD
>     Quote --> Diagram
> ```

## Mistakes

A diagram Mermaid cannot read stays as written:

```mermaid
graph TD
    A -- this arrow goes nowhere
```
