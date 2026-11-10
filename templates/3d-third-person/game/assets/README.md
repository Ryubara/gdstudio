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
- `assets/animation/vault/` is GDStudio's own vault clips (`Vault_Low`, `Vault_High`, `Vault_Land`; MIT, keyed from
  scratch by `build_vault.py` on the mannequin's rig, with a `LICENSE.md`), an `AnimationLibrary` like the two packs,
  and `vault_clips.json`, each clip's reference obstacle and contact times.
- `assets/weapons/pistol/` is GDStudio's own pistol (MIT, from Deadnight's build script, with a `LICENSE.md`), and
  `pistol_held.tscn` puts it in the mannequin's right hand for the pistol clips (the folder's README).
- `assets/audio/coin/` (a coin pickup, four variants) and `assets/audio/footsteps/` (four soft steps) are generated
  with ElevenLabs Sound Effects on the free tier, like the base's wind: attribution required, not licensed for
  commercial use. **Temporary: replace or relicense them before any commercial release**, and name ElevenLabs on the
  Credits screen until then.
- `assets/audio/pistol/` is five pistol shots synthesised by Deadnight's code (MIT, GDStudio's own, with a
  `LICENSE.md`): no attribution and nothing to replace.
- `assets/audio/impacts/` is nine bullet impact sounds (default, wood and metal, three each) synthesised by the kit's
  `tools/audio/impact_sounds.py` (MIT, GDStudio's own, with a `LICENSE.md`); `assets/shaders/impacts/` and
  `assets/materials/impacts/` are the mark's shader and its default material (original).
- `assets/ui/minimap/` is the minimap's six icon shapes (dot, ring, square, diamond, arrow, triangle: white on
  clear, 64 px, GDStudio's own, drawn by `tools/minimap/make_icons.py`; a marker tints them). The scripts and scenes
  that use them are in `ui/minimap/` and `core/minimap/`.
- `assets/shaders/effects/flash_star.gdshader` and `assets/materials/effects/flash_star.tres` draw the muzzle flash's
  star (original).
