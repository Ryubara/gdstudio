---
areas: [ci, process]
---
# One red job explained the run and hid a second

2026-11-04

- **Saw:** Deadnight's #1086 had two red jobs on its first push. The report and the description blamed the run on
  `godot (8)`'s time limit; `godot (1)` was red too, with `mesh_instances` 2,610 of 2,600, and it reached the coordinator
  as a surprise on the next push.
- **Cause:** one failure had a good explanation that was not this change's fault, and the search stopped there. "That
  failure was not caused by this change" was written about a whole run after reading one job.
- **Fix:** list every job's conclusion before saying why a run is red
  (`gh run view <run> --json jobs --jq '.jobs[]|.name+" "+.conclusion'`) and read each failed job. While a run is still
  going, read one job with `gh api --allow-escape-sequences repos/<o>/<r>/actions/jobs/<id>/logs`: `--log-failed` waits
  for the whole run and prints nothing until then.
- **Docs:** this file.
