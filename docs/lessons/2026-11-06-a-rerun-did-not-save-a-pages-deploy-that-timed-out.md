---
areas: [ci, process]
---
# A rerun did not save a Pages deploy that failed, and a new commit does not always

2026-11-06

- **Saw:** the `docs` workflow failed on main at the `deploy` job on 4 commits of 10 across two repositories in two
  hours, with `mkdocs` green each time and GitHub's status page showing no incident: Deadnight `102d639` (#1358),
  `13ac676` (#1364) and `9c1b80c` (#1364), the kit `4d2d303` (#758). It stopped at a different stage each time:
  `Timeout reached, aborting!` at `updating_pages`, `syncing_files` and `deployment_queued`, and `Deployment failed, try
  again later` at `deployment_queued`.
- **What each retry did:**
    - Rerunning the failed job (`gh run rerun --failed`): 0 of 3, `Deployment cancelled` after 8 to 9 seconds, on both
      repositories.
    - Rerunning the whole workflow, which builds a new artifact of the same commit: 0 of 2, `Deployment failed, try again
      later` after 100 seconds and after 5 minutes.
    - The next commit on main: 2 of 3 (`1b7d5db` and the kit's `5f128d6` deployed; `9c1b80c` after `13ac676` did not).
- **Cause:** not known. It is on GitHub's side of the deploy: the artifact was the same 5 MB as the last good run and the
  build was clean. Why a rerun of a commit is refused was not found (the deployment is named after the commit, so a guess
  is that a rerun meets the attempt that failed). This rests on a handful of runs in one afternoon. The first version of
  this lesson said a new commit was the retry that works, from one case; the next two runs showed that was too strong:
  the deploys that passed may have been luck, and a commit landing after a failure is not proved to be why.
- **Fix:** none in the code. Do not spend reruns of the failed job. The workflows have no `workflow_dispatch`, so the
  other ways in are a whole rerun, some time later, or the next commit. The site stays up on the last good deploy (seen
  by its `Last-Modified`), so a red `docs` run costs stale pages, not an outage: the automatic `CI failing on the default
  branch` issue stays open until a run is green, and it need not hold other merges.
- **Check next time:** read the deploy job's log before any rerun, and count what each kind of retry did before writing
  a rule from one that worked: one success after a failure is not a cure.
