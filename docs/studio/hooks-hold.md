# The hold

<!-- new section: moved from hooks.md#hold, which went over the 50 KB page limit (gdstudio #1202) -->

## The hold {#hold}

A pull request the maintainer must see first carries the label `S-hold`. GitHub enforces it, not this hook: the `hold`
job of `.github/workflows/hold.yml` fails while the label is on, and the `Main` ruleset requires that job, so no route
merges it. The rule is `merge.hold` in `.github/conventions.yml`. A failed `hold` is a decision, not a broken build: it
stays out of `merge.required_checks`, so `pr-status` does not label it `S-ci-failing`.

- **Set it** with `gds pr hold <owner/repo>#N`: it adds the label and returns once the check is red, because until then
  the green run before it still counts (on a real pull request: 3 s to pending, 7 to 10 s to red). Or open it held:
  `gh pr create --label S-hold`.
- **Take it off** only on the maintainer's word: by hand on the pull request's page, or by the coordinator while the
  switch below is on. The check re-runs with no new commit. Auto-merge that is on stays on through the hold, so the
  pull request merges the moment the label comes off.
- **The guard** in `guards/merges.py` gives a session the reason, and it is the only thing that stops a session taking the
  label off: every agent uses the maintainer's token, so GitHub cannot tell them apart. It reads shell commands, so it
  does not see a script that calls the API itself.
- **The switch** delegates lifting until the maintainer says otherwise: in the workspace's untracked
  `gdstudio.local.toml`, a `[hold]` table with `coordinator_may_lift` set to the boolean `true` (optional `since`,
  `by`). The maintainer turns it on or off by hand in an editor; missing, `false` or unreadable is off. On, the
  coordinator (no `agent_type` or `agent_id`) may run `gh pr|issue edit --remove-label S-hold`, logged to
  `scratch/hold-lifts.log`; task agents, the API, `gh label` and merges stay refused. `gds doctor` says whether it is
  on; `gds workspace init` keeps the table. No session turns it on: Edit or Write of the file, a shell command that
  writes it (a redirect, a copy onto it or into the workspace, any program naming it but a reader), and any shell line
  or new file text that sets the key are refused.
- **While it waits**, its agent merges `main` only when the pull request is DIRTY at report time; the coordinator
  refreshes it right before it lands ([Landing](landing.md#landing): an agent merged `main` four times into a held
  pull request, each push restarting CI).
- **A pull request opened before the check was required** has no run on its head and stays pending: run
  `gh workflow run hold-sweep.yml` once. It reports the check through the Checks API and does not touch the pull
  request. A new game runs it once when its ruleset starts requiring `hold`.

Do not put an `if:` or a `paths:` filter on `hold`: a job skipped by `if:` reports success, so a filter on the label's
name would let any other label replace a failed run. `python/tests/test_hold.py` has a test for each such reason.
