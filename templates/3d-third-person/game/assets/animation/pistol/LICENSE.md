# Pistol clips

- Animation: `Pistol_Rack`, GDStudio's own work, keyed from scratch by script (kit #1081)
- Source: `build_pistol_rack.py` and `solve_rack_hand.py` in this folder. How a slide is racked was studied from
  shooting instruction pages, for the mechanics and the timing only (the folder's `README.md` lists them); no clip,
  capture or key of anyone else's was copied or traced
- Author: GDStudio contributors
- Licence: MIT, the same as this kit (<https://opensource.org/license/mit>)
- Files: `pistol_rack.glb` (the clip on the rig's bones and a one-triangle mesh that makes the importer build the
  skeleton), `rack_hand.json` (each body's left hand on the slide, its solved place and fingers),
  `build_pistol_rack.py` and
  `solve_rack_hand.py`

The clip is keyed on the skeleton of GDStudio's own prototype body, read from
`assets/characters/prototype/form_female.glb`; the bones it keys carry the names and parents of Quaternius's universal
rig (CC0, credited in `assets/characters/mannequin/LICENSE.md`), which that body is built on. Its first and last pose
is the last frame of `Pistol_Reload` from `assets/animation/universal/ual1.glb` (CC0, its own `LICENSE.md`), so it
joins the reload. `pistol_rack.glb` carries that skeleton's bone names and rest pose and no mesh of a body. No
third-party file is in this folder.
