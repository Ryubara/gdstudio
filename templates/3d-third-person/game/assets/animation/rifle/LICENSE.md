# Rifle clips

- Animations: `Rifle_Idle`, `Rifle_Aim_Neutral`, `Rifle_Aim_Up`, `Rifle_Aim_Down`, `Rifle_Shoot` and `Rifle_Reload`,
  GDStudio's own work, keyed from scratch by script (kit #1082)
- Source: `build_rifle_clips.py` in this folder. How a carbine is shouldered and reloaded was read from shooting
  instruction pages, for the mechanics only (`README.md` lists them); no clip, capture or key of anyone else's was
  copied or traced
- Author: GDStudio contributors
- Licence: MIT, the same as this kit (<https://opensource.org/license/mit>)
- Files: `rifle_clips.glb` (the six clips on the rig's bones and a one-triangle mesh that makes the importer build
  the skeleton), `rifle_clips.json` (each clip's length and loop flag) and `build_rifle_clips.py`

The clips are keyed on the bones of Quaternius's universal rig, read from
`assets/characters/mannequin/mannequin_female.glb` (CC0, its own `LICENSE.md`), and their legs and pelvis are the
first pose of `Idle_Loop` from `assets/animation/universal/ual1.glb` (CC0, its own `LICENSE.md`). `rifle_clips.glb`
carries the rig's bone names and rest pose and no mesh of the mannequin. No third-party file is in this folder.
