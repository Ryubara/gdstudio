---
areas: [blender, tools]
---
# Blender could not find a file passed as Title=path

2026-11-01

- **Saw:** `render_sheet.py --model "Walker=/c/Repositories/.../zombie_walker.glb"` failed in Blender with
  `RuntimeError: Error: Please select a file`.
- **Cause:** Git Bash converts a `/c/...` path to `C:\...` when it starts an argument; inside `Title=/c/...` it is
  not to be relied on: on Deadnight #797 (2026-11-03) one run passed `Ray=/c/...` converted and
  `"Ray gun=/c/..."` unconverted, so the same command shape worked for one model and failed for the next.
- **Fix:** pass Windows-style paths with forward slashes (`C:/Repositories/...`) to Blender and Godot from Git Bash.
- **Docs:** [character variants](../tools/blender/variants.md).
