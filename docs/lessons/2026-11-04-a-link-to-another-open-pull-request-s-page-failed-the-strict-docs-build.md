---
areas: [ci, process]
---
# A link to another open pull request's page failed the strict docs build

2026-11-04

- **Saw:** Deadnight #1087 failed `mkdocs` on a link to `xp-curve.md`, a page only in #1083, still open. The
  same follow-up existed because #1084 had merged with stale numbers: the coordinator asked its agent for three fixes
  while auto-merge was on, and the pull request landed before they were pushed.
- **Cause:** Two pull requests open at once see two different mains. A strict docs build reads the branch's own tree, so
  a page that is on its way counts as missing. And a request for changes does not hold a pull request back: auto-merge
  only waits for checks, and the stale numbers passed them.
- **Fix:** #1087 passed once #1083 merged and main came in. It carried the three fixes on a new branch.
- **Check next time:** Before asking for changes to a pull request with auto-merge on, turn auto-merge off in the same
  step, and turn it back on with the fix. Link a page from another open pull request only after that pull request
  lands, or name it in plain text until then.
