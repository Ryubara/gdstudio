# Rifle clips

- Animations: `Rifle_Idle`, `Rifle_Aim_Neutral`, `Rifle_Aim_Up`, `Rifle_Aim_Down`, `Rifle_Shoot`, `Rifle_Reload` and
  `Rifle_Reload_Empty`, GDStudio's own work, keyed from scratch by script (kit #1082, #1508)
- Source: `build_rifle_clips.py` in this folder. How a carbine is shouldered and reloaded was read from shooting
  instruction pages, for the mechanics only (`README.md` lists them); no clip, capture or key of anyone else's was
  copied or traced
- Author: GDStudio contributors
- Licence: MIT, the same as this kit (<https://opensource.org/license/mit>)
- Files: `rifle_clips.glb` (the seven clips on the rig's bones and a one-triangle mesh that makes the importer build
  the skeleton), `rifle_clips.json` (each clip's length and loop flag) and `build_rifle_clips.py`

The clips are keyed on the bones of GDStudio's own prototype body, read from
`assets/characters/prototype/form_female.glb`, whose rig keeps the bone names and rest rotations of Quaternius's
universal rig (CC0, credited in `assets/animation/universal/LICENSE.md`), and their legs and pelvis are one pose of
GDStudio's own `Idle` from `assets/animation/own/locomotion.glb`. `rifle_clips.glb` carries the rig's bone names
and rest pose and no mesh of the body. No third-party file is in this folder.
