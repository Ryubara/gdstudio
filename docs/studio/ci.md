# CI and deploys

<!-- new section: the studio folder had no page on how CI and deploys run on the default branch; the hooks page covers what
runs on the machine -->

How the continuous integration runs on the default branch and how a merge reaches the live deploy: every commit of
`main` is checked, and a deploy that can skip itself is sized against the real merge rate.

## Runs on the default branch {#main-runs}

<!-- new section: the studio pages cover hooks, issues and the workspace; nothing held how CI and deploys run on the
default branch -->

- **Approach:** Use `cancel-in-progress` for pull requests only; every run on the default branch finishes. **Watch out
  for:** main's CI cancelled its run when the next merge landed, so four of five merges in three minutes were never
  checked. **Seen:** Deadnight #290, 2026-11-01 (fix: the evening review found it (Deadnight #290) and Deadnight #296
  kept the cancel to pull requests).
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
  --log-failed` before changing anything; edit the description to get a fresh run, because `gh run rerun` replays the
  event it first ran on, old description included. **Watch out for:** a game's CI checks out the kit's `main`, and a game
  pull request written before the kit pull request that added `--no-mcp` had merged failed in 19 s with
  `unrecognized arguments`. **Seen:** Deadnight, 2026-11-01 (fix: the kit change merged first and the job reran);
  Deadnight #1366, 2026-11-06 (the replayed description).
