# Vault clips

- Animations: `Vault_Low`, `Vault_High` and `Vault_Land`, GDStudio's own work, keyed from scratch by script (kit #1010)
- Source: `build_vault.py` in this folder. Vaults were studied from parkour coaching pages and from how shipped games
  describe their traversal, for the mechanics and the timing only (the pull request of kit #1010 lists them); no clip,
  capture or key of anyone else's was copied or traced
- Author: GDStudio contributors
- Licence: MIT, the same as this kit (<https://opensource.org/license/mit>)
- Files: `vault.glb` (the three clips on the rig's bones and a one-triangle mesh that makes the importer build the
  skeleton), `vault_clips.json` (each clip's reference obstacle and contact times), `build_vault.py` and
  `render_vault.py`

The clips are keyed on the bones of Quaternius's universal rig, read from `assets/characters/mannequin/mannequin_female.glb`
(CC0, its own `LICENSE.md`), and their first and last poses are poses of `Sprint_Loop` from
`assets/animation/universal/ual1.glb` (CC0, its own `LICENSE.md`), so they join the run. `vault.glb` carries the rig's
bone names and rest pose and no mesh of the mannequin. No third-party file is in this folder.
