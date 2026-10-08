# Writing a custom check

A check is anything that answers "is it up?" in under the timeout.

```go
// A check that passes when the homepage mentions the shop is open.
func ShopOpen(ctx context.Context, site Site) Result {
	body, latency, err := fetch(ctx, site.URL)
	if err != nil {
		return Down(err)
	}
	if !strings.Contains(body, "We're open") {
		return Suspect("homepage says the shop is closed")
	}
	return Up(latency)
}
```

```swift
// The menu bar companion asks the same API.
struct Status: Decodable {
    let site: URL
    let up: Bool
    let latency: Duration?
}

let status = try await client.status(for: "example.com")
print(status.up ? "✓ \(status.site)" : "✗ \(status.site)")
```

```ts
// And the webhook receiver is a dozen lines.
export async function POST(request: Request) {
  const { site, status, since } = await request.json();
  if (status === "down") await pager.open({ site, since });
  return new Response(null, { status: 204 });
}
```
