# Code

Inline `code` sits in the text, as in `let x = 1` or `./build.sh install`.

## Languages

```swift
struct Greeter {
    let name: String
    func greet() -> String { "Hello, \(name)!" } // Swift
}
```

```python
def fib(n: int) -> int:
    """Python"""
    return n if n < 2 else fib(n - 1) + fib(n - 2)
```

```javascript
const greet = (name = "world") => `Hello, ${name}`; // JavaScript
export default greet;
```

```bash
#!/bin/bash
set -euo pipefail
for f in *.md; do echo "$f"; done   # shell
```

```json
{ "name": "markview", "version": "1.0", "native": true, "size": 42 }
```

```yaml
name: markview
engines: [native, web]
native: true
```

```html
<p class="note">An <em>HTML</em> snippet</p>
```

```css
.note { color: #1e3a8a; font-weight: 600; }
```

```diff
- removed line
+ added line
```

## Without a language

```
Plain text, no highlighting.
```

Indented by four spaces:

    also a code block

## Long lines

A line too long for the box wraps, and the continuation is indented:

```swift
let configuration = URLSessionConfiguration.default; configuration.timeoutIntervalForRequest = 30; configuration.httpAdditionalHeaders = ["Accept": "application/json"]
let short = 1
```

## In lists and quotes

1. Build it:

   ```sh
   ./build.sh
   ```

2. Install it:

   ```sh
   ./build.sh install
   ```

> ```json
> { "quoted": true }
> ```
