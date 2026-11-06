---
areas: [ci, tests, process]
---
# A parked pull request merged without main turned main red

2026-11-06

- **Saw:** Deadnight's `ci` on `main` went red right after #1023, #1037 and #1213 were merged one after another. Each
  was green and CLEAN, and each had been parked for days. `test_the_rounds_go_in_only_when_the_reload_has_finished`
  failed every run: 8 of 8 alone, and in main's runs of all three merges. A pull request's own run failed with it, in a
  suite it had not touched.
- **Cause:** #1023 cut the pistol's reload from 1.3 s to 1.0 s, 60 ticks. #1292 had landed after #1023's last run and
  added a test that mashes Reload for 60 ticks, assuming the reload is still running. The two never ran together until
  the merge. CLEAN only says the text merges and the last checks passed; it says nothing about how old the base of
  those checks is. The coordinator skipped the refresh on purpose, to obey "push only when DIRTY or main broke a check".
- **Fix:** Deadnight #1313. The test mashes while the reload runs, inside a bound, so it holds for any reload time.
- **Check next time:** a parked pull request, or any whose last run is older than the merges since, is merged main into
  and run again before it lands, even when GitHub says CLEAN. That rule against needless pushes is for a queue that is
  moving. Merging several at once: refresh and land them one at a time, or expect to fix main. A test about "during" a
  timed action waits on the state of that action, never on a count taken from today's tuning.
