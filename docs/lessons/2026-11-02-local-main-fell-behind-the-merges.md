---
areas: [ci, tools]
---
# The local main checkouts fell behind the merges

2026-11-02

- **Saw:** the maintainer, working in the editor on the main checkout, did not have what had just merged: "whenever
  you merge something, you should by default always be doing git pull".
- **Cause:** most pull requests merge on GitHub by auto-merge, with no local command, and agents work in worktrees, so
  nothing ever moved `repos/<repo>` on `main`. Pulling was left to memory.
- **Fix:** the hooks pull every local main with `--ff-only` after a merge command, at session start and at Stop (at
  most every two minutes), and name a checkout whose local changes block it instead of discarding them.
- **Docs:** [Hooks: local mains](../hooks.md#mains).
