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
  true, `compression/page_size` 32), and test a planted foot on the imported library, not on the file.
  **Watch out for:** the glTF import samples every track at `animation/fps` whatever keys the file holds, so sparse
  keys do not arrive sparse: the default optimizer then moved a planted foot 4 mm in a slow idle (the build held it
  to 0.3 mm), its error settings changed nothing, and with it off the 10 s clip was 256 KB; compressed it is 39 KB
  with the foot within 1 mm. **Seen:** gdstudio #1154, 2026-11-11 (`tests/gameplay/test_own_clips.gd`).
- **Approach:** Give a compressed library a page (`compression/page_size`, in KiB) larger than its densest
  clip, and compare every bone's place and turn in the imported clips, frame by frame, with the same file read
  uncompressed at run time (`GLTFDocument`; a loop is `<name>_Loop` there).
  **Watch out for:** with 8 KiB pages `Land_Hard` (38 frames, 61 tracks with a key on nearly every frame) was
  split over pages and the pelvis's place lost its keys from frame 16 to 28 (Godot held frame 15's value, a
  planted foot 194 mm off), while the file's keys were right. At 32 KiB every clip is within 0.05 mm and
  0.07 degrees of the file, and the import is 183 KB.
  **Seen:** gdstudio #1161, 2026-11-12 (`locomotion.glb.import`; the test is
  `test_own_jump_clips.gd`'s `test_the_import_keeps_every_clip_s_motion`).
- **Approach:** When a clip of our own replaces a library clip, move its constant (`CharacterClips.IDLE` is
  `gds/Idle`), keep the library clip in `CharacterClips.STAND_INS`, and read a clip file the game does not import
  (a review file under a `.gdignore`) with `GLTFDocument` at run time. **Watch out for:** `GLTFDocument` keeps the
  `_Loop` suffix and leaves the clip unlooped, which the importer's scene step would have fixed; a clip count
  asserted in a test (`ALL.size()`) moves with every clip added. **Seen:** gdstudio #1154, 2026-11-11
  (`tools/capture/own_clips_review.gd`); gdstudio #1160, 2026-11-11 (the crouch clips: `CROUCH_IDLE` and
  `CROUCH_WALK` moved to `gds/`, and the count test failed at 91 for 95, as this entry warns).
- **Approach:** Add a pose over a gait as a difference of two clips of the library: `AnimationNodeSub2` (the lean
  pose, less `gds/Lean_Ref`) into `AnimationNodeAdd2`, with the weight the lean wanted over the `degrees` the
  pose's record gives (`lean` in `locomotion.json`); read a directed gait's `heading`, `speed` and `in_step_with`
  from its record. **Watch out for:** nothing plays `gds/Walk_Back`, `Walk_Left`, `Walk_Right`, `Jog_Back`,
  `Jog_Left`, `Jog_Right` or the four lean poses yet (the tree is kit #1158); their speeds are their own (1.3, 1.2
  and 3.0 m/s), not the tuned ones, and over a gait a lean's leg share moves the feet, which only foot placement
  holds. **Seen:** gdstudio #1159, 2026-11-12 (`tests/gameplay/test_own_directions.gd`: the sum over the reference
  is the pose within 0.06 degrees, the soles within 0.7 mm of the floor).
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
  **Seen:** gdstudio #1155 (PR #1275), 2026-11-11 (the offset's z from -0.716 to -0.722) and 2026-11-12 (main's
  pistol seat, #1262, moved the muzzle and the line conflicted: taking main's -0.728 failed by 6 mm; it is -0.734).
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
  and 275 KB with compression ([what the clips cost](../../../tools/blender/library-clip-audit.md#audit-cost)). **Watch
  out for:** the library files key a position on every bone, their own body's bone lengths; `remove_immutable_tracks`
  drops those constant tracks on import, and a body of other proportions that plays them stretches its neck and limbs
  to the mannequin's. **Seen:** gdstudio #1150 (PR #1165), 2026-11-11 (the sizes); gdstudio #1149 and #1151,
  2026-11-11 (the position tracks).
- **Approach:** When a new library joins the character's `AnimationPlayer` (`prone`, `melee`, `gds`), add a
  `LIBRARY_*` constant, a constant per clip and every clip name to `CharacterClips.ALL` in the same commit, and raise
  the count in `test_character_clips.gd`. **Watch out for:** `test_every_listed_clip_exists_and_every_clip_is_listed`
  counts every clip of every library on the player, so a library added only to `character_dressed.tscn` passes every
  targeted suite and fails only in the full run. **Seen:** kit #1254, the six melee clips (90 to 96, then 99
  beside the three vault clips of #1239).

## The fixed clips {#fixed-clips}

<!-- new section: since kit #1187 the template wears the prototype bodies, and three library clips cross a forearm
and a shin on them (kit #1295); the corrected copies are a library of their own -->

`assets/animation/fixed/fixed.glb` is the `AnimationLibrary` `fixed`: `Jump_Land` (from `ual1`), `Slide_Exit` and
`NinjaJump_Land` (from `ual2`) with one upper arm swung 4 to 11 degrees outward on the frames where its forearm was
6.6 to 12.2 mm inside the shin on `form_female`, eased in and out; every other key is the library's
([how it is built](../../../tools/blender/animation.md#corrected-clips)). `CharacterClips.LAND` and `SLIDE_EXIT` name
the fixed clips, `CharacterClips.STAND_INS` maps each to the library clip it came from, and
`tests/assets/test_fixed_clips.gd` holds the file to what the build measured and to the library's keys. The file
also holds, since kit #1320, `Sword_Dash` and `Sword_Heavy_Combo` (from `ual2`, played by nothing in the template), whose
thighs passed through each other by 17 to 26 mm on both bodies: one leg is swivelled about the line from its hip to
its ankle (41 and 22 degrees at most) and its foot keyed back to the library's turn, so each foot stays within 0.57 mm
of the library's on every frame, which the same test checks in Godot's own pose on both bodies. The two clips add
553 KB to the file (946 KB for five clips). A fixture
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
  ground contact, all of it from the hand plant to the hand's release, none at the landing), and the wrist stays its
  own height over the top (`wrist_above_top`, 22 to 36 mm by body) at any height. Another depth is more travel between
  the hand's release and the landing; another speed is the clip's rate. `tools/capture/vault_study.tscn` does the
  height warp (`LOW_HEIGHT`, `HIGH_HEIGHT`) and plays the clips over their boxes from four views; headless, it prints
  the contact numbers.
- **A file a body** (kit #1294). A planted hand is on its place only on the arms the clip was solved for, and the
  legs go over clear of each other only on the thighs they were keyed around, so `build_vault.py --body <name>`
  solves the same keys on each body and writes a file for it: `vault.glb` and `vault_clips.json` on `form_female`
  (the template's default body, `CharacterBodies.FEMALE`), `vault_male.glb` on `form_male`, and
  `vault_quaternius.glb` on the Quaternius female, the bytes the one file had before, which the Quaternius male plays
  too. The character's `vault` library follows its model (`CharacterAnimation.vault_libraries` in
  `character_dressed.tscn`, the model's scene file to its library, as `prone_libraries`). Every file has the clips at
  the same lengths, speeds, contact times, root places and hand places (the build fails a body whose numbers differ
  from the default's, and a Godot test holds it), so the `VaultClip` resources are one set; only the wrist's height
  over the top is the body's own (22 mm on `form_female`, 28 mm on `form_male`, 36 mm on the Quaternius female: the
  thickness of the palm).

  | Body, in its own file | Planted wrist moves, low / high | Off its height | Deepest limb in limb | Before, in the one file |
  | --- | --- | --- | --- | --- |
  | `form_female` | 0.0 / 0.0 mm | 0.0 / 0.0 mm | 4.5 mm (thighs, `Vault_High` frame 14) | 18.7 / 72.3 mm, 15.5 / 31.2 mm, 34.0 mm |
  | `form_male` | 0.0 / 0.0 mm | 0.0 / 0.0 mm | 4.6 mm (thighs, `Vault_High` frame 16) | 35.2 / 82.2 mm, 59.0 / 48.2 mm, 23.6 mm |
  | Quaternius female | 0 / 0 mm | 0 / 0 mm | 0.0 mm | the same file |
  | Quaternius male (her file) | 34 / 79 mm | 49 / 41 mm | 3.1 mm (feet) | the same file |

  What a body's arms and thighs move is a short list of numbers in the build's `BODIES` table, each explained where
  the clip reads it: the wrist's height over the top and the heights of the centre of mass at the joins (measured);
  how far the wrist lifts on the frame it pushes off and how far the fingers tip (a longer arm is still bent when the
  body has passed: 141 degrees on `form_female` with the first keys, 176 now); the collarbone's lift on the male; and
  in `Vault_High` the lower leg's foot further out from the hips past the front edge (75 and 100 mm), the knees a
  little further out, and the lower foot further back and down on the frame at the edge.
- **No limb passes through another**: each build measures every frame of every clip on the skinned mesh of the body
  its file is for (`assets/animation/limb_overlap.py`, the approach under
  [Keyframes](../../../tools/blender/animation.md#keyframes)), with the body's twist bones turned as the game turns
  them, and fails over 5 mm (the table above). Each file's sidecar carries the numbers and the hash of the file they
  were measured on, and `tests/assets/test_vault_clips.gd` fails when either is off. `vault/bodies_overlap.json`
  (`limb_overlap.py --brief`, [Limbs inside limbs](../../../tools/blender/body-crossings.md#library-clips)) holds the
  two bodies that share `vault_quaternius.glb`, read by the same suite.
- **The legs clear the box between the keys too.** A game draws the clip 60 times a second and more, with the 24
  keys a second joined by straight lines, so the build reads the pose 240 times a second, joined the same way, with
  the root moved at the clip's speed: no leg joint of the file's body more than 5 mm inside the box (0.0 in both
  vaults), no skin more than 12 mm (0.0 in `Vault_Low`, 4.4 mm of a forearm in `Vault_High`). In `Vault_Low` the left
  knee swings out to the right with the rolled body on frame 7, before the front face, and is 0.065 m over the top
  where it crosses the edge (0.285 s); the lead foot is lifted with the toes up on frame 5 and its ball is 0.07 m over
  the top at the edge. A planted palm presses up to 16.3 mm into the top between two keys and the sole of the sprint's
  foot strike 20.8 mm into the floor, under the contact, which the build allows (20 and 25 mm).
  `tests/assets/test_vault_clips.gd` reads the leg joints at the same rate in Godot, and the `_edge` sheet draws the
  poses between the keys at the front edge.
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
- **Approach:** Check a clip against the obstacle between its keys as well, 240 times a second with the keys joined
  as the player joins them, and key a limb that swings past an edge over the edge's height a frame before it gets
  there. **Watch out for:** `Vault_Low`'s left knee was before the front face and under the top on frame 7 and past
  it and over the top on frame 8, both keys clear; on the frames a game draws between them it was 60 mm inside the
  wall (the skin 76 mm), and the lead foot's toes 40 mm between frames 5 and 6. The knee's pole pointed forward
  while the ankle passed behind the hip, so the knee hung down and whipped forward in one frame. **Seen:** gdstudio
  #1221, 2026-11-11 (found by #1037's test in the game; fix: `check_between` in `build_vault.py`, the knee keyed out
  beside the rolled body on frame 7, the lead foot lifted on frame 5).
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
- **Approach:** Solve a clip with a planted hand once for each body that plays it, from one set of keys, into a
  file a body, and hold every file to the default body's numbers in the build. Give a body its own number only where
  its arms or thighs force one, and name each in one table. **Watch out for:** one file keyed on the Quaternius
  female slid the planted wrists of the bodies the template wears 18 to 82 mm over the top and put their thighs 24 to
  34 mm into each other; solved on `form_female`, the same file put the Quaternius female's free hand 41.5 mm into
  her thigh, so no one body's file serves the others. The thighs crossed at the crotch, where the lower leg lay
  across under the upper one: moving the knees apart did little (the knees were 1.9 hip widths apart with 8 mm still
  crossing), moving the lower leg's foot out from the hips cleared it. **Seen:** gdstudio #1294, 2026-11-11.
- **Approach:** Pick a mannequin's skinned mesh by its parent (the armature) or its armature modifier. **Watch out
  for:** `mannequin_female.glb` holds a stray 42-vertex `Icosphere` beside `Mannequin_F`, and it comes first, so a
  build that took the first mesh measured nothing and failed on an empty list. **Seen:** gdstudio #1010, 2026-11-10.
- **Approach:** Keep the capsule out of geometry through a vault: it goes up and over the top as a body's would, and the
  model, not the capsule, follows the clip's level root through the crossing (held in the world for the move, with the
  camera's target moved by the same difference so the view stays level). **Watch out for:** this section said the clip's
  root goes level through the wall and nothing about the capsule, so it read as moving the body through the wall; the
  capsule has to stay where the physics world (and a server, stepping the same plan) can move it, so the model leaves it
  for the crossing. **Seen:** gdstudio #1037 (PR #1239), 2026-11-11 (`VaultAnimation` holds the model).

## The gait settings {#gait-settings}

<!-- new section: the tree's gaits gained speed matching, transitions, a momentum blend and a lean (gdstudio #1158),
each an inspector choice that a game and the clip issues that follow need to find -->

`CharacterAnimation.gait_settings` (`GaitSettings`, the template's characters share
`gameplay/character/gait_settings.tres`; empty, its defaults) fits the gaits to the body's real motion. How the tree
does it is on [AnimationTree](../animation-tree.md#gait-fitting). All of it is cosmetic: never sent.

| Setting | Default | What it does |
| --- | --- | --- |
| `speed_match` | on | the gait points at the clips' speeds (`clips.json` times the body's leg length over the reference's), each gait played at the ground speed over its own; off, the points at the tuning's speeds and every clip at its own pace |
| `pace_range` | 0.4 to 2 | the slowest and fastest a gait is played |
| `stretch` | 0.8 to 1.3 | how far a gait is slowed and sped up alone before the next blends in: the walk alone to 2.21 m/s, the walk and the jog blended to 3.2, the jog alone to 5.2 |
| `slowest_pace` | 0.5 | the walk alone down to half its pace (0.85 m/s), fading into the idle below |
| `transitions`, `transition_clips` | on, `GaitTransitionSet` | a start, a stop, a reversal, a pivot or a turn on the spot when the controller does one and its clip exists |
| `pivot_angle`, `reversal_angle`, `turn_angle`, `standing_speed` | 45, 135, 50 degrees, 0.3 m/s | the controller's numbers that pick them |
| `momentum_blend`, `momentum_half_life`, `momentum_speed_limit` | on, 0.05 s, 720 degrees a second | a change of body state shows at once and the difference from the drawn pose dies away (`MomentumBlend`), in place of the cross-fade over `blend_time` |
| `lean`, `lean_clips`, `lean_full_at`, `lean_time` | on, `gds/Lean_Left` and the rest, 20 m/s², 0.12 s | the lean into the acceleration, built only when the four lean clips exist |

**What a transition clip needs** (gdstudio #1156, #1157). A name in `GaitTransitionSet` is a base: the tree plays
`<base>_L` or `<base>_R` when it is in the libraries, else `<base>`. The side is the foot that steps off (a start),
the foot that lands next in the gait's phase (a stop, a reversal) or the way the body turns (a pivot, a turn on the
spot). The defaults are `gds/Idle_To_Walk`, `gds/Idle_To_Jog`, `gds/Idle_To_Sprint`, `gds/Walk_Stop`,
`gds/Jog_Stop`, `gds/Sprint_Stop`, `gds/Jog_Turn_180`, `gds/Sprint_Turn_180`, `gds/Jog_Turn_90`,
`gds/Turn_In_Place_90` and `gds/Turn_In_Place_180`. From its record in `clips.json` the tree reads `travel` (a start
or a stop is played at the time its travel has covered the ground the body really covered), `turn` (a reversal, a
pivot or a turn: the time it has turned as far as the body), and `exit_phase` (the share of the gait's cycle it ends
on), or else `end_foot` (`l`: the gait goes on from 0, `r` from half its cycle). A clip whose body has finished its
part plays on at its own pace; a body asked for something else leaves it at once. Until the clips exist nothing
plays and the states change as before.

**What a lean clip needs** (gdstudio #1159): its first frame is the pose leaning one way; what the tree adds is that
pose's difference from the idle's first frame.

The cost, from `tools/bench/gait_cost.tscn` (`gds template bench-web 3d-third-person gait_cost --run`, headless
Chrome on a workstation, the settings off and on in turns, players walking, blending, sprinting and stopping): 38 µs a
frame for one character, 17 µs a character with 40 (4.28 ms off, 4.97 ms on); headless desktop, 12 µs a character
with 40. The momentum blend reads 25 body bones a frame on each character and turns the ones that differ for 0.4 s
after a change; the transitions ask nothing of the body while no transition clip is in the libraries.
