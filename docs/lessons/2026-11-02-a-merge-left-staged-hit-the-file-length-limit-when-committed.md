---
areas: [process, tests]
---
# A merge of main left staged for hours failed lint the moment it was committed

2026-11-02

- **Saw:** deadnight #410 (two-weapon carry) had 248 staged files, `MERGE_HEAD` set, "All conflicts fixed but you are
  still merging", no pull request. The first `git commit` failed `gdlint`: `night_server.gd` 1016 lines (limit 1000), a
  snapshot comment over 100 columns, `_is_goal` with 7 returns (limit 6).
- **Cause:** the earlier agent resolved the conflicts and kept editing instead of committing the merge, so main's
  growth (989 lines in `night_server.gd`) plus the branch's additions only met the lint limits at commit time. Pre-commit
  checks the staged tree, so unstaged work does not hide it. Another 13 commits of main then landed while it sat.
- **Fix:** commit the merge the moment the conflicts are resolved, before new work; then merge main again. Under the
  file-length limit, move a helper to the class that already owns the subject (`MachineOffers.replaces` took what the
  server file could not hold) instead of squeezing lines; merge two early returns into one condition for the return
  count; `gdformat` rewrites the staged file, so `git add -A` and commit again.
- **Docs:** [Agents](../studio/agents.md).
