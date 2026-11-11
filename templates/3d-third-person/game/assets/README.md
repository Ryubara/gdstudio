# assets

`assets/<domain>/<subject>/`: the domain is the kind of thing (`models`, `textures`, `materials`, `shaders`, `audio`,
`ui`, `branding`), the subject is what it is for (`prototype`, `player`). Names are `<subject>_<variant>_<n>`.

- Every third-party folder carries a `LICENSE.md` naming the source and licence; a file without one is not committed.
- Binary assets go through Git LFS (`.gitattributes` lists the types).
- `assets/shaders/prototype/` and `assets/materials/prototype/` are the template's prototype surface: one world-space
  grid shader and a material per colour.
- `assets/characters/mannequin/` is Quaternius's two mannequins (`mannequin_female.glb`, the default, and
  `mannequin_male.glb`) and `assets/animation/universal/` the Universal Animation
  Library 1 and 2 (CC0, each with a `LICENSE.md`): the character's mesh and its 86 clips.
- `assets/weapons/pistol/` is GDStudio's own pistol (MIT, from Deadnight's build script, with a `LICENSE.md`), and
  `pistol_held.tscn` puts it in the mannequin's right hand for the pistol clips (the folder's README).
- `assets/audio/coin/` (a coin pickup, four variants), `assets/audio/footsteps/` (four soft steps),
  `assets/audio/fists/` (three punch whooshes), `assets/audio/impacts/` (nine bullet impacts: default, wood and metal,
  three each) and the pistol's empty click, reload and draw in `assets/audio/pistol/` are generated with ElevenLabs
  Sound Effects on the studio's paid plan, like the base's wind: commercial use in a game allowed, no attribution
  required, not to be shared on their own as sound files (each folder's `LICENSE.md`).
- The five pistol shots in `assets/audio/pistol/` are synthesised by Deadnight's code (MIT, GDStudio's own; the
  folder's `LICENSE.md`): no attribution and nothing to replace. `assets/shaders/impacts/` and
  `assets/materials/impacts/` are the mark's shader and its default material (original).
- `assets/ui/minimap/` is the minimap's six icon shapes (dot, ring, square, diamond, arrow, triangle: white on
  clear, 64 px, GDStudio's own, drawn by `tools/minimap/make_icons.py`; a marker tints them). The scripts and scenes
  that use them are in `ui/minimap/` and `core/minimap/`.
- `assets/ui/inventory/` is the inventory's icons (a coin, a bandage, the pistol and the fists: SVG, GDStudio's own,
  drawn for the template); the items are `gameplay/inventory/*.tres` and the weapons' `WeaponDef`s name theirs.
- `assets/shaders/effects/flash_star.gdshader` and `assets/materials/effects/flash_star.tres` draw the muzzle flash's
  star (original).
