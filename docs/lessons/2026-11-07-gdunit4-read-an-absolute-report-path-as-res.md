---
areas: [tests, ci, godot]
---
# GdUnit4 read an absolute report path as a path inside the project

2026-11-07

- **Saw:** on a Linux runner, the step that checks "nothing the build made is left for git to see" listed `?? game/home/`
  after a test run that passed `-rd "$RUNNER_TEMP/reports"`. The same command with `C:/...` on Windows wrote outside
  the project.
- **Cause:** `GdUnitFileAccess.make_qualified_path` turns a path starting with `/` into `res:/` plus the path, so
  `/home/runner/work/_temp/reports` became `res://home/runner/work/_temp/reports`. A relative path starts in the
  project (Godot runs there): `-rd reports` made `game/reports`. Only a drive path or a path with `..` leaves it.
- **Fix:** `-rd ../../../reports` from `repos/<game>/game`, which is the runner's work folder (outside the game's
  repository), and the artifact upload names `reports`. Keep a final `git status --porcelain` step after the
  tests: it caught this, and an import that left uids or imports behind.
- **Docs:** [Prototype surfaces and daylight](../godot/prototype-surfaces.md#smaller-findings),
  [Project conventions](../godot/project-conventions.md#rules).
