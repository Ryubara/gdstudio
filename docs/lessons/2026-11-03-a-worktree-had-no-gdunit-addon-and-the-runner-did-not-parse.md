---
areas: [tests, tools]
---
# GdUnitCmdTool did not parse in a new worktree

2026-11-03

- **Saw:** `res://addons/gdUnit4/bin/GdUnitCmdTool.gd` "File not found"; after copying the folder in,
  `Could not find type "GdUnitTestCIRunner"`.
- **Cause:** `game/addons/gdUnit4/` is an ignored folder, so a fresh worktree does not have it; and a copied addon's
  global classes are only in `.godot/global_script_class_cache.cfg` after an import.
- **Fix:** copy the folder from another worktree, then run `godot --headless --path game --import` once, then the runner.
- **Docs:** none yet; `gds workspace init --fetch gdunit4` fetches it into the main repository only.
