---
areas: [godot, tools]
---
# A model copied with `git show` imported as nothing

2026-11-01

- **Saw:** `ERROR: Failed loading resource: res://assets/.../zombie.glb`; the `.import` said `valid=false` and the
  copied file was 131 bytes.
- **Cause:** models are Git LFS objects; `git show origin/main:path > file` writes the pointer text, not the binary.
- **Fix:** copy the real file from a checkout (check the size), or `git lfs pull` first; delete the stale `.import`
  files and import again. For an old version of one file, `git show <rev>:<path> | git lfs smudge > file` writes the
  binary.
- **Again (2026-11-02):** the old palette atlas of a before/after check (Deadnight #651): PNGs are LFS objects too, and
  Pillow said `cannot identify image file`. Any binary in `.gitattributes` goes through `git lfs smudge`.
- **Docs:** [Modular kits: building props](../tools/blender/modular-kits.md#building-props).
