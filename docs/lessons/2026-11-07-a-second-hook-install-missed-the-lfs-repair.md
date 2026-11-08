---
areas: [tools, general]
---
# A second hook install missed the Git LFS repair the first one had

2026-11-07

- **Saw:** the first real `gds new game` (kit #779) created the GitHub repository, then stopped on
  `git push failed: error: failed to push some refs`. The error said nothing more, and the hooks all passed when
  run by hand with `--all-files`.
- **Cause:** `gds new game` runs `git lfs install` and then `uvx pre-commit install`, which moves Git LFS's pre-push
  hook to `pre-push.legacy`. That hook starts `#!/bin/sh`, which pre-commit cannot find on Windows
  (`ExecutableNotFoundError`). `gds worktree` has repaired this since it first happened (`repair_legacy_hooks`), but
  the new command installed hooks through its own path and never called the repair. The cause was hidden because the
  command kept only git's stderr, while pre-commit writes its report to stdout.
- **Fix:** `new_game` calls `worktrees.repair_legacy_hooks` after the install. A failed push now shows stdout and
  stderr together. Tests cover both, and the second probe pushed. That probe then opened its kit pull request as
  "Add the pre-push.legacy game": the repair loop was written `for name in ...` inside the function whose `name` is
  the game's. It is now `for hook in ...`, and the test checks the pull request's branch and title.
- **Check:** before adding a second place that installs or runs git hooks, grep for the first (`install_hooks`,
  `ensure_hooks`) and call it, or its repairs, rather than calling `pre-commit install` again. Find a hidden hook
  failure without pushing by running `.git/hooks/pre-push origin <url>` with the ref line on stdin. In a long
  function, a loop variable gets a name that function does not already use (ruff does not catch this shadowing).
- **Docs:** [A new game from a template](../engines/godot/new-game.md).
