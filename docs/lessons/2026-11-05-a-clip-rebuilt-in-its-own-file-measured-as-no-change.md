---
areas: [blender, godot]
---
# A clip rebuilt in its own file measured as no change, because another file's copy plays

2026-11-05

- **Saw:** a change to Deadnight's `Grenade_Cook` rebuilt into `soldier_grenade.glb` gave results that did not follow the
  change (30, then clean, then 40 mm), and a rebuilt `Swing_Melee` in `soldier.glb` changed nothing at all.
- **Cause:** both clips are also in `soldier_parts.glb` (`FILE_CLIPS` of `build_soldier_parts.py`, the file every dressed
  body's library comes from), and `SoldierClipFile.add` keeps a clip the library already has: the parts' copy plays, the
  own file's is never read. Swapping one file at a time showed it.
- **Fix:** rebuild both files from the same source (`build_soldier_parts.py` takes about 15 s and writes the same
  `parts.json`). Also: `git show HEAD:<file>.glb` prints a Git LFS pointer, not the file; copied over an asset it made the
  import fail ("Expected 'true', 'false', or 'null', got 'version'") and wrote `valid=false` into the `.import` file. Use
  `git checkout -- <file>.glb`, restore the `.import`, delete `.godot/imported/<file>.glb-*`, import again.
- **Check next time:** before tuning a clip, find every built file that carries its name (`grep` the clip in the
  build scripts' clip lists and in the glb's JSON) and confirm which copy plays by swapping one file; compare two glbs
  by their animation accessors in Python, not by `git show`.
- **Docs:** Deadnight `docs/research/weapon-hold-ik.md`, "The poses #987 left over the tolerance (#1282)".
