---
areas: [tests, ci, process]
---
# A report said main's shard failed a step it had passed, and the logs behind its numbers were deleted

2026-11-05

- **Saw:** Deadnight #1231, reviewed by the coordinator. The page and kit lesson said main's shard 1 "fails in the
  late-round budget step, before the tests step runs", so main's green proved nothing. Main's runs 42011482212 and
  42016360272 passed both steps in shard 1. Separately, a 596-case plain run and a 595-case wrapper run of "the same"
  71-suite list could not be reconciled: the list and logs had been deleted.
- **Cause:** the claim came from two red main runs seen earlier and was written as if it were all of main, without
  reading the step conclusions of the green runs (`gh run view <id> --json jobs`). I emptied the scratch folder when
  the pull request opened, before anyone had checked the numbers, so the only copy of the list and logs was gone.
- **Fix:** read the step conclusions and the suites each shard held (`ci_test_shards.py --shard N` at the run's SHA)
  before explaining why a branch was green or red; the real reason main was clean was the mix of suites in shard 3.
  Keep the lists, logs and `results.xml` of a measurement until the pull request merges (name them in `SCRATCH.md`
  `Can go:` only after), and compare two runs by their case lists, not their counts.
- **Check for next time:** a sentence about "main" or "CI" in a page names the run ids it rests on; a count of two
  runs is quoted only when both lists are kept.
- **Docs:** [Leaks at exit in a GdUnit run](../engines/godot/test-exit-leaks.md#a-suite-that-only-names-a-class).
