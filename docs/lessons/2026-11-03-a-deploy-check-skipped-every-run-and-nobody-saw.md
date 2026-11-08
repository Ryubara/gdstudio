---
areas: [ci, backend]
---
# A deploy check that skipped every run kept Railway on an old build for hours

2026-11-03

- **Saw:** the maintainer asked why Railway was not deploying when pull requests merged (Deadnight #732).
  Railway ran `main c41e30f` while main had gone on by more than ten merges; every run since
  logged "66ec313 is not the head of main (cb2431b): skipped" in a green `deploy` job.
- **Cause:** the check that fixed #552 asked "is my commit the head of main?" when the deploy job started. A run takes
  10 to 25 minutes (godot shards, then web) and merges land every few minutes, so main had always moved on by the time
  a run got there: the rule was true for no run. It was tested for the case it was written for (an older commit is
  refused) and never for "does any run ever pass at the rate merges land". Nobody saw it because a skip is a green job
  with a notice, no check was red, and nothing compared what Railway runs with what main is; earlier lessons already
  said to name the live commit, but that stayed a thing an agent did after one fix, not a standing check.
- **Fix:** compare with the thing being replaced, not with a moving target: deploy when the live commit (the
  `cliMessage` of the service's newest `SUCCESS` deployment) is an ancestor of the run's commit, skip when the run's
  commit is an ancestor of the live one, and fall back to the head only when the live commit cannot be read
  (`deploy/check_head.sh`, `deploy/test_check_head.sh` in Deadnight). A guard that can skip must be tested with the
  real cadence in mind: a case where main moved on while the run was going and the run must still deploy.
- **Check:** when a job can skip itself, ask "how often will it skip?" with the real run time and merge rate; a job
  that skipped on every run is a failure, so give it a signal (the last deploy older than a few merges, or a notice
  that says how long since the last deploy). After a merge the maintainer waits on, read the live commit.
- **Docs:** Deadnight `docs/research/web-export.md` ("The deployed build is newer than the one it replaces"),
  [An older main build deployed over a newer one](2026-11-02-an-older-main-build-deployed-over-a-newer-one.md).
