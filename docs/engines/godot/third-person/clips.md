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
- **Approach:** Keep the library glbs' import at the defaults (the optimizer and `remove_immutable_tracks` on) and
  read the costs before changing one: `ual1.glb` imports at 1,560 KB with the optimizer off, 752 KB at the defaults
  and 275 KB with compression ([what the clips cost](../../../tools/blender/own-animation.md#audit-cost)). **Watch out
  for:** the library files key a position on every bone, their own body's bone lengths; `remove_immutable_tracks`
  drops those constant tracks on import, and a body of other proportions that plays them stretches its neck and limbs
  to the mannequin's. **Seen:** gdstudio #1150 (PR #1165), 2026-11-11 (the sizes); gdstudio #1149 and #1151,
  2026-11-11 (the position tracks).

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
| `Vault_Low` | 0.792 s (19 frames at 24) | 0.8 m high, 0.4 m deep | 4.0 m/s (3.17 m) | -1.30 m, +1.87 m | left foot off 0.167, left hand on 0.250, hips over the middle 0.375, wrist off 0.375, fingers off (the push) 0.417, right foot down 0.792 |
| `Vault_High` | 1.250 s (30 frames) | 1.2 m high, 0.4 m deep | 3.0 m/s (3.75 m) | -1.86 m, +1.89 m | right foot off 0.458, both hands on 0.458, right hand off 0.500, hips over 0.667, left wrist off 0.667, fingers off (the push) 0.708, right foot down 1.250 |
| `Vault_Land` | 0.417 s (10 frames) | none | 4.0 m/s (1.67 m) | | right foot down 0, hips lowest 0.125, off 0.208, left foot down 0.417 |

- **`Vault_Low`** is a speed vault: off the left foot, the left hand flat on the top 0.12 m in from the front edge and
  0.27 m left of the body's line, both legs over to the right and stacked (the right leg leads above like a
  hurdler's, the left tucks under it; they never cross), down on the right foot. The right hand never
  comes nearer the obstacle than 0.6 m and keeps the sprint's fist, so it can hold the pistol; the clip does not seat
  the fingers on a weapon ([Weapons](../../../tools/blender/weapons.md#hands-on-the-weapon) does that per weapon).
- **`Vault_High`** is a two-handed side vault for what the low one cannot do: a short step, off the right foot with
  both hands on the top (0.10 m in, 0.24 m each side), the hips up over the hands, the right hand off first to let the
  legs by. Both hands are open on the obstacle, so it holds no weapon: the vault code holsters or hides one.
- **The legs go over together, to the right.** In `Vault_High` the hips roll onto the left arm (72 degrees at the
  push) until the body lies on its side over the top, and both legs trail beside the hips, parallel to the obstacle, a
  hip width apart (the knees 1.6 hip widths at most while the hips are over the box, 3.8 before the fourth review)
  with the knees near a right angle (65 degrees at the tightest, 14 before), the right leg on top. The hips cross the
  front edge 0.26 m over the top and are 0.34 to 0.42 m over it across the box (0.16 and 0.29 to 0.33 before: the lean
  puts the pelvis nearer the centre of mass, whose arc is unchanged). The feet cross the front edge two frames after
  the hips; past the far edge the legs swing forward and down in one move (no ankle slower than 2 m/s against the
  hips; five frames under 0.7 before). The build and the Godot suite hold it (`LEGS_*`).
- **The arm that lets go follows the body.** `Vault_High`'s right hand leaves the top with its elbow still bent (84
  degrees), lifts ahead of the right knee as that leg swings over, and from four frames after the release rides out
  to the right a little under shoulder height, a balance arm, until it comes down and back into the sprint's swing
  with the landing. Its wrist is never over its shoulder (0.01 m under at the highest, 0.30 m over before the third
  review), it gains speed over four frames (2.6, 4.6, 5.3, 5.1 m/s in the world, where the body itself moves at
  3.6) and never moves faster than 4.1 m/s against the shoulder (9.4 before). `Vault_Low`'s free right arm is keyed
  the same way: it lies back along the upper side of the rolled body, the wrist at shoulder height (0.01 m over;
  0.37 m before), and opens out to the right as the body comes upright. The build and the Godot suite hold both
  (`FREE_*`; the male's longer arms read up to 0.03 m over the shoulder and 6.9 m/s).
- **`Vault_Land`** is the step after either: both vaults end in the sprint's right foot strike (0.333 s into
  `Sprint`), where `Vault_Land` starts, and it ends in the left foot strike (`Sprint` at 0 s), where both vaults start.
  The body arrives still falling (2.8 m/s after the low vault, 3.9 m/s after the high one), so the clip's first three
  frames are the landing: the knee gives from 162 to 94 degrees and the hips drop 0.14 m, the chest comes forward,
  then the leg drives off. A game that goes from a vault straight to `Sprint` at 0.333 s loses that.
- **The planted arm carries the body, and its push is the time in the air.** In `Vault_Low` the left hand is on the
  top for 0.167 s (four frames; the wrist is still for three, then the heel of the hand lifts and the fingers leave
  last). The elbow is at 148 degrees when the hand lands, gives to 121 as the shoulder comes over the hand, and is
  straight (176) when the hand leaves, behind the body; the chest turns toward the hand as the body goes by and the
  right arm lies back along the upper side of the body, no higher than its shoulder. Through the contact the arm
  carries the whole body (1.04 of its weight on average: the body comes onto the hand rising at 0.82 m/s and leaves it
  at 0.89 m/s, where gravity alone would have taken 1.6 m/s off). In `Vault_High` the hands land with the arms folded
  under the body (78 degrees), the arms straighten as the hips rise over them (to 176 when the left hand leaves, 0.25
  s after the plant) and carry 0.4 of the body's weight while the jump does the rest.
- **In the air the body is on the arc of a free fall**, measured at its centre of mass (the usual table of body
  segment masses on the bones), not at the pelvis. `Vault_Low`: 0.375 s from the hand's push to the landing, up
  0.04 m more for 0.09 s, then 0.40 m of fall in 0.28 s; `Vault_High`: 0.542 s, up 0.095 m for 0.14 s (the top is
  past the far edge), then 0.80 m of fall in 0.40 s. Both are within 0.3 mm of the arc on every frame. The landing
  leg opens a little more each frame on the way down (in `Vault_Low` the knee from 89 to 139 degrees over six
  frames, the foot lower on every frame) and lands at 162.
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
  keyed on the female, the template's default. On the male the planted wrist moves 35 mm in `Vault_Low` and 71 mm in
  `Vault_High` while it should be still, and sits up to 49 mm low. The vault code puts the hand on the edge by IK if
  that shows; the clip cannot be right for both.
- **No limb passes through another**, on either mannequin: the build measures every frame of every clip on both
  skinned meshes (`assets/animation/limb_overlap.py`, the approach under
  [Keyframes](../../../tools/blender/animation.md#keyframes)) and fails over 5 mm; the clips read 0.5 mm at most
  (0.0 mm since the rework of 2026-11-11). `vault_clips.json` carries the numbers and the hash of the
  file they were measured on, and `tests/assets/test_vault_clips.gd` fails when either is off.
- **What the vault code has to change to play them** (kit #1037; nothing in this section changes the game). The
  clips carry the body's rise and fall themselves, in the pelvis, over the reference obstacle: the code moves the
  root level and forward at the clip's speed, and lifts it only by the difference to another height while a hand is
  on the top. The `Vaultable`'s present path does neither: for the reference wall it takes 1.75 m in 0.45 s and
  drops the body 0.92 m in the last 0.135 s, where a free fall from rest takes 0.43 s, and it lands 1.04 m past the
  front face where the clips land 1.87 m (`Vault_Low`) and 1.89 m (`Vault_High`) past it. To fit the clips:
  `landing_margin` about 1.1 m (from 0.3), the path's height taken from the clip instead of the eased fall,
  `plant_at` and `clear_at` from `hand_plant` and `push_off` as shares of the part of the clip that is played, and
  the crossing's time the clip's own from the frame it starts at (0.54 s from the plant to the landing in
  `Vault_Low`, 0.79 s in `Vault_High`), so `max_vault_time` at 0.9 s holds both.

- **Approach:** Turn the importer's animation optimizer off for a clip with a contact (`_subresources` in the
  `.import`: `"nodes": {"PATH:AnimationPlayer": {"optimizer/enabled": false}}`), and test the contact in Godot, on
  every planted frame, with the body moved as the game moves it. **Watch out for:** the optimizer dropped the
  forearm's key on the middle frame of the hand plant (the elbow was straight, bent 43 degrees and straight again on
  three frames), so Godot played the wrist 107 mm off the box on that frame while the build's checks in Blender read 0.
  **Seen:** gdstudio #1010, 2026-11-10 (fix: the optimizer off, the arm kept bent through the plant, and
  `tests/assets/test_vault_clips.gd`).
- **Approach:** Animate a vault from the planted arm. Decide where the body's centre of mass is on every frame (a
  free fall's arc in the air; on the hand, a rise that ends faster than gravity alone would leave it) and key the
  pelvis from that. Let the arm show it: the elbow bent with the shoulder low over the hand, the arm straight and
  behind the body when the fingers leave, the chest turned to the hand, the other arm out. The speed off the hand is
  the time in the air. **Watch out for:** a pelvis keyed by eye: the hand was on for 0.083 s with a straight arm, the
  path topped out as the hand left, and `Vault_High` stopped a 3.2 m/s rise in two frames (more than twice
  gravity), which read as a body pulled down. **Seen:** gdstudio #1016, 2026-11-11 (the maintainer's review; fix:
  `Clip.drive` and `check_motion` in `build_vault.py`, three cases in `tests/assets/test_vault_clips.gd`).
- **Approach:** When a rise cannot be stopped by gravity before the top you want, slow the rise or move the top later
  and higher, and check the path the game moves the body on against a free fall as well as the clip. **Watch out
  for:** lifting the shoulder to straighten the planted arm drops the hips by as much, since the centre of mass is
  given: the feet went 47 mm into the box until the roll was put back. The `Vaultable`'s own path drops the body
  three times faster than a fall, whatever the clip does. **Seen:** gdstudio #1016, 2026-11-11 (`Vault_High` tops
  out 0.14 s after the hand leaves; the path is kit #1037's).
- **Approach:** Pick a mannequin's skinned mesh by its parent (the armature) or its armature modifier. **Watch out
  for:** `mannequin_female.glb` holds a stray 42-vertex `Icosphere` beside `Mannequin_F`, and it comes first, so a
  build that took the first mesh measured nothing and failed on an empty list. **Seen:** gdstudio #1010, 2026-11-10.
- **Approach:** Keep the capsule out of geometry through a vault: it goes up and over the top as a body's would, and the
  model, not the capsule, follows the clip's level root through the crossing (held in the world for the move, with the
  camera's target moved by the same difference so the view stays level). **Watch out for:** this section said the clip's
  root goes level through the wall and nothing about the capsule, so it read as moving the body through the wall; the
  capsule has to stay where the physics world (and a server, stepping the same plan) can move it, so the model leaves it
  for the crossing. **Seen:** gdstudio #1037 (PR #1239), 2026-11-11 (`VaultAnimation` holds the model).
