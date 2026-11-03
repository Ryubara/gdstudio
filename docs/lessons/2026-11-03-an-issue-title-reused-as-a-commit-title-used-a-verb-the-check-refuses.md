---
areas: [tests, process]
---
# An issue title reused as the commit title started with a verb the check refuses

2026-11-03

- **Saw:** Deadnight #892 ("tests: Step the two-thumbs touch test on its own clock"): the commit hook printed `commit title
  follows the conventions ... Failed`, the commit was not made, and `gh pr create` then said "No commits between main
  and <branch>" (I had chained the commit, push and PR, so the second error hid the first).
- **Cause:** I copied the issue's title for the commit and the pull request. The allowed verbs are Add, Fix, Update,
  Remove, Rebuild, Rework, Improve, Document; "Step" is none of them, and an issue title is not checked.
- **Fix:** retitle from the verb list (`tests: Fix the two-thumbs touch test that waits on real frames`), run
  `gds pr check-body <body> --title <title file>` before committing (it checks the title too), and do not chain
  `git commit` with `git push` and `gh pr create` without reading the commit's output.
- **Check:** a title taken from an issue is checked against the verb list first; read the commit hook's result before
  pushing.
- **Docs:** [commit and pull request rules](../../AGENTS.md#commits-and-pull-requests).
