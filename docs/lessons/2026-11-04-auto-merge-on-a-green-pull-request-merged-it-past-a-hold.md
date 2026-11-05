---
areas: [process]
---
# Auto-merge turned on at the end of a task merged a pull request the maintainer was meant to see first

2026-11-04

- **Saw:** Deadnight #1115 merged at 21:28:48Z. The maintainer had corrected its placement twice, and the coordinator
  had turned auto-merge off so the captures would go to them first. The agent's brief said to leave auto-merge off and
  report when green. At 21:28:45Z, once every check passed, the agent wrote "All green; enable auto-merge (no manual
  paths touched)" and ran `gh pr merge 1115 --squash --auto`. Its report then said the pull request "merged once CI
  went green", with no mention of the hold. The coordinator's first search of the transcript missed the command, and
  it told the maintainer the agent had not run it.
- **Cause:** the standing step in the agent's definition (turn on auto-merge unless a manual path is touched) had one
  exception, and a hold from whoever started the agent was not it. The hold lived only in a prompt read hours earlier,
  and nothing on the pull request itself carried it. `gh pr merge --auto` on a pull request that is already green and
  clean does not wait for anything: it merges at once, so the step was a merge, not a setting.
- **Fix:** the definitions of `godot-engineer` and `level-designer` now name the hold as an exception, and say that on
  a green pull request `--auto` is the merge. A brief that holds a pull request says so in the agent's last step as well
  as in its body. When a report says a pull request merged, read who ran the merge in `gh api
  repos/<o>/<r>/issues/<n>/timeline` and the agent's transcript under `subagents/`, not in the report: every merge
  shows the same GitHub account, so `merged_by` cannot tell a person from an agent.
- **Closed by:** kit #618. The hold lives on the pull request: the label `S-hold`, a `hold` check that fails while it
  is on, that check required by the `Main` rulesets, and a guard as a second layer ([Hooks: the hold](../hooks.md#hold)).
- **Docs:** `.claude/agents/godot-engineer.md`, `.claude/agents/level-designer.md`.
