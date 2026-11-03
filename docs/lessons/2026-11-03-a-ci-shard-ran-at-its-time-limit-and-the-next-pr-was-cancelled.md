---
areas: [ci, tests]
---
# A shard of the test job ran at 14 of its 15 minutes on main, and a pull request that added minutes was cancelled

2026-11-03

- **Saw:** `godot (1)` of Deadnight #676 ended "The operation was canceled" at the 15 minute limit with no failing
  test. The log showed `Executed test suites: (124/124)` seconds before the cancel: every test had run.
- **Cause:** the shard (the `night` and `rules` folders) took 14 min 15 s on a green run of `main` already (suites 862 s
  plus a minute of setup). Nothing had gone wrong; the PR added 70 s of bot suites and the limit moved from near to
  over. `night` alone was 13 of the minutes, in four bot suites of 185, 78, 70 and 57 s; shards 2 and 3 took 8 min.
- **Fix:** `tools/ci_test_shards.py` can name single scripts of a folder (`MOVED`) and send them to another shard; the
  three shards are now about 10 min each. The balance is by seconds per script from the job log, not by folder.
- **Check for next time:** a job cancelled with no failure is a time limit: compare its length with the same job on the
  latest green `main` run (`gh run view <id> --json jobs`) before suspecting a hang, and read the per-suite times. A PR
  that adds minutes of suites checks its shard's total first.
- **Docs:** [CI time](https://github.com/Ryubara/deadnight/blob/main/docs/research/ci-time.md) (Deadnight; the section
  "The night folder is split by script").
