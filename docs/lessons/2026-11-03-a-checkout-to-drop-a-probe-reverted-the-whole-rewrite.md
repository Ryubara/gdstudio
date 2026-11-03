---
areas: [tools, general]
---
# A checkout meant to drop a timing probe reverted the whole rewrite

2026-11-03

- **Saw:** after timing prints went into an uncommitted rewrite of a file, `git checkout <file>` to drop them put the
  file back to `main`, and the rewrite had to be written again.
- **Cause:** `git checkout <file>` restores the last commit, not "the file before my last edit".
- **Fix:** copy the file to the scratch folder before instrumenting it and copy it back after, or remove the probe lines
  with an edit; commit (or `git stash`) a rewrite before probing it.
- **Docs:** this page.
