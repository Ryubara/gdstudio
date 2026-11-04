---
areas: [blender, godot]
---
# Importing a conflicted glb wrote valid=false into its import file

2026-11-04

- **Saw:** after a merge left `soldier_parts.glb` conflicted, `godot --import` printed `glTF: Error parsing .gltf JSON data:
  ... got 'version'`, and a later import failed `Failed loading resource` although the file had since been rebuilt whole.
- **Cause:** the file is in Git LFS, so a conflict leaves pointer text in the working tree (`version` is its first
  word). A rebuild that stops on an assert writes no new model, so the import reads that text. It then rewrites
  `.glb.import` with `valid=false` and drops `dest_files`, and Godot goes on trusting that record after the model is good.
- **Fix:** restore the import file (`git checkout HEAD -- <file>.glb.import`), delete its
  `.godot/imported/<file>.glb-*`, and import again. Never import a conflicted built file: fix the script, build until it
  exits clean, then import, and read `git diff` of `*.import` before committing.
- **Docs:** this file; see also [an LFS pointer from git show](2026-11-01-git-show-of-an-lfs-file-gives-a-pointer-not-the-model.md).
