---
areas: [ci, process]
---
# A rerun did not save a Pages deploy that timed out: a new commit did

2026-11-06

- **Saw:** the `docs` workflow failed on main in two repositories within an hour, at the `deploy` job with `mkdocs`
  green, and GitHub's status page showed no incident all the while. Deadnight #1358 (`102d639`): `Timeout reached,
  aborting!` after 10 minutes at `updating_pages`. The kit #758 (`4d2d303`): the same timeout at `syncing_files`.
- **What each retry did:** rerunning the failed job (`gh run rerun --failed`) gave `Deployment cancelled` after 8 to 9
  seconds, twice on Deadnight and once on the kit. Rerunning the whole workflow, which builds a new artifact of the same
  commit, gave `Deployment failed, try again later` after 100 seconds. The next commit on main deployed at the first
  try: Deadnight `1b7d5db`, in 6 minutes, with the failed runs' site still live until then.
- **Cause:** not known. It is on GitHub's side of the deploy: the artifact was the same 5 MB as the last good run and
  the build was clean. Why a rerun of that commit is refused was not found (the deployment is named after the commit, so
  a guess is that the rerun meets the attempt that timed out). Three reruns of one kind and one of the other are all
  this rests on, and the kit's own new commit is the next case.
- **Fix:** none in the code. After a Pages timeout, do not spend reruns: one rerun of the failed job at most, then land
  the next commit, which is the retry. The workflows have no `workflow_dispatch`, so a new push is the only other way
  in. The site stays up on the last good deploy, so a red `docs` run costs stale pages, not an outage: the automatic
  `CI failing on the default branch` issue stays open until a run is green and need not hold other merges.
- **Check next time:** read the deploy job's log before the rerun, and judge the error by what the retry did: a cancel
  within seconds is not a new fault in the docs.
