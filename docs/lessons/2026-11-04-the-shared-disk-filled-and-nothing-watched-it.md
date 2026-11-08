---
areas: [tools, process, tests]
---
# The shared disk filled and nothing watched it

2026-11-04

- **Saw:** the C: drive (931 GB) at 120 MB free with some 25 agents at work: Godot imports were truncated, a pre-commit
  hook emptied a source file, test runs failed. Measured: the workspace held 64 GB, of which `scratch/` was 50.8 GB, and
  26 GB of that was 86,000 numbered Movie Maker frames; worktrees were 7.3 GB (1.2 GB of `.godot/`), `Temp` 31 GB. The
  worktree sweep, run by hand, freed 23 MB: the space was not in finished worktrees.
- **Cause:** every clean-up was a step someone had to remember, and only one (the worktree sweep) was automated. Scratch
  was "never deleted" by rule, so each capture left its frames, each CI investigation its downloaded artifacts, after
  the clip, the numbers and the pull request were done; and nothing measured the disk until it was full. A shared
  resource with many writers and no owner fills.
- **Fix:** `gds disk guard`, started by every hook event at most every five minutes: under 40 GB free it sweeps, clears
  the import caches of idle worktrees and the downloads (artifacts, archives, raw movie output, numbered frames) of
  scratch topics past their pull request; under 10 GB it refuses new task agents, `gds issue start` and `git worktree
  add`; per-worktree and per-topic budgets name the biggest folders in the refusals and in the status line
  (`mods/gdstudio-disk`). Agents reduce a downloaded CI artifact to its numbers and delete it in the same task, and
  a topic's `SCRATCH.md` names its pull request and what can go. Check for next time: anything many agents write to
  gets a measured budget and an automatic clean-up when it is made, not when it is full.
- **Docs:** [The disk guard](../studio/workspace.md#disk), [Disk hook](../studio/hooks.md#disk).
