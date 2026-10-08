# Architecture

Lighthouse is a scheduler, a pool of checkers and a notifier, sharing one SQLite file.

## A check, end to end

```mermaid
sequenceDiagram
    participant S as Scheduler
    participant C as Checker
    participant DB as SQLite
    participant N as Notifier
    S->>C: check example.com
    C->>C: GET / (5s timeout)
    C-->>DB: latency 182 ms
    C--xS: timed out
    S->>C: retry 1 of 2
    C-->>N: still down
    N->>N: page on-call
```

## The life of a site

```mermaid
stateDiagram-v2
    [*] --> Up
    Up --> Suspect : check fails
    Suspect --> Up : retry passes
    Suspect --> Down : retries fail
    Down --> Up : check passes
```

## Storage

Every result is one row. A year of 30-second checks for 50 sites is about
52 million rows, or 1.4 GB, which SQLite handles without noticing.

```sql
CREATE TABLE results (
  site     INTEGER NOT NULL REFERENCES sites(id),
  at       INTEGER NOT NULL,        -- unix seconds
  latency  INTEGER,                 -- milliseconds, NULL when down
  status   TEXT    NOT NULL CHECK (status IN ('up', 'down', 'suspect'))
);
CREATE INDEX results_site_at ON results(site, at);
```
