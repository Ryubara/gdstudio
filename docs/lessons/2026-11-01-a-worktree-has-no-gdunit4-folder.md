---
areas: [tests, tools]
---
# GdUnit4 would not start in a fresh worktree

2026-11-01

- **Saw:** `-s res://addons/gdUnit4/bin/GdUnitCmdTool.gd` found no script in a worktree made from `origin/main`.
- **Cause:** `game/addons/gdUnit4/` is excluded from git (`.git/info/exclude`) and lives only in the main checkout, so
  `git worktree add` does not bring it.
- **Fix:** copy it once (`cp -r <workspace>/repos/<game>/game/addons/gdUnit4 <worktree>/game/addons/`), then run `godot
  --headless --path game --import` before the first test run (a new `class_name` is also unknown until that import). It
  stays untracked.
- **Docs:** [Godot testing](../godot/index.md#testing-and-capture).
