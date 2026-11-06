---
areas: [ci, process]
---
# A pull request landed on auto-merge before the dispatch that was its proof had finished

2026-11-06

- **Saw:** Deadnight #1324 fixed a red nightly. Its test plan was a dispatch of the nightly workflow on the branch
  (100 nights a cell, about three hours on a busy queue). The dispatch's `leak` job finished first and failed on a
  limit the pull request had said did not fail on CI; by then the pull request was merged, on `--auto`.
- **Cause:** the notes of the task said auto-merge would stay off until the dispatch was read, and then, with the
  pull request's own checks green and a partial reading in hand (five cells of twelve), the flag went on: the checks
  were taken for the proof, and the partial reading for the whole. The dispatch is a job nobody gates on, so nothing
  stopped the merge.
- **Fix:** none can be automatic; the rule is written down. A pull request whose test plan is a long run does not get
  `--auto` until every job of the run has been read (`gh run view <id> --json jobs`: no job queued or in progress, each
  conclusion explained), and it says in the body which jobs were read. When the proof is too long to wait for, shorten
  it (`nights=10` still runs every job) rather than merge on part of it.
- **Check next time:** before `gh pr merge --auto`, `gh run view` on the proof run and the list of jobs that are not
  `completed`; the list must be empty.
- **Docs:** this page.
