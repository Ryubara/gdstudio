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
- **Approach:** Import a clip file whose keys a build already reduced and checked (GDStudio's own clips,
  `assets/animation/own/`, the library `gds`) with the importer's optimizer off and track compression on (in the
  `.import`: `_subresources` > `nodes` > `PATH:AnimationPlayer` > `optimizer/enabled` false, `compression/enabled`
  true, `compression/page_size` 8), and test a planted foot on the imported library, not on the file.
  **Watch out for:** the glTF import samples every track at `animation/fps` whatever keys the file holds, so sparse
  keys do not arrive sparse: the default optimizer then moved a planted foot 4 mm in a slow idle (the build held it
  to 0.3 mm), its error settings changed nothing, and with it off the 10 s clip was 256 KB; compressed it is 39 KB
  with the foot within 1 mm. **Seen:** gdstudio #1154, 2026-11-11 (`tests/gameplay/test_own_clips.gd`).
- **Approach:** When a clip of our own replaces a library clip, move its constant (`CharacterClips.IDLE` is
  `gds/Idle`), keep the library clip in `CharacterClips.STAND_INS`, and read a clip file the game does not import
  (a review file under a `.gdignore`) with `GLTFDocument` at run time. **Watch out for:** `GLTFDocument` keeps the
  `_Loop` suffix and leaves the clip unlooped, which the importer's scene step would have fixed; a clip count
  asserted in a test (`ALL.size()`) moves with every clip added. **Seen:** gdstudio #1154, 2026-11-11
  (`tools/capture/own_clips_review.gd`).
- **Approach:** Test a gait of our own by what holds for a rolling foot and a run: the patch of the sole on the
  floor stays put along the travel curve (the toes' joint, after the first quarter of the contact, which is the
  roll onto it; the ankle travels), each arm goes with the other side's leg, the
  two feet land half a cycle apart, and the clip's `speed` is the game's. **Watch out for:** the first
  tests held the ankle still through a contact, which a heel-to-toe roll moves, and looked for the arms
  widest on the landing frame, which is true of a walk and not of a run; a footstep count asserted for the
  library's walk (90 steps a minute) is wrong for ours (138). **Seen:** gdstudio #1155,
  2026-11-11 (`tests/gameplay/test_own_clips.gd`, `test_footsteps.gd`).
- **Approach:** Hold a rolling foot's joint along the floor and in height apart, on the bodies the game wears
  (`CharacterBodies`), and give a limit the import's own share: measure the same joint with
  `compression/enabled` off before blaming the clip. **Watch out for:** on the prototype bodies the toes' joint
  stays within 0.4 mm along the floor and comes down 5.2 to 5.7 mm as the foot rolls off (the build sets the
  turned-up sole's skin on the floor), which one distance read as a 5 mm slide; and the idle's planted joints
  move 0.2 mm in the build and 1.1 to 1.4 mm in Godot, the rest being the compressed tracks' rounding (0.2 to
  0.5 mm with compression off), over the test's first 1 mm. **Seen:** gdstudio #1155 (PR #1275), 2026-11-11
  (`ROLLING` 1 mm, `ROLL_DROP` 7 mm, `PLANTED` 1.5 mm).
- **Approach:** After a gait changes, run every suite that measures a pose over the gait, not only the gait's
  own: an action that fades in over it (the vault, `test_vault_contacts.gd`), the carried weapon
  (`test_pistol_clearance.gd`) and a shot at a running body (`test_net_ai_rewind.gd`). **Watch out for:** the
  ground blend space plays its loops out of step (`sync` advances them by the same time, not the same phase), so
  between the walk's and the jog's speeds a foot is a mix of two strides: with our own gaits the ball of a foot
  was 20 mm under the floor as a vault began and 43 mm under half way into its 0.1 s fade, where the library's
  shorter strides stayed inside the test's 20 mm. The vault's floor check counts from the end of the fade; the
  phases are kit #1158's. **Seen:** gdstudio #1155, 2026-11-11.
- **Approach:** After rebuilding the idle, measure the aiming muzzle again and move `Weapon.no_muzzle_offset` (and
  its copy in `test_weapon.gd`) to it: `test_weapon_ray.gd` prints the muzzle from the eye in the view's axes.
  Run the weapon suites after every merge of main as well as after a rebuild. **Watch out for:** the offset is
  where the pistol's muzzle is while the character aims standing on the idle, so the idle solved again on the
  prototype bodies put it 6.2 mm from the real muzzle, over the test's 5 mm; the full run before the merge had
  passed, because main's steady stance under the aim, which set the offset to main's idle, landed in between.
  **Seen:** gdstudio #1155 (PR #1275), 2026-11-11 (the offset's z from -0.716 to -0.722).
- **Approach:** When a `CharacterClips` constant moves to another library, grep for every table that lists libraries
  by name (`grep -rn LIBRARIES`, `universal/ual1`: `tests/fixtures/hold_stage.gd`, `pistol_clearance.gd`,
  `tools/ragdoll/measure_joints.gd`) and add the library, then run the weapon and hold suites (`test_weapon*.gd`,
  `test_pistol_hold.gd`, `test_pistol_clearance.gd`, `test_aim_brace.gd`) before the full run. **Watch out for:** a
  fixture that builds its own `AnimationPlayer` knows only the libraries its table names, so the moved clip is
  missing there and nowhere else; and every upper-body layer rides the pelvis of the clip under it, so a new idle
  turned the aim 13 degrees and moved the muzzle 0.22 m ([the aim](shooting.md#crouch-aim-shoot)). **Seen:** gdstudio #1154,
  2026-11-11 (16 cases red in the full run after only the two touched suites were run).
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

## The fixed clips {#fixed-clips}

<!-- new section: since kit #1187 the template wears the prototype bodies, and three library clips cross a forearm
and a shin on them (kit #1295); the corrected copies are a library of their own -->

`assets/animation/fixed/fixed.glb` is the `AnimationLibrary` `fixed`: `Jump_Land` (from `ual1`), `Slide_Exit` and
`NinjaJump_Land` (from `ual2`) with one upper arm swung 4 to 11 degrees outward on the frames where its forearm was
6.5 to 12.3 mm inside the shin on `form_female`, eased in and out; every other key is the library's
([how it is built](../../../tools/blender/animation.md#corrected-clips)). `CharacterClips.LAND` and `SLIDE_EXIT` name
the fixed clips, `CharacterClips.STAND_INS` maps each to the library clip it came from, and
`tests/assets/test_fixed_clips.gd` holds the file to what the build measured and to the library's keys. A fixture
that builds its own `AnimationPlayer` and plays `CharacterClips` constants adds the `fixed` library beside `ual1` and
`ual2` (`tests/fixtures/pistol_clearance.gd`). `tools/capture/fixed_clips_tour.tscn` films both clips from the game
camera, and with `LIBRARY_CLIPS=1` the library's.

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
- **On the template's bodies** (the prototype `form` pair, `CharacterBodies`, since kit #1187; measured in kit #1286
  by `tests/assets/test_vault_clips.gd`, which poses all four bodies): the planted wrist slides 18 and 72 mm on
  `form_female` (low and high vault) and 35 and 82 mm on `form_male`, and rides 29 to 67 mm off its height over the
  top (on `form_male` up to 31 mm into the box); `Vault_High` puts the thighs 34.0 mm (`form_female`) and 23.6 mm
  (`form_male`) into each other where the legs come over together. The feet, the joins to the sprint and to
  `Vault_Land`, the free arm, the push and the legs' spread pass on every body. The suite holds those numbers as the
  bodies' limits (`PER_BODY`, `KNOWN_OVERLAP_MM`) until kit #1294 solves them.
- **No limb passes through another**, on either mannequin: the build measures every frame of every clip on both
  skinned meshes (`assets/animation/limb_overlap.py`, the approach under
  [Keyframes](../../../tools/blender/animation.md#keyframes)) and fails over 5 mm; the clips read 0.5 mm at most
  (0.0 mm since the rework of 2026-11-11). `vault_clips.json` carries the numbers and the hash of the
  file they were measured on, and `tests/assets/test_vault_clips.gd` fails when either is off. The template's bodies
  are measured beside them in `vault/bodies_overlap.json` (`limb_overlap.py --brief`,
  [Limbs inside limbs](../../../tools/blender/body-crossings.md#library-clips)), read by the same suite.
- **How the vault plays them** (kit #1037): the `VaultClip` resources `gameplay/character/vault_low.tres` and
  `vault_high.tres` carry the numbers of `vault_clips.json` (a test holds them equal), and the vault is
  [timed by the clip](traversal.md#clip-timing): it starts at the frame that fits the distance, the root moves level
  and forward through the clip's contact places, lifted by the difference to another height while a hand is on the
  top, and `Vault_Land` follows in the same action. The capsule still goes over the top; only the model is held on
  the clip's root.

- **Approach:** Check a contact clip at the game's frame rate as well as on its own keys: sample every joint that
  passes an edge at 60 a second (or finer) between the keys. **Watch out for:** `Vault_Low` moves the left knee 0.5 m
  in one of its 24 frames a second, from before the front edge to over the top; both keys are clear of the box and
  the build's checks pass, and the frames Godot draws between them cut the corner by up to 68 mm. A limit for a
  peak between keys is set over its worst instant, measured at several draw rates (59, 61, 121, 179 and 240 frames
  a second sweep the instant a frame lands on); one run's frames read anything from 0 to the peak. **Seen:** gdstudio
  #1037, 2026-11-11 (`test_vault_contacts.gd` allowed 55 mm from runs that read 48 mm, and failed in CI at 66 to
  68 mm once main's other suites shifted the frames; it allows 75 mm now; the clip's fix is gdstudio #1221).
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
