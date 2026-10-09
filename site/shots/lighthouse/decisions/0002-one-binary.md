# 2. Ship one binary

**Status:** accepted · **Date:** 2026-04-18

Scheduler, checkers and notifier run in one process. Splitting them would buy
scaling we don't need, at the cost of a queue we'd have to watch, too.
