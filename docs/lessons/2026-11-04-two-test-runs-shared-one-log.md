---
areas: [tests, tools]
---
# Two test runs wrote one log and a pass could not be told from a failure

2026-11-04

- **Saw:** Deadnight's #991 log held two `Overall Summary` blocks for the same 414 cases, one with 0 failures and exit 0,
  one with 2 failures and exit 100, and no `FAILED` line in either. Which run was which code could not be read back.
- **Cause:** a helper script sent every run to one fixed log with `>`, and a run started before an edit was probably
  still going when the next began, so both wrote to the same file. The script's `| tail` hid the exit code as well.
- **Fix:** one run at a time: print the commit (`git rev-parse --short HEAD`) before it and count the summaries after
  (`grep -c "Overall Summary"` is 1), or give each run its own log. A second summary voids the log: run it again alone.
- **Docs:** [Lessons](index.md): no page covers it yet; this file is the record.
