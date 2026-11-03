---
areas: [ci, tools]
---
# A run cancelled by a newer push counted as earlier work that went wrong

2026-11-03

- **Saw:** the `body` check of kit #244 demanded a `Lessons:` line: "this pull request corrects earlier work (build-ok
  failed on an earlier commit of it)". On that commit `build-ok` had failed only because its run was cancelled when
  the next push started a new one (`RESULTS: cancelled`). Nothing had gone wrong.
- **Cause:** `collect_history` in `.github/scripts/groundwork.py` read each earlier commit's check runs as
  `name, conclusion` and counted a watched check whose conclusion was `failure`. `build-ok` runs `if: always()` and
  exits 1 on a `cancelled` result of the jobs it needs, so a cancellation by `concurrency: cancel-in-progress` shows
  up as a plain failure of the one required check. The rule could not tell the two apart.
- **Fix:** `failed_checks` reads the check suite of every run too. A failed watched check is skipped when the other
  jobs of its own run include a cancelled one and none that failed; a failure beside a failed job, or with nothing
  cancelled, still counts. Tests cover a cancelled run, a real failure, a cancellation in another run, and the history
  of a pull request with both. Games take the change with `gds sync`.
- **Check:** when a rule reads a check's conclusion as "someone made a mistake", ask what else produces that
  conclusion (a cancelled run, a skipped needed job, a runner lost) and test each; a conclusion-only signal needs the
  jobs behind it.
