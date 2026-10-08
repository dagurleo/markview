# Getting started

Lighthouse needs nothing but itself. Install it, point it at a site, and leave it running.

## Install

```sh
brew install lighthouse        # macOS
curl -fsSL lighthouse.dev/i | sh   # Linux
```

## Your first check

```yaml
# lighthouse.yml
sites:
  - url: https://example.com
    every: 30s
    notify: [slack:#ops, email:oncall@example.com]
  - url: tcp://db.internal:5432
    every: 1m
```

Run `lighthouse watch -c lighthouse.yml` and keep the terminal open, or
`lighthouse service install` to start it with the machine.

> [!NOTE]
> The first check runs immediately; after that Lighthouse spreads checks over the
> interval so that a hundred sites never fire in the same second.
