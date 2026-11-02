---
areas: [tools]
---
# A worktree path given to `git -C` landed inside the repository

2026-11-01

- **Saw:** `git -C repos/deadnight worktree add worktrees/deadnight/x` made the worktree at
  `repos/deadnight/worktrees/deadnight/x`, and a tool given `worktrees/deadnight/x` wrote into an empty folder that was
  not a repository (`fatal: not a git repository`).
- **Cause:** `-C` changes git's working directory first, so a relative path is resolved against the repository, not the
  shell's directory.
- **Fix:** give `git worktree add` an absolute path (`<workspace>/worktrees/<repo>/<branch>`); remove a stray one with
  `git worktree remove --force`.
- **Docs:** [The workspace](../workspace.md).
