---
areas: [tools, process]
---
# A test script kept in the shared temp folder ran another agent's worktree

2026-11-01

- **Saw:** a "pass" for my branch that came from another worktree: the runner's output said it scanned a folder that
  was not mine, and `gdt.sh` in the shared temp folder had `cd` into someone else's worktree.
- **Cause:** every agent on the machine used the same file name in the same temp folder, and the last writer won.
- **Fix:** keep helper scripts in the session's own scratchpad (a unique path), take the worktree as an argument, and
  read the line that names the scanned folder before trusting a result.
- **Docs:** none (a habit, not a Godot behaviour).
