---
areas: [ci]
---
# The shard report asked for a ninth shard because its times were old

2026-11-04

- **Saw:** Deadnight's `ci_test_shards.py --report` flagged all 8 shards at 454 s against the 440 s budget ("add a
  shard") while nothing failed and main's real shards took 380 to 559 s with setup.
- **Cause:** the report deals the scripts by the seconds in the times file, and that file was days old: 28 scripts at the
  default and heavy suites that had since been made faster. The suite was not what had grown.
- **Fix:** refresh the file first (`ci_shard_time.py update` on the `tests.log` of three green `main` runs), then read the
  report: 3,254 s and 414 s a shard, none flagged, no shard added and the budget left alone. Reduce the downloaded
  artifacts (about 745 MB for 24) to the file and delete them in the same step.
- **Check for next time:** a report that says "add a shard" is believed only after the times file is refreshed from
  recent runs; the order is refresh, report, then add a shard (Deadnight `docs/research/ci-time.md`).
- **Docs:** [CI time](https://github.com/Ryubara/deadnight/blob/main/docs/research/ci-time.md) ("Keeping the shards
  balanced").
