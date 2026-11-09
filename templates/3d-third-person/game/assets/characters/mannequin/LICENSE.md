# Mannequin characters

Two models of the Quaternius universal rig: the female mannequin (the default of the player scene) and the male one.
Both are CC0, by Quaternius, and are drawn on the same skeleton (65 bones with the same names and parents), so every
clip of `assets/animation/universal/` plays on either one.

## Female: `mannequin_female.glb`

- Model: "Female Mannequin" (`Mannequin_F`) by Quaternius, from the Universal Animation Library 2 [Standard]
- Source: <https://quaternius.itch.io/universal-animation-library-2> and
  <https://quaternius.com/packs/universalanimationlibrary2.html> (the pack's `Female Mannequin/Unreal-Godot/Mannequin_F.glb`,
  sha256 `2ee6cc3fe888d9b144afa8cc4b2ab7bfc5d13a0d5b7548df777f61f64ad65fa6`; the pack zip `Universal Animation Library
  2[Standard].zip` has sha256 `4008ea208a604773a2b2177d965f0f5d3195498b5bf838c3f5785d68e95f2a68`)
- Files: `mannequin_female.glb`, the original file renamed and not changed (it was `mannequin.glb`).

## Male: `mannequin_male.glb`

- Model: the "Mannequin" mesh and its skeleton from the Universal Animation Library [Standard] (the male mannequin the
  packs ship inside their clip files; no pack has a model-only file for it) by Quaternius
- Source: <https://quaternius.itch.io/universal-animation-library> and
  <https://quaternius.com/packs/universalanimationlibrary.html> (the pack's `Unreal-Godot/UAL1_Standard.glb`, sha256
  `69591853d817488edaa8fd9bf8fc1d821eaeaf789f8627b3cd23b41c4ed67997`; the pack zip `Universal Animation
  Library[Standard].zip` has sha256 `cc73fc4e495b82958207316596317a3f40b9fa38065bde1027937452da537724`). The mesh,
  skin and skeleton of `UAL2_Standard.glb` (sha256 `8cee20ab1bc55130092447e810e26df22dd2803eccc54f52137a7d54d7ab88a8`,
  from the Universal Animation Library 2 pack) are byte for byte the same.
- Files: `mannequin_male.glb` (sha256 `0a67bc1965336dff6d6e61c997719dcae2824b00b97c130d18acbbca31e7dcc6`), the
  `UAL1_Standard.glb` file with its 43 clips removed and nothing else changed: its nodes, mesh, skin and materials are
  copied as they are, and only the animation data is dropped (7.6 MB to 0.6 MB). Made with
  `tools/models/strip_glb_animations.py` of the GDStudio kit (`python strip_glb_animations.py UAL1_Standard.glb
  mannequin_male.glb`).
- The male mesh node is called `Mannequin`; the female's is `Mannequin_F`. Nothing refers to either name.

Author of both: Quaternius (<https://quaternius.com>). Licence: CC0 1.0 Universal (public domain),
<https://creativecommons.org/publicdomain/zero/1.0/>; the pack pages and the itch.io pages say CC0 and each pack's
`License.txt` repeats it.

Neither model has clips: they share their rig with the Universal Animation Library, whose clips
(`assets/animation/universal/`) play on them unchanged. The two rest poses differ a little at the arms (the male's
collarbones and upper arms are longer), so the same clip reaches slightly different poses.

No attribution is required; the credit is given anyway (Credits screen), for both.
