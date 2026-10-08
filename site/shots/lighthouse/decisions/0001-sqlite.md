# 1. Store results in SQLite

**Status:** accepted · **Date:** 2026-03-02

We expected to need Postgres. A year of checks for fifty sites is 1.4 GB, which
SQLite writes at 40,000 rows a second on a laptop. One file is also one backup.
