# Universal Animation Library 1 and 2

- Animations: "Universal Animation Library" (`UAL1_Standard.glb`) and "Universal Animation Library 2"
  (`UAL2_Standard.glb`), the Standard packs, by Quaternius. Both use the Quaternius universal humanoid rig, so their
  clips play on either mannequin in `assets/characters/mannequin/` without retargeting. These are the files with root motion
  off (the packs' `_RM` files have it on).
- Source: <https://quaternius.itch.io/universal-animation-library> (file `Universal Animation Library[Standard].zip`,
  sha256 `cc73fc4e495b82958207316596317a3f40b9fa38065bde1027937452da537724`) and
  <https://quaternius.itch.io/universal-animation-library-2> (file `Universal Animation Library 2[Standard].zip`, sha256
  `4008ea208a604773a2b2177d965f0f5d3195498b5bf838c3f5785d68e95f2a68`); pack pages
  <https://quaternius.com/packs/universalanimationlibrary.html> and
  <https://quaternius.com/packs/universalanimationlibrary2.html>
- Author: Quaternius (<https://quaternius.com>)
- Licence: CC0 1.0 Universal (public domain), <https://creativecommons.org/publicdomain/zero/1.0/>; the pack pages and
  the itch.io pages say CC0 and each pack's `License.txt` repeats it
- Files: `ual1.glb` (`Unreal-Godot/UAL1_Standard.glb`, sha256
  `69591853d817488edaa8fd9bf8fc1d821eaeaf789f8627b3cd23b41c4ed67997`) and `ual2.glb`
  (`Unreal-Godot/UAL2_Standard.glb`, sha256 `8cee20ab1bc55130092447e810e26df22dd2803eccc54f52137a7d54d7ab88a8`), the
  original files renamed and not changed. Godot imports each as an `AnimationLibrary` (their meshes are left out of
  the import); the game's player holds them as the libraries `ual1` and `ual2`.

The Pro and Source tiers of the packs are not here. No attribution is required; the credit is given anyway (Credits
screen).
