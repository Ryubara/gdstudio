---
areas: [godot, tools]
---
# gdformat moved a comment into a wrapped dictionary entry

2026-11-03

- **Saw:** after a merge kept two batches' entries in one `const` dictionary, `pre-commit` (gdformat) failed the
  merge commit and its rewrite put a comment line between `"freeze_gun":` and the `{...}` that is its value, and the
  next comment line after it.
- **Cause:** gdformat wraps a long entry as `"key":` then `{...}` on the next line; a comment block right after such an
  entry is interleaved with it when the file is reformatted.
- **Fix:** start a commented block after a one-line entry (here the heavy batch went after `"grenade"` and ended on the
  one-line `"m249"`), run gdformat on the file and read the lines back before committing.
- **Docs:** [Weapons](../tools/blender/weapons.md).
