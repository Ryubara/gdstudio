---
areas: [godot, tools]
---
# A model copied with `git show` imported as nothing

2026-11-01

- **Saw:** `ERROR: Failed loading resource: res://assets/.../zombie.glb`; the `.import` said `valid=false` and the
  copied file was 131 bytes.
- **Cause:** models are Git LFS objects; `git show origin/main:path > file` writes the pointer text, not the binary.
- **Fix:** copy the real file from a checkout (check the size), or `git lfs pull` first; delete the stale `.import`
  files and import again.
- **Docs:** none.
