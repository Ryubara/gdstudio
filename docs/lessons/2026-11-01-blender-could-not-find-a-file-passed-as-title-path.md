# Blender could not find a file passed as Title=path

2026-11-01

- **Saw:** `render_sheet.py --model "Walker=/c/Repositories/.../zombie_walker.glb"` failed in Blender with
  `RuntimeError: Error: Please select a file`.
- **Cause:** Git Bash converts a `/c/...` path to `C:\...` only when it starts an argument; inside `Title=/c/...` it
  reached Blender unconverted.
- **Fix:** pass Windows-style paths with forward slashes (`C:/Repositories/...`) to Blender and Godot from Git Bash.
- **Docs:** [character variants](../blender/variants.md).
