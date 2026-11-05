---
areas: [ci]
---
# A trial run of a job that opens issues opened the issue the real job owns

2026-11-05

- **Saw:** the throwaway `push` trigger used to try Deadnight's scheduled `ui-windowed` workflow on its branch ran the
  `report` job for real: it opened "Windowed UI suites need a look" (#1209) from a seven-suite trial, and a trial of the
  could-not-run path opened another (#1210). The coordinator had to block both on the pull request, and a later clean
  trial would have closed the real issue falsely.
- **Cause:** the issue step keyed on the state of the run, not on what the run was. A run of a few suites, or of a
  branch, says nothing about the folder or the schedule.
- **Fix:** a run of named suites (`workflow_dispatch` with a list) never opens or closes the issue, and a trial's issue
  has a title of its own (`... (trial run of the branch)`) that the trial itself closes on its clean path; the trial
  trigger is removed before the pull request. Close any trial issue before the pull request lands, by hand with a
  reason and no comment. Check for next time: before pushing a trial of a job that writes somewhere shared (issues,
  deploys, releases), list what it writes and give the trial its own target.
- **Docs:** Deadnight `docs/research/windowed-ui-ci.md` (the job's report paths).
