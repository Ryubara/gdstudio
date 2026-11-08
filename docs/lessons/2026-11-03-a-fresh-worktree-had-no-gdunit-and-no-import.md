---
areas: [tests, tools]
---
# A fresh game worktree ran no tests: no GdUnit4 addon and no imported assets

2026-11-03

- **Saw:** the first GdUnit run in a new worktree printed `Could not preload resource file "res://assets/..gltf"` and
  `Compile Error: Failed to compile depended scripts`, then `Abnormal exit with 105`, three times in a row.
- **Cause:** the worktree is a clean checkout: `addons/gdUnit4` and `addons/godot_mcp` are not in it (they live in the
  main clone only), and `.godot/` was empty, so nothing was imported. A `--import` cut short by `| tail` looked done.
- **Fix:** copy both addon folders from the main clone, run `godot --headless --path game --import` to the end (log it
  to a file, check the exit code), then run the suite. A commit piped to `tail` also hid a failed `markdownlint` hook
  again ([earlier lesson](2026-11-02-a-commit-piped-to-tail-hid-a-failed-hook.md)): read `git log` after it.
- **Docs:** [Navigation in tests](../engines/godot/navigation-in-tests.md) for the map side of the same task.
