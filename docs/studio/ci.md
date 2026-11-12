# CI and deploys

<!-- new section: the studio folder had no page on how CI and deploys run on the default branch; the hooks page covers what
runs on the machine -->

How the continuous integration runs on the default branch and how a merge reaches the live deploy: every commit of
`main` is checked, and a deploy that can skip itself is sized against the real merge rate. Below are the pull request
checks and their reruns, the time limits and shards of the test jobs, how to read a red run, and how a workflow file is
checked before its first run.

## Runs on the default branch {#main-runs}

<!-- new section: the studio pages cover hooks, issues and the workspace; nothing held how CI and deploys run on the
default branch -->

**No pull request lands on a red main, auto-merge included.** While a `CI failing on the default branch` issue is open
([Merging on a red main](hooks-red-main.md#red-main)), the `main-green` check fails on every open pull request but the fix
forward, whose body closes one of those issues by a closing keyword (`Fixes #N`); the `Main` ruleset requires it from
GitHub Actions (`merge.red_main` in `.github/conventions.yml`), so no route merges past it, not even auto-merge turned
on earlier. Two workflows give it:

- `.github/workflows/main-green.yml` runs on each pull request event (`pull_request_target`: opened, reopened,
  synchronize, edited) and reads the open issues and the body when it runs. A body edited to add `Fixes #N` re-runs it.
- `.github/workflows/main-green-sweep.yml` writes the check again on every open pull request into `main`, through the
  Checks API, when a red issue changes: `ci-failure.yml` dispatches it right after filing the issue (an issue filed with
  a workflow's token starts no `issues` workflow), and closing, reopening, renaming or deleting one starts it as an
  `issues` event. It first waits for `main-green` runs still going, so one that read the issues before the change cannot
  put the old answer back. Run it by hand (`gh workflow run main-green-sweep.yml`) after the ruleset first requires the
  check, so open pull requests do not wait on a check that never ran, or after an outage that dropped events.

A pull request therefore merges once the issue closes, with no push: its auto-merge stays on and lands when the sweep turns
`main-green` green. `main-green` stays out of `merge.required_checks`, so `pr-status` does not call a red main the pull
request's failure. Tests: `python/tests/test_main_green.py` (the steps run under bash against a fake `gh`).

- **Approach:** Stop a merge that must not happen with a check the ruleset requires, not only with a guard on the merge
  command: auto-merge turned on before main went red merges with no command at all. **Watch out for:** #1276 had
  auto-merge on, went green and landed while #1279 (main red) was open; the hook guard of #1241 refuses `gh pr merge`
  and the merge API, never a merge GitHub makes by itself. **Seen:** gdstudio #1302, 2026-11-11 (fix: the required
  `main-green` check and its sweep).
- **Approach:** Use `cancel-in-progress` for pull requests only; every run on the default branch finishes. **Watch out
  for:** main's CI cancelled its run when the next merge landed, so four of five merges in three minutes were never
  checked. **Seen:** Deadnight #290, 2026-11-01 (fix: the evening review found it (Deadnight #290) and Deadnight #296
  kept the cancel to pull requests); gdstudio #919, 2026-11-10 (the kit's own `ci.yml` grouped by ref and cancelled
  for `main` too: 4 of the last 30 runs on `main` were cancelled; fix: the group is the commit for a push, and
  `test_workflow_concurrency.py` fails any workflow that runs on `main` and can cancel there, unless a
  `# cancels-on-main:` comment gives the reason, as `docs.yml` does: a cancelled site build is replaced by the next).
- **Approach:** Read a green head as checked against the main it was built on: before landing one whose base is older
  than main, merge main in when main has changed a file the pull request also changes, even where the merge is clean,
  and push once. **Watch out for:** #1250 added two cases to `test_ai_spawner.gd` and landed; #1243's green head,
  built before that, added one more and auto-merged 24 minutes later, so the suite reached 21 public methods and
  main's gdlint failed though neither pull request had. Auto-merge never merges main in, so a pull request with it on
  needs the same refresh by hand when main changes one of its files. **Seen:** gdstudio #1279, 2026-11-11 (fix: the
  suite split in two); gdstudio #1312, 2026-11-11: #1296 auto-merged on a head built before #1239 and
  `character_animation.gd` reached 1001 lines (fix: a comment reflowed; the split is #1287).
- **Approach:** When a job can skip itself, work out how often it skips at the real run time and merge rate and give a
  recurring skip a signal; deploy any green commit newer than the live one, and read the live commit after a merge
  someone waits on. **Watch out for:** deploy jobs skipped unless their commit was still main's head; CI took 10 to 25
  minutes and merges came every few, so every run skipped and Railway fell 13 merges behind, each skip a green job. The
  guard was tested for an older commit refused, never for any run deploying. **Seen:** Deadnight #732, 2026-11-03 (fix:
  a run deploys when the live commit (the newest `SUCCESS` deployment's `cliMessage`) is its ancestor and skips when
  its own commit is the live one's ancestor; `deploy/check_head.sh` and a case where main moved on during the run).
- **Approach:** For any job that publishes "the latest" of something, ask what happens when a run of an older commit gets
  there last, give each deploy job its own `concurrency` group, and compare the run's commit with what it replaces at
  the moment of publishing; test the refusal with the live commit injected so it fails first without GitHub. **Watch out
  for:** a `concurrency` group serializes deploys and never orders them, so two quick merges finished their tests in
  either order and an older commit deployed over a newer one; the live game went back before the hand grips. **Seen:**
  Deadnight #552, 2026-11-02 (fix: the deploy job asks, when it starts, whether its commit is still the head of `main`;
  #732 above replaced that rule, which skipped every run).

## A game's pull request needs the kit's {#kit-first}

<!-- new section: the runs section covers the default branch; nothing covered a game's CI checking out the kit's main -->

- **Approach:** Merge the kit change first, then rerun or push the game's pull request, and read `gh run view
  --log-failed` before changing anything (a rerun replays the old event, see [the pull request checks](#pr-checks)).
  **Watch out for:** a game's CI checks out the kit's `main`, and a game pull request written before the kit pull
  request that added `--no-mcp` had merged failed in 19 s with `unrecognized arguments`. **Seen:** Deadnight,
  2026-11-01 (fix: the kit change merged first and the job reran).

## The pull request checks {#pr-checks}

<!-- new section: the page held how the default branch runs; nothing held how the checks on a pull request behave when
they are rerun, replayed or read from another branch -->

- **Approach:** Run a new description rule's checker locally on the pull request's own body (`groundwork.py check-body
  --body <file> --title <file>`) before merging it, then edit each open pull request's description to re-run `body`.
  **Watch out for:** `pr.yml` runs on `pull_request_target`, so the checker is always the base branch's: a new rule
  applies only after it merges, and only to pull requests opened or edited later; the pull request that added the Issues
  affected rule passed without being checked by it. **Seen:** Deadnight, 2026-11-01 (fix: the new checker run on its own
  body).
- **Approach:** After `gh pr edit`, wait for the `pr-rules` run the edit started; never rerun an older run, and if you
  did, rerun the newest so it finishes last. **Watch out for:** `pr.yml` reads the body from the event, so a rerun
  replays the old event with the old body and fails again with the same reason. **Seen:** Deadnight #655, 2026-11-03.
- **Approach:** Merge `main` into every branch whose head lacks a workflow change (`git merge-base --is-ancestor
  <change> <head>`) and push once; that is a reason to push, like a conflict. **Watch out for:** a run takes its job
  limit from the branch's own `ci.yml`, so two pull requests rerun, then closed and reopened, after `main` raised the
  `godot` limit from 20 to 30 minutes were still cancelled at 20. **Seen:** Deadnight #501, #507 and #525, 2026-11-02
  (fix: main merged into each branch).
- **Approach:** When a push shows `pr`, `hold` and `pr-status` but no `ci`, `conventions` or `docs`, read `gh pr view N
  --json mergeable`: on `CONFLICTING` run `gds merge-main` and push; on `MERGEABLE` wait five minutes for the late runs
  before closing and reopening. **Watch out for:** `pull_request` workflows run on the merge commit GitHub builds,
  `pull_request_target` ones on the base, so a conflict starts no `ci` at all and a slow merge build delays it, while
  the base-side checks run at once; a close and reopen raced the late run and one cancelled the other (one group per
  pull request). **Seen:** gdstudio #912 and #951, 2026-11-10 (clean merges; `ci` came 2 and 4 minutes late, after the
  reopen); gdstudio #988 (opened in conflict: no `ci` until a merge of main). Found for gdstudio #1003 in the run list.
- **Approach:** Before you wait on a check that `gh pr checks` still shows as pending, read its run (`gh run view <id>
  --json status,conclusion,headSha`); when that run is `completed` and `success` on the pull request's head, and
  another entry of the same name passed, the check is done. **Watch out for:** after `gh pr edit` a second `title` entry
  stayed `IN_PROGRESS` in the rollup while its run had finished green, so a loop over `gh pr checks` waited on a check
  that would never change, with the pull request already `CLEAN`. **Seen:** gdstudio #1000, 2026-11-10 (run
  42893048440).
- **Approach:** Judge a check on a commit by its newest run alone (`pr_status.py`'s `newest_runs`: by start time,
  then id), and when a status label disagrees with `gh pr checks`, list the commit's check runs with their suites.
  **Watch out for:** `check-runs?filter=latest` is the latest run of each check per check suite, and every event
  of a pull request (opened, edited, pushed to) makes its own suite, so `commits`, failed twice on a description
  whose Model line lacked a model and passed after the edit, came back three times and `S-ci-failing` stayed on a
  pull request whose only red check was `hold`. **Seen:** gdstudio #1265, 2026-11-12
  (`test_a_check_that_passed_after_the_description_was_edited_is_not_failing`).

## Reruns {#reruns}

<!-- new section: the page held how the default branch runs; nothing held what a rerun does to the run that replaced it
-->

- **Approach:** Tie a delayed rerun to the pull request's head: the loop checks that the run's `head_sha` is still the
  head and does nothing if it is not; after a push stop any loop for that branch, and to retry cancel the old run, wait
  for the new run to stop, then `gh run rerun --failed` on it. **Watch out for:** a loop kept for a run id restarted the
  run of an old commit after a merge of `main` was pushed, took the branch's concurrency slot and cancelled 15 jobs of
  the new commit, so a commit that had not failed showed a wall of red. **Seen:** Deadnight #1127, 2026-11-04.
- **Approach:** Read the deploy job's log before any rerun of a failed Pages deploy, spend no reruns of the failed job,
  wait, then rerun the whole workflow once, and count what each kind of retry did before writing a rule from one that
  worked. **Watch out for:** the `docs` deploy failed on 5 of 11 commits across two repositories with a green build and
  no incident on GitHub's side; rerunning the failed job worked 0 of 3 times, the whole workflow 2 of 4, and "a new
  commit is the retry" came from one case. The site stays up on the last good deploy, so a red `docs` run costs stale
  pages, not an outage. **Seen:** gdstudio #758 and #763, Deadnight #1358 and #1364, 2026-11-06 (fix: none in code; the
  cause was not found).
- **Approach:** To clear runs stuck in the queue after an Actions outage, pick each one by its own state and jobs
  (`status` queued and no job started, from `actions/runs/<id>/jobs`), never by `created_at`; a run that the API calls
  completed while it shows queued takes no cancel, so a new commit on its branch (a merge of `main`) is the retry.
  **Watch out for:** a rerun keeps the original run's `created_at`, so a sweep of "queued since before 20:40" cancelled
  two live reruns (#1040's test job 14 minutes in, and #1239's capture rerun) and could not touch the seven stuck runs
  it was meant for. **Seen:** gdstudio #1040, #1239 and #1245, 2026-11-11.
- **Approach:** When a run fails uploading an artifact while GitHub reports an Actions incident, wait until its status
  page shows Actions operational, then rerun once. **Watch out for:** a rerun during the outage failed at the same
  upload step, spending a run and the branch's slot for nothing. **Seen:** gdstudio #1040, 2026-11-11.

## Time limits and shards {#shards}

<!-- new section: nothing on this page held the time limits of the test jobs and how their shards are sized -->

- **Approach:** Before suspecting the last test of a cancelled job, compare the cancel time with the job's start plus
  its `timeout-minutes` and with the same job on the latest green `main` run (`gh run view <id> --json jobs`), and read
  the per-suite times; keep the limit well above the measured time. **Watch out for:** a cancel lands wherever the run
  is, so the last log line names an innocent test: a job cancelled 15 ms after `STARTED` of one suite had run `124/124`
  suites seconds before the limit, and a pull request that added 70 s of suites pushed a shard from 14 min 15 s over
  its 15. **Seen:** Deadnight #488, 2026-11-02 (fix: limit 30 minutes, #501); Deadnight #676, 2026-11-03.
- **Approach:** Never write a list of which scripts run in which shard: keep the seconds per script (a times file
  rewritten from the logs of green `main` runs, `ci_shard_time.py update`), deal them longest-first, size the shard
  count from the total (`total / 480 s` rounded up, plus a margin), and fail a shard's last step past 80% of its limit.
  **Watch out for:** three shards rebalanced by script were back at the limit within a day, and six hand-balanced ones
  within another: the suite grows with every merge, runs vary by 15% or more between runners, and moving a few scripts
  only delays the limit. **Seen:** Deadnight #676, 2026-11-03; Deadnight #775 and #992, 2026-11-04 (fix: eight shards
  dealt by seconds, the self-test failing when matrix and count differ).
- **Approach:** Refresh the times file from the logs of three recent green `main` runs before believing a report that
  asks for another shard, and reduce the downloaded artifacts to the file and delete them in the same step. **Watch out
  for:** a report flagged all eight shards at 454 s against 440 s because its times were days old; after the refresh
  none was flagged and no shard was added. **Seen:** Deadnight, 2026-11-04 (fix: the order refresh, report, then add a
  shard).

## Reading a red run {#red-run}

<!-- new section: nothing on this page held how to read a failed run or a red main -->

- **Approach:** List every job's conclusion before saying why a run is red (`gh run view <run> --json jobs --jq
  '.jobs[]|.name+" "+.conclusion'`) and read each failed job; while the run is going, read one job with `gh api
  --allow-escape-sequences repos/<o>/<r>/actions/jobs/<id>/logs`, since `--log-failed` waits for the whole run. **Watch
  out for:** a report blamed one job's time limit for the whole run while a second job was red on a count 2,610 over
  2,600, and it reached the coordinator as a surprise on the next push. **Seen:** Deadnight #1086, 2026-11-04 (fix: the
  list of jobs read before any explanation); gdstudio #1274, 2026-11-11 (a red `build-ok` handed over unread: the
  template job's `gdlint` on a suite the branch never touched, red on `main`, fixed there by #1282).
- **Approach:** Before auto-merge on a branch that is behind, `gds merge-main`, then run the tests that other merges
  added or changed since the branch's base (`git diff --name-only <base>..origin/main -- 'game/tests/**/test_*.gd'`)
  beside the branch's own; the pull request that moves data rewrites a list of known failures keyed by it; reproduce a
  red `main` where it ran (the pinned Linux Godot in WSL). **Watch out for:** `main` was red for seven merges in a row
  though each pull request was green alone: a test met a rule it did not know, 19 list entries keyed by coordinates were
  stale, a bot night passed on Windows and failed on the Linux runner. **Seen:** Deadnight #958 to #964, 2026-11-04
  (fix: the tests fixed in the pull request that moved the data).
- **Approach:** A test about "during" a timed action waits on the state of that action, never on a count taken from
  today's tuning. **Watch out for:** a pull request parked for days cut a reload from 1.3 to 1.0 s, a test added since
  mashed Reload for 60 ticks, and `main` went red on the merge though both were green and CLEAN. **Seen:**
  Deadnight #1023, #1037 and #1213, 2026-11-06 (fix: Deadnight #1313, the test mashes while the reload runs).
- **Approach:** When a file is within about 20 lines of a lint limit and more than one open pull request touches it,
  move a whole piece out instead of tightening comments, tell the agents who start there, and run the lint in CI so a
  limit is a guarantee about `main`. **Watch out for:** `night.gd` stood at 995 of 1,000 and each pull request fitted
  alone but not after a merge of `main`; `gdlint` ran only in local hooks, so two merges put `lobby_screen.gd` over
  1,000 with `main` green and blocked three pushes of branches that never touched it. When a push is refused for a file
  the branch never touched, read `main` first; never push past the hook. **Seen:** Deadnight #1128 and #1129,
  2026-11-04; Deadnight #1225, 2026-11-05 (fix: a piece moved out, `gdlint` added to CI).
- **Approach:** Fetch a CI tool as its release binary, check it against a sha256 written in the workflow (from the
  release's checksums file) and retry the download (`curl -fsSL --retry 6 --retry-all-errors --retry-delay 10`); never
  `go install` a tool in CI. For `not in gzip format`, ask the URL for its status (`curl -sSIL`) first. **Watch out
  for:** `go install ...actionlint@v1.7.12` needed Go 1.25, `GOTOOLCHAIN=auto` tried to fetch it and `sum.golang.org`
  answered `404`, so `docs` went red on `main` with our code unchanged; before that, GitHub's release host answered
  `504` and the download script had no retry. The hash is what makes a retry safe. **Seen:** gdstudio #823, 2026-11-08
  (#825's retry failed; the next built from the Go proxy); gdstudio #962, 2026-11-10 (fix: the pinned binary in `docs.yml`
  and the game template's `ci.yml`, whose script checked no hash).

## Workflow files {#workflows}

<!-- new section: nothing on this page held how a workflow file is checked before its first run -->

- **Approach:** Run `actionlint` with `shellcheck` before the push of any workflow change (`uvx --from shellcheck-py
  --with actionlint-py bash -c 'actionlint .github/workflows/*.yml'`), and write `if grep ...; then exit 1; fi` and
  `find ... | wc -l` instead of `! grep` and `ls | wc -l`. **Watch out for:** the runner's `actionlint` runs
  `shellcheck` on every `run:` script and local installs often have none, so SC2251, SC2015 and SC2012 passed locally
  and failed CI three times; the same `! grep` step sat in the workflow written for every new game. **Seen:**
  Deadnight #968, 2026-11-03; Deadnight #1112, 2026-11-04; gdstudio #778, 2026-11-07; gdstudio #1071, 2026-11-11 (a
  new workflow's steps copied from ci.yml, where `! grep` is the last line and passes; mid-script it is SC2251);
  gdstudio #1238, 2026-11-11 (an unquoted `$pw` command variable was SC2086; fix: a bash array, `"${pw[@]}"`).
- **Approach:** Before pushing a trial of a job that writes somewhere shared (issues, deploys, releases), list what it
  writes and give the trial its own target; a run of named suites or of a branch never opens or closes the issue the
  schedule owns, and the trial trigger is removed before the pull request. **Watch out for:** a throwaway `push` trigger
  ran the `report` job for real and opened the issue the scheduled run owns, twice; a later clean trial would have
  closed the real one. **Seen:** Deadnight #1209 and #1210, 2026-11-05.
- **Approach:** A pull request that adds a `schedule:` trigger also adds where its failure goes (a last job, `if:
  failure() && github.event_name == 'schedule'`, that opens one issue), and says who reads the first week; a scheduled
  workflow with a red first run is an issue the same day. **Watch out for:** `bots-nightly` failed two nights running
  and nobody was told: a scheduled run belongs to no pull request, and GitHub tells only the account that last edited
  the cron line. **Seen:** Deadnight, 2026-11-06 (fix: proposed, not built).
- **Approach:** Key a cache of downloaded packages by a prefix and restore it with `restore-keys`, never by the runner
  image version; copy only the files fetched now (`find -cnewer <marker file>`, since apt gives a download the server's
  modification time). **Watch out for:** the `ubuntu-24.04` pool serves more than one image version, so an exact image
  key missed on the very next run; `Need to get 0 B/21.1 MB of archives` is the proof of a warm run. **Seen:**
  Deadnight #1112, 2026-11-04.
- **Approach:** Write a `run:` step so that shellcheck needs no directive: read words into an array (`read -r -a folders
  < <(cmd)`) and pass `"${folders[@]}"`; a directive is `key=value` and nothing else on its line. Run actionlint where
  `shellcheck` is installed. **Watch out for:** `# shellcheck disable=SC2086 -- reason` reads the reason as another key
  (`SC1072`, `SC1073`) and fails the `actionlint` job; actionlint checks `run:` scripts only with shellcheck installed,
  so a Windows machine without it passes what CI rejects. **Seen:** Deadnight, 2026-11-02 (fix: the unquoted `$folders`
  became an array and the directive was removed).
