---
areas: [tools, blender]
---
# The end-of-file hook appended a newline to a glTF buffer

2026-11-03

- **Saw:** `pre-commit` reported `Fixing game/assets/smallmap/wire_fence.bin` and `fence_post.bin`: the end-of-file
  fixer had appended a byte to two glTF buffers.
- **Cause:** `identify` decides text or binary from a file's first kilobyte; a small `.bin` with no zero byte there
  passes as text, and `.bin` is not in Git LFS.
- **Fix:** exclude `\.bin$` from every hook (`exclude:` at the top of `.pre-commit-config.yaml`), rebuild the buffers
  from the build script, and stage again.
- **Docs:** [Modular kits: building the pieces](../tools/blender/modular-kits.md#building-the-pieces).
