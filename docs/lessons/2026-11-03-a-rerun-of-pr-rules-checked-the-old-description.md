---
areas: [ci]
---
# A rerun of pr-rules checked the old description

2026-11-03

- **Saw:** after adding the `Lessons:` line to Deadnight #655, `gh run rerun` of the failed `pr-rules` run failed
  again with the same reason, and the pull request showed one red and one green `pr-rules`.
- **Cause:** `pr.yml` reads the body from the event (`github.event.pull_request.body`); a rerun replays the old event
  with the old body. Editing the description already starts a fresh run (`types: [edited]`).
- **Fix:** after `gh pr edit`, wait for the run the edit started; never rerun an older `pr-rules` run. If you did,
  rerun the newest one so it finishes last.
- **Docs:** [Hooks](../hooks.md).
