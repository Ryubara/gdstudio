---
areas: [blender]
---
# A parts rebuild picked up clips that ship in their own files

2026-11-02

- **Saw:** rebuilding Deadnight's `soldier_parts.glb` for the female Soldier (#678) wrote 55 clips instead of the 39
  it shipped with: the sprint, strike, downed, revive and aim-move clips came along.
- **Cause:** the build exports every action `soldier_clips.py` makes, and that module had grown since the file was
  last built. Those clips ship in their own files with their finger channels stripped, and the controller adds a clip
  from a file only when the library lacks it, so the copies in the parts file would have won, fingers and all.
- **Fix:** the build keeps a frozen list of the clips the file carries (`FILE_CLIPS`) and asserts it; the 39 rebuilt
  sample for sample identical to the committed file (compared the glb's animation accessors), so only the meshes
  changed. Before rebuilding a shared file, diff its catalog (`parts.json` `clips`) against the committed one.
- **Docs:** [Character variants](../blender/variants.md#a-second-body-on-the-same-parts).
