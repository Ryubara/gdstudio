---
areas: [process, tests]
---
# A "before" capture needs `main` checked out beside the change

2026-11-03

- **Saw:** the pull request needs a `Before:` and an `After:` capture of a screen. The first "before" frames were taken
  at the start of the task and only for the desktop window; once the code had changed, the phone and web "before"
  frames could not be taken any more. `git stash` to get the old code back was refused by the hooks.
- **Cause:** a capture of the old build needs the old code, and the task's own worktree no longer has it after the first
  edit. Taking only the frames you thought of first leaves gaps.
- **Fix:** add a detached worktree of `origin/main` under the task's scratch folder
  (`git worktree add --detach <workspace>/scratch/<repo>/<task>/baseline origin/main`), import it once
  (`godot --headless --path game --import`), and run the same capture scripts there with `--label=before` (the
  desktop, the phone window and the web export alike); remove it with `git worktree remove` when the pull request is
  open. The capture scripts that exist on `main` (the tours) run unchanged; a new tour is for the "after" side.
- **Docs:** [Capture: before captures](../capture.md#before-captures).
