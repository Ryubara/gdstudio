---
areas: [tools, process]
---
# Finished worktrees were never removed, and the disk filled up

2026-11-03

- **Saw:** the maintainer: "My disk space is 8.05 GB, we need to clear out anything related to GDStudio and Dead Night
  that's taking up all this storage that's not being used anymore", and "Our GDStudio workflow needs to automatically
  clear out work trees as soon as they're rendered obsolete. The issue is that there might be some stuff intended to be
  kept for later such as the artwork we made and maybe others." The coordinator removed 64 Deadnight worktrees by hand
  (8 GB free became 14 GB); some were two days old, and each held a Godot import cache of tens to hundreds of MB.
  Reviewers' and probes' detached worktrees (`review-*`, `*-before`, `baseline-*`, `exp-*`) had no owner and were never
  removed. Of the 23 worktrees archived first, the loose files worth keeping (`REVIEW.md`, probes, captures, a `.blend`)
  were 181 MB.
- **Cause:** removing a worktree was a manual step after each merge, so it was skipped under load, and nothing owned the
  worktrees that no pull request or issue named. Which files were worth keeping was only known by looking at each one.
- **Fix:** `gds worktree sweep` ([workspace.md](../workspace.md#sweep)) removes a worktree whose pull request merged, whose
  issue closed or that nothing touched for hours, after copying its changed and untracked files that are not generated
  to `scratch/<repo>/<branch>/kept/`. A hook starts it in the background ([hooks.md](../hooks.md#sweep)); `gds doctor`
  warns under 20 GB free.
- **Check:** a program that removes things is judged by what it refuses. Test, with real git repositories, that it
  keeps a worktree with an open pull request, one with commits on no remote branch, one a process uses (also by a longer
  name that starts the same) and one touched in the last minutes, and that it copies artwork and notes while leaving
  `.uid` and `.godot/` out. Two traps found on the way:
    - on Windows another process's working directory cannot be read, and an agent between two commands has no process
      at all, so "no process uses it" is not enough: a grace period on the newest change time, and the started-issue
      ledger, stand in for it;
    - `git status` rewrites the index, which is the activity clock: the first dry run reported every worktree as
      "touched 0 minutes ago". Read the state with `git --no-optional-locks`.
- **Check (for any agent):** anything to keep lives in a commit or in `scratch/`, never only in a worktree, and a process
  you start in a worktree ends with it. A reviewer's checkout goes under `worktrees/<repo>/`, not `scratch/`, so the
  sweep finds it.
- **Docs:** [Expired monitors left their polling loops running](2026-11-03-expired-monitors-left-their-polling-loops-running.md)
  (a background job ends on its own and opens no console window).
