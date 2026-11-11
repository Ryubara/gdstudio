# Pistol clips

- Animation: `Pistol_Rack`, GDStudio's own work, keyed from scratch by script (kit #1081)
- Source: `build_pistol_rack.py` and `solve_rack_hand.py` in this folder. How a slide is racked was studied from
  shooting instruction pages, for the mechanics and the timing only (the folder's `README.md` lists them); no clip,
  capture or key of anyone else's was copied or traced
- Author: GDStudio contributors
- Licence: MIT, the same as this kit (<https://opensource.org/license/mit>)
- Files: `pistol_rack.glb` (the clip on the rig's bones and a one-triangle mesh that makes the importer build the
  skeleton), `rack_hand.json` (the left hand's solved place and fingers on the slide), `build_pistol_rack.py` and
  `solve_rack_hand.py`

The clip is keyed on the bones of Quaternius's universal rig, read from
`assets/characters/mannequin/mannequin_female.glb` (CC0, its own `LICENSE.md`), and its first and last pose is the last
frame of `Pistol_Reload` from `assets/animation/universal/ual1.glb` (CC0, its own `LICENSE.md`), so it joins the reload.
`pistol_rack.glb` carries the rig's bone names and rest pose and no mesh of the mannequin. No third-party file is in
this folder.
