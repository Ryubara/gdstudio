# Melee clips

- Animations: `Melee_Unarmed_Jab`, `Melee_Unarmed_Cross`, `Melee_Unarmed_Hook`, `Melee_Pistol_Whip`,
  `Melee_Pistol_Backhand` and `Melee_Pistol_Jab`, GDStudio's own work, keyed from scratch by script (kit #1254)
- Source: `build_melee.py` in this folder. Blows were studied from boxing research and from handgun retention
  training pages, for the mechanics and the timing only (`README.md` lists them); no clip, capture or key of anyone
  else's was copied or traced
- Author: GDStudio contributors
- Licence: MIT, the same as this kit (<https://opensource.org/license/mit>)
- Files: `melee.glb` (the six clips on the rig's bones and a one-triangle mesh that makes the importer build the
  skeleton), `melee_clips.json` (each clip's contact time, hit window and measured checks), `build_melee.py` and
  `render_melee.py`

The clips are keyed on the bones of Quaternius's universal rig, read from
`assets/characters/mannequin/mannequin_female.glb` (CC0, its own `LICENSE.md`), and their first and last poses are
frame 0 of `Idle_Loop` and `Pistol_Idle_Loop` from `assets/animation/universal/ual1.glb` (CC0, its own `LICENSE.md`),
so they join the poses the game stands in. The fist is the one of the prone clips (`../prone/`, our own); the pistol
hand's fingers are the game's own grip pose (`gameplay/weapon/hold/pistol_grip_pose.tres`, our own). `melee.glb`
carries the rig's bone names and rest pose and no mesh of the mannequin or the pistol. No third-party file is in this
folder.
