---
areas: [godot, tools]
---
# Godot rewrites project.godot

2026-11-01

- **Saw:** a hand-written comment in `project.godot` vanished after the first import. Later, after any `--import` or
  run, `git status` showed `project.godot` modified with sections reordered and no setting changed.
- **Cause:** Godot owns that file and rewrites it in its own format and section order when it saves project state; two
  engineers touching the input map then conflict on a reorder nobody meant.
- **Fix:** never hand-comment it; local-only settings go in an untracked `override.cfg`. Run
  `git checkout game/project.godot` after each run, before staging, and stage files by path (never `git add -A` in a
  worktree where Godot has just run); change the file by hand only for a real setting.
- **Docs:** [Workspace](../studio/workspace.md).
