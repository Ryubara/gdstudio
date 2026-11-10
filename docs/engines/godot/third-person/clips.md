# The character's clips

<!-- new section: split out of the character page when it reached the size limit (#1016) -->

The clips the 3D Third Person character plays: the Universal Animation Library and the template's own vault clips.
Part of [the character and its model](character.md) and [the 3D Third Person template](../third-person-template.md).

## The animation libraries {#animation-libraries}

<!-- new section: no page said how the Universal Animation Library reaches a Godot character -->

- **Approach:** Import each Universal Animation Library glb as an `AnimationLibrary` (`importer="animation_library"` in
  its `.import`, the "Import As" choice of the Import dock), add it to the player's `AnimationPlayer` under a library
  name (`ual1`, `ual2`), and keep the mannequin as a plain scene whose root is the `AnimationPlayer`'s `root_node`.
  **Watch out for:** the importer drops the glb's mesh (the library is 0.75 MB where the file is 7.6 MB), removes the
  `_Loop` suffix and makes the clip loop (`Idle_Loop` is `ual1/Idle`, `Jump_Loop` is `ual1/Jump`), and the track paths
  are `Armature/Skeleton3D:<bone>`, which match the mannequin's scene (`mannequin/Armature/Skeleton3D`) with no
  retargeting, since the libraries and the mannequin share the Quaternius universal rig. A test walks every track of all
  86 clips and finds its bone. **Seen:** gdstudio #821, 2026-11-08.
- **Approach:** Name every point of an `AnimationNodeBlendSpace1D` (`add_blend_point(node, pos, -1, &"walk")`) and
  travel a state machine between states that all have transitions to each other. **Watch out for:** Godot 4.7 warns "No
  name provided" for an unnamed point, once per point and per player. **Seen:** gdstudio #821, 2026-11-08.
- The Pro and Source tiers of the packs are not free; the template holds the Standard files only (43 clips each, 86 in
  all). Their licence is CC0 on the official pages (itch.io and quaternius.com) and in each zip's `License.txt`.
  A download needs the itch.io page's free "name your own price" path (a CSRF token, then `download_url`, then
  `file/<id>`, all within seconds of each other); keep the zips in `<workspace>/cache/downloads/` and record their
  sha256 in the licence entry.

## The vault clips {#vault-clips}

<!-- new section: the Universal Animation Library has a climb (`ClimbUp_1m`) and no vault; kit #1010 made the template's
own, and the vault code (#1013) reads their contact times from here -->

`assets/animation/vault/vault.glb` holds GDStudio's own vault clips, keyed from scratch on the universal rig by
`build_vault.py` (the pinned Blender) and imported as an `AnimationLibrary` like the two packs. They are in place like
the library's: the game moves the body. `vault_clips.json` beside the file gives, for each clip, what a warp needs: the
reference obstacle, the constant speed the body was moved at when the clip was keyed, where the root starts, and the
contact times. Forward 0 is the obstacle's front face.

| Clip | Length | Reference obstacle | Body moved at | Root from, to | Contacts (seconds from the clip's start) |
| --- | --- | --- | --- | --- | --- |
| `Vault_Low` | 0.667 s (16 frames at 24) | 0.8 m high, 0.4 m deep | 4.0 m/s (2.67 m) | -1.30 m, +1.37 m | left foot off 0.167, left hand on 0.292, hips over the middle 0.375, hand off 0.375, right foot down 0.667 |
| `Vault_High` | 1.083 s (26 frames) | 1.2 m high, 0.4 m deep | 3.0 m/s (3.25 m) | -1.86 m, +1.39 m | right foot off 0.458, both hands on 0.458, right hand off 0.542, hips over 0.667, left hand off 0.667, right foot down 1.083 |
| `Vault_Land` | 0.417 s (10 frames) | none | 4.0 m/s (1.67 m) | | right foot down 0, off 0.208, left foot down 0.417 |

- **`Vault_Low`** is a speed vault: off the left foot, the left hand flat on the top 0.12 m in from the front edge and
  0.27 m left of the body's line, both legs over to the right and stacked (the right leg leads above like a
  hurdler's, the left tucks under it; they never cross), down on the right foot. The right hand never
  comes nearer the obstacle than 0.6 m and keeps the sprint's fist, so it can hold the pistol; the clip does not seat
  the fingers on a weapon ([Weapons](../../../tools/blender/weapons.md#hands-on-the-weapon) does that per weapon).
- **`Vault_High`** is a two-handed side vault for what the low one cannot do: a short step, off the right foot with
  both hands on the top (0.10 m in, 0.24 m each side), the hips up over the hands, the right hand off first to let the
  legs by. Both hands are open on the obstacle, so it holds no weapon: the vault code holsters or hides one.
- **`Vault_Land`** is the step after either: both vaults end in the sprint's right foot strike (0.333 s into
  `Sprint`), where `Vault_Land` starts, and it ends in the left foot strike (`Sprint` at 0 s), where both vaults start.
  A game that wants the run back sooner can go from a vault straight to `Sprint` at 0.333 s.
- **Why two vaults.** A one-handed vault carries the hips past a hand that is under the shoulder: at 0.8 m the hips
  rise 0.2 m over a running stride, at 1.3 m they would rise 0.7 m off one foot with the hand at shoulder height
  (1.44 m on the mannequin), which no body does. Parkour coaching puts most vaults between knee and hip height and
  shipped systems switch clips by height (the research is in the pull request of #1010), so the low clip covers about
  0.5 to 1.0 m and the high one about 1.0 to 1.3 m; above that is a climb (`ClimbUp_1m` and a mantle).
- **Warping one clip to another obstacle** (for #1013 to confirm in play): the pose over the obstacle is a rigid body
  on a hand, so another height is the body lifted by the difference while a hand is on the top (none at the last
  ground contact, all of it from the hand plant to the hand's release, none at the landing), and the wrist stays 36 mm
  over the top at any height. Another depth is more travel between the hand's release and the landing; another speed
  is the clip's rate. `tools/capture/vault_study.tscn` does the height warp (`LOW_HEIGHT`, `HIGH_HEIGHT`) and plays the
  clips over their boxes from four views; headless, it prints the contact numbers.
- **The male mannequin's arms are longer** (0.54 m shoulder to wrist against the female's 0.49 m), and the clips were
  keyed on the female, the template's default. On the male the planted wrist moves 37 mm in `Vault_Low` and 76 mm in
  `Vault_High` while it should be still, and sits up to 45 mm low. The vault code puts the hand on the edge by IK if
  that shows; the clip cannot be right for both.
- **No limb passes through another**, on either mannequin: the build measures every frame of every clip on both
  skinned meshes (`assets/animation/limb_overlap.py`, the approach under
  [Keyframes](../../../tools/blender/animation.md#keyframes)) and fails over 5 mm; the clips read 0.5 mm at most
  (the thighs brushing on one frame of `Vault_High`). `vault_clips.json` carries the numbers and the hash of the
  file they were measured on, and `tests/assets/test_vault_clips.gd` fails when either is off.

- **Approach:** Turn the importer's animation optimizer off for a clip with a contact (`_subresources` in the
  `.import`: `"nodes": {"PATH:AnimationPlayer": {"optimizer/enabled": false}}`), and test the contact in Godot, on
  every planted frame, with the body moved as the game moves it. **Watch out for:** the optimizer dropped the
  forearm's key on the middle frame of the hand plant (the elbow was straight, bent 43 degrees and straight again on
  three frames), so Godot played the wrist 107 mm off the box on that frame while the build's checks in Blender read 0.
  **Seen:** gdstudio #1010, 2026-11-10 (fix: the optimizer off, the arm kept bent through the plant, and
  `tests/assets/test_vault_clips.gd`).
- **Approach:** Pick a mannequin's skinned mesh by its parent (the armature) or its armature modifier. **Watch out
  for:** `mannequin_female.glb` holds a stray 42-vertex `Icosphere` beside `Mannequin_F`, and it comes first, so a
  build that took the first mesh measured nothing and failed on an empty list. **Seen:** gdstudio #1010, 2026-11-10.
