---
areas: [ci, tests]
---
# A hand-balanced shard list went stale within a day, and nothing warned before a shard hit the limit

2026-11-04

- **Saw:** `godot (6)` of Deadnight timed out at 15 minutes on #992 (14 min 50 s the run before); shard 1 had been
  cancelled the same way on `main`. Six shards, balanced by hand a day earlier (#775), with 28 new test scripts merged
  since. The heaviest shard was 650 to 816 s of suites, the lightest 230 to 340 s.
- **Cause:** the shard lists were folders and a table of seconds in a docstring, edited by hand, so each new script
  went to its folder's shard and each rebalance was a guess from two logs. Runners also vary by 1.5x from job to job (CPU
  suites; real-socket suites do not), so a shard that looked safe in one run was not in the next. Nothing measured a
  shard against the limit until the limit cancelled it with no test failing.
- **Fix:** deal the scripts out by seconds. A times file (seconds per script, rewritten from the job logs by one
  command, `ci_shard_time.py update`) feeds a longest-first deal to the lightest shard, so a new script lands
  somewhere light without a person naming it; the self-test fails when the workflow's matrix and the shard count
  differ. Eight shards for 3,250 s of suites (total / 480 s, rounded up, plus a margin). Each shard's last step
  annotates the job past 60 % of the limit and fails it past 80 %, so drift is red on the pull request that caused it.
- **Check for next time:** never write a list of what runs in which shard; keep the seconds and compute the lists. A
  job time limit gets a share check (warn, then fail) well under the limit, and the number of shards is checked
  against the total whenever the times are refreshed.
- **Docs:** [Test speed](../engines/godot/test-speed.md) (sharding); Deadnight's
  [CI time](https://github.com/Ryubara/deadnight/blob/main/docs/research/ci-time.md) ("Keeping the shards balanced").
