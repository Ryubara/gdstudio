---
areas: [process, ci]
---
# A lesson pushed after its pull request merged never reached main

2026-11-02

- **Saw:** twice in one day an agent added a second lesson to its kit docs branch after that branch's pull request had
  already been squash-merged (kit #175, the outline agent's "screenshots claimed uploaded"; kit #176, the rooms-size
  agent's "rooms sized from one room alone"). Each report said the lesson was in the pull request; `git log
  origin/main..origin/<branch>` showed the commit on the branch only.
- **Cause:** auto-merge lands a docs pull request minutes after its checks pass, so a later push goes to a branch whose
  pull request is closed. Nothing flags it: the Stop docs gate looks for kit branches with commits and *no* pull
  request, and this branch has one (merged).
- **Fix:** before pushing a follow-up to a kit branch, run `gh pr view <branch> --json state -q .state`; if it is
  `MERGED`, start a new branch from `origin/main`, cherry-pick the commit and open a new pull request. The coordinator
  checks `git log origin/main..origin/<branch>` for every merged kit docs branch an agent reports on.
- **Docs:** [Hooks: docs](../hooks.md#docs). Follow-up: the docs gate should also name a kit branch whose pull request
  merged but which holds commits that main does not.
