---
areas: [tests, process]
---
# A capped output was read as proof of three suites, and the logs were deleted before CI passed

2026-11-04

- **Saw:** the pull request for Deadnight #987 said three GdUnit4 suites passed, and its numbers ("287 faults", the suite
  counts) could not be shown later: the run exited 0 but only one `Statistics` line (2 test cases) had been seen, and the
  logs were gone.
- **Cause:** the runner script cut its output with `head -8`, so two suites' summary lines were never printed, and the
  one seen was taken for all; the raw logs were then deleted to save disk before CI had passed. A grep count of fault
  lines was written into the pull request as if it were a count of faults.
- **Fix:** run each suite with its own log and read its own `Statistics` line (`2/10/5 test cases, 0 failures`); quote
  every suite's count in Testing; keep a one-line summary (the counts) in the scratch notes before deleting a log, and
  delete logs only after the checks are green. A number in a pull request says what was counted (`287 fault lines`),
  or is left out.
- **Docs:** [two test runs shared one log](2026-11-04-two-test-runs-shared-one-log.md).
