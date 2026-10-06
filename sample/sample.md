---
title: Markview sample
tags: [demo, markdown]
---

# Markview sample

A paragraph with **bold**, *italic*, ~~strikethrough~~, `inline code`, a
[web link](https://example.com), a [jump to the table](#a-table), and a
[link to another file](other.md). Press <kbd>⌘</kbd><kbd>F</kbd> to find.

![Local image](icon.png)

## Lists

- First item
- Second item
  - Nested item
- [x] Done task
- [ ] Open task

1. One
2. Two

> A plain blockquote.

> [!WARNING]
> Alerts render with a coloured title.

## Code

```swift
struct Greeter {
    let name: String
    func greet() -> String { "Hello, \(name)!" } // comment
}
```

```json
{ "light": true, "count": 42, "name": "markview" }
```

## A table

| Feature        | Status | Notes                 |
| -------------- | :----: | --------------------- |
| GFM tables     |   ✅   | aligned columns       |
| Live reload    |   ✅   | watches the file      |
| Dark mode      |   ✅   | follows the system    |

<script>document.title = "SCRIPT RAN"; document.body.innerHTML = "SCRIPT RAN";</script>
<img src="missing.png" onerror="document.body.innerHTML = 'ONERROR RAN'" alt="">

---

The end.
