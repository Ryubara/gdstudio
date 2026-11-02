---
areas: [ci, tools]
---
# A pull request that adds a description rule is not checked by it

2026-11-01

- **Saw:** the pull request adding the Issues affected rule passed `body` without the new rule being checked, and older
  open pull requests stayed green after it merged.
- **Cause:** `pr.yml` runs on `pull_request_target`, so the checker is always the base branch's: a new rule applies only
  after it merges, and only to pull requests opened or edited after that.
- **Fix:** run the new checker locally on the pull request's own body (`groundwork.py check-body --body <file> --title
  <file>`; both take files) before merging, then edit each open pull request's description to re-run `body`.
- **Docs:** [Hooks](../hooks.md).
