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
- **Approach:** Name every library clip the game plays where the export can read it: a `CharacterClips` constant a
  shipped script names, or the clip's name in a scene, a `.tres` or a script; a clip whose name is built at run
  time goes in the project setting `gds_game/clip_export/keep`. **Watch out for:** the export carries `ual1` and
  `ual2` with only the named clips ([replacing](../../../tools/blender/own-animation.md#replacing)), so a clip
  named only in a comment (`SWORD_ATTACK`, `DANCE`), in `ALL` or in `STAND_INS` plays in the editor and in every
  suite and is missing from the web build; `test_export_clips.gd` catches one in the tree, the clip settings or a
  definition, and CI's pack check one the game names and the pack lacks. **Seen:** kit #1366, 2026-11-13.
- **Approach:** When a clip of our own replaces a library clip, run `test_export_clips.gd` and point any case that
  names the old constant's stand-in at one still in `ual1` or `ual2`. **Watch out for:** the stand-in case read
  `CharacterClips.stand_in(LAND)`, and once our landing replaced the fixed one its stand-in was `fixed/Jump_Land`,
  in no pruned library, so the scene that set it kept nothing and the case failed. **Seen:** gdstudio #1369,
  2026-11-14 (the merge with #1428, in the full suite).
- **Approach:** When a new library joins the character's `AnimationPlayer` (`prone`, `melee`, `gds`), add a
  `LIBRARY_*` constant, a constant per clip and every clip name to `CharacterClips.ALL` in the same commit, and raise
  the count in `test_character_clips.gd`. **Watch out for:** `test_every_listed_clip_exists_and_every_clip_is_listed`
  counts every clip of every library on the player, so a library added only to `character_dressed.tscn` passes every
  targeted suite and fails only in the full run. **Seen:** kit #1254, the six melee clips (90 to 96, then 99
  beside the three vault clips of #1239).
- **Approach:** Take a track out of every character's blend by switching it off in the shared clips
  (`Animation.track_set_enabled(track, false)`, once per library at run time: `HelperTracks`); the mixer makes no
  cache for a track no clip has on, and skips it in the blend. **Watch out for:** `remove_track` on a clip of a
  compressed library (`gds`) is refused ("Compressed tracks can't be manually removed"), and the switch holds for
  every player in the process, tests included: a suite that reads the switched-off bones switches them on for itself.
  **Seen:** gdstudio #1438, 2026-11-13 (the `ik_` targets, 286 tracks; `test_own_directions.gd` reads them).
- **Approach:** Compare the rifle's clips (`rifle/rifle_clips.glb`) in Godot within the importer's error, never key for
  key: they import at Godot's defaults, the lossy optimizer on, unlike our locomotion clips (optimizer off, compression
  on: above). **Watch out for:** keys equal in the file came in up to 0.35 degrees apart, so a test that held two
  reloads equal up to their shared seat failed though the build's keys matched. **Seen:** gdstudio #1508 (PR #1515),
  2026-11-14 ([the rifle charge](rifle-charge.md#rifle-charge)).

## The jump's clips {#jump-clips}

<!-- new section: the jump plays GDStudio's own clips since kit #1161, and the page had no place that says
which state plays which and what the tree does not use yet -->

The jump's clips are GDStudio's own, in the library `gds` (`assets/animation/own/locomotion.glb`; how they are
made: [the jump clips](../../../tools/blender/clip-toolkit.md#jump-rows)). The capsule leaves the floor on the
tick of the press, so no clip has a frame on the floor before the take-off, and in the air the body's centre of
mass keeps its place against the capsule: it flies the arc the controller flies.

| State | Export of `CharacterAnimation` | Clip | Stand-in (`CharacterClips.STAND_INS`) |
| --- | --- | --- | --- |
| `JUMP` (rising) | `jump_clip` | `gds/Jump_Start`: the whole 0.4 s rise from the idle's first pose to the rise's, the arms floating up over all of it | `ual1/Jump_Start` |
| `JUMP` from a run | `GaitSettings.run_takeoff_left`, `_right` | `gds/Jump_Start_Run_L` and `_R`: from the jog's left and right foot strikes (its frames 0 and 10), at its speed | the standing take-off |
| `FALL` | `air_clip` (with `rise_clip`, `apex_clip`) | `gds/Jump_Fall`, `Jump_Rise`, `Jump_Apex`: 1.2 s loops in a blend space on the vertical speed, the soles at the capsule's bottom | `ual1/Jump` |
| `LAND` (a fall of `land_clip_speed` or more) | `land_clip` | `gds/Land_Soft`: control back at frame 9 (0.3 s), the settle after | `fixed/Jump_Land` |
| `LAND` from 9 m/s | `GaitSettings.hard_land_clip` | `gds/Land_Hard`: control back at frame 20 (0.67 s), 1.27 s with its settle; the controller holds the body to that frame | `land_clip` |
| `LAND` asked to run | `GaitSettings.run_land_clip` | `gds/Land_To_Jog`: 0.27 s, ends on the jog's right foot strike (frame 10) | `land_clip` |

**How the tree picks them** (`JumpAnimation`, kit #1371). A jump from the ground state at `run_takeoff_speed` (2.5 m/s)
or more takes off from the foot that pushes: the one down at the gait's phase (`clips.json` contacts: the jog's left
from 0 to 0.3 of its cycle, its right from 0.5 to 0.8), else the one that lands next; a gait with no record picks the
take-off whose `joins.first_frame` is nearest the phase. The momentum blend carries no pose speed into the standing
take-off and starts again on one frame more (PR #1530). The take-off plays to its end while the body is in the air, then
the air plays at the body's vertical speed. A landing is picked by the fall speed (`Character.landed`'s on a stepped
body, the fastest fall it was drawn with on a puppet) against each clip's `fall_speed` range. While the body stands it
plays through its settle (the tree stays in `land` after the body's `LAND` state ends); asked to move it gives the body
back at its `control` frame, or at once when the body already moves; `Land_To_Jog` hands over to the jog at the phase of
its `joins.last_frame` (0.5). A clip missing from the libraries leaves its choice to `CharacterAnimation`'s clip, so the
library's play as stand-ins. Cosmetic, never sent: a puppet picks from the state, velocity and goal it is drawn with.
`tests/gameplay/test_jump_tree.gd` holds each case; `tools/capture/jump_tour.tscn` films them on a player's own screen
beside the puppet of it on another's.

**How the controller holds a hard landing** (kit #1535). A fall of `CharacterTuning.hard_land_speed` (9 m/s, the hard
landing's `fall_speed.from`) or more, and at least `land_clip_speed`, puts the body in `LAND` for `hard_land_time`
(0.67 s, its `control` frame over 30) and holds it all that time as an action does (`CharacterLanding`,
`_action_lock`): the push is ignored, the body keeps `hard_land_keep` (0) of its ground speed and loses the rest by
`deceleration`, and it does not turn, jump or aim (an aim held lowers and comes back up when it is given back), and
the lean tick is not taken. With the stick pushed from the touch-down `Land_Hard` plays to frame 20 and the body goes
on at once (`test_jump_tree.gd` leaves it at 0.67 s; 0.32 s before); its planted feet slide 0.31 mm pushed, the same
as standing, and 0.88 mm with the stick held all through the fall (`test_hard_landing.gd`; 252 mm before). A softer
landing holds nothing: `land_time` (0.3 s) in `LAND`, steered at full rate, as before. The hold is step state that was
already there, so the server and a predicting client hold a body the same and nothing new is sent; a puppet's `LAND`
lasts as long as the server's (its state is in the TICK). `CharacterTuning.land_time_after()` and `land_hold_after()`
give both times from a fall speed. A game whose hard landing clip changes sets the two numbers to its record
(`test_hard_landing.gd` holds the defaults to `locomotion.json`); `hard_land_time` 0 holds nothing. `hard_land_keep`
above 0 lets a body that lands with the air's ground speed slide on through the landing, under the in-place clip's
planted feet.

`locomotion.json` says of each clip what the tree reads: `carried` (the capsule carries it), `made_for` (the
tuning numbers it was built to, which `tests/gameplay/test_own_jump_clips.gd` holds to `CharacterTuning`'s
defaults), `fall_speed` (`from`, `to`), `control` (the frame control is back at), `joins` (the clip each end is,
and `first_frame` or `last_frame`, the frame of it).

- **Approach:** Pick a take-off (or any clip that starts from a gait) by the foot that is on the floor at the gait's
  phase, from the record's contacts, and test the pick at phases between the strikes too, against the gait's pose
  bone by bone. **Watch out for:** the first pick took the take-off whose join frame was nearest the phase; at 0.2 of
  the jog the drawn pose was 593 mm (a hand) from the left strike's frame and 401 mm from the right's, so neither
  nearness by phase nor by pose says which foot pushes; on a strike the joined take-off is 46 to 51 mm from the jog.
  **Seen:** gdstudio #1371, 2026-11-14 (`test_jump_tree.gd`).
- **Approach:** Prove a hold on the body by the feet against the same landing standing still (pushed and
  standing slide alike), measured from a quarter into each flat window as `test_gait_stops.gd` does, and the
  body's own ground under 0.5 mm. **Watch out for:** measured from the first flat frame, `Land_Hard`'s left
  ball moved 3.29 mm with the body perfectly still (1.9 mm of it in the first half frame, as the foot settles
  and the momentum blend dies away): the clip's own settle, not a slide the controller made, read as a failure.
  **Seen:** gdstudio #1535, 2026-11-14 (`test_hard_landing.gd`).
- **Approach:** Read what a seek on the ground state set (`GaitBlend.seek_phase`, a hand-over) one update after the
  `travel()` that goes there. **Watch out for:** in the update of the travel the walk point's `current_position`
  still read the phase the ground state was left at (0.22 before a jump; 0.50 the update after), the same frame of
  lag as the drawn pose ([gait fitting](../animation-tree.md#gait-fitting)). **Seen:** gdstudio #1371, 2026-11-14.

## The fixed clips {#fixed-clips}

<!-- new section: since kit #1187 the template wears the prototype bodies, and three library clips cross a forearm
and a shin on them (kit #1295); the corrected copies are a library of their own -->

`assets/animation/fixed/fixed.glb` is the `AnimationLibrary` `fixed`: `Jump_Land` (from `ual1`), `Slide_Exit` and
`NinjaJump_Land` (from `ual2`) with one upper arm swung 4 to 11 degrees outward on the frames where its forearm was
6.6 to 12.2 mm inside the shin on `form_female`, eased in and out; every other key is the library's
([how it is built](../../../tools/blender/animation.md#corrected-clips)). `CharacterClips.SLIDE_EXIT` names the
fixed slide exit; the fixed landing is the stand-in of our own since kit #1161 ([the jump](#jump-clips)).
`CharacterClips.STAND_INS` maps each fixed clip to the library clip it came from, and
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

Moved to [Vaulting's clips](vault-clips.md#vault-clips).

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
| `jump_choices` and the Jump group | on; `gds/Jump_Start_Run_L` and `_R` from 2.5 m/s, `gds/Jump_Rise` and `gds/Jump_Apex` at 3 m/s up and 4 down, `gds/Land_Hard` from 9 m/s of fall, `gds/Land_To_Jog` asked to run at 2.5 m/s | the jump's clips picked by the body's numbers ([the jump's clips](#jump-clips), `JumpAnimation`); off, `jump_clip`, `air_clip` and `land_clip` alone |
| `helper_tracks` | off | the clips' `ik_` target tracks blended; off, switched off in the game (`HelperTracks`, gdstudio #1438): nothing drawn follows them, the pose is the same and the tree 4 to 5 µs a character cheaper |

**What a transition clip needs** (gdstudio #1156, #1157). A name in `GaitTransitionSet` is a base: the tree plays
`<base>_L` or `<base>_R` when it is in the libraries, else `<base>`. The side is the foot that steps off (a start),
the foot that lands next in the gait's phase (a reversal) or the way the body turns (a pivot, a turn on the
spot). A stop begins nearest the phase the stick is let go at: of `<base>_L`, `<base>_R` and the entries between
them named by the gait's frame they begin on (`gds/Sprint_Stop_05`), the one whose `joins.first_frame` is nearest
(`GaitTransitionSet.pick_entry`, gdstudio #1525; the jog and the sprint have one every two frames, so a body is
drawn at most a frame from it). The defaults are `gds/Idle_To_Walk`, `gds/Idle_To_Jog`, `gds/Idle_To_Sprint`, `gds/Walk_Stop`,
`gds/Jog_Stop`, `gds/Sprint_Stop`, `gds/Jog_Turn_180`, `gds/Sprint_Turn_180`, `gds/Jog_Turn_90`,
`gds/Turn_In_Place_90` and `gds/Turn_In_Place_180`. From its record in `clips.json` the tree reads `travel` (a start
or a stop is played at the time its travel has covered the ground the body really covered), `turn` (a reversal, a
pivot or a turn: the time it has turned as far as the body), and `exit_phase` (the share of the gait's cycle it ends
on), or else `end_foot` (`l`: the gait goes on from 0, `r` from half its cycle). A clip whose body has finished its
part plays on at its own pace; a body asked for something else leaves it at once. A start is picked while the body
stood at most `GaitTransitions.START_GRACE` (4) frames ago, since the controller's acceleration has it past
`standing_speed` on the tick it is asked to move (gdstudio #1416); a state asked for while a clip plays (a crouch in a
stop) is the one the machine goes on to. `tools/capture/own_blend_tour.tscn` films each start, stop and crouch from
the game camera, printing the largest move of a bone each frame. Until the clips exist nothing
plays and the states change as before.
The starts and stops are GDStudio's own since kit #1156 (`locomotion.json`; each start ends as a foot strikes,
so its `end_foot` is the phase the gait goes on from); the reversals, pivots and turns are kit #1157's.

**How a stop moves the body** (gdstudio #1415). A body on its feet with the stick let go slows by the stop deceleration
of the gait whose speed band it is in (`CharacterTuning` > Ground > Stops): `walk_stop_deceleration` 2.84 m/s² up to
`walk_speed`, `run_stop_deceleration` 4.38 up to `run_speed`, `sprint_stop_deceleration` 4.57 above. At the template's
60 ticks a second they cover each stop clip's travel: 0.48 m from the walk, 1.96 m from the jog, 4.82 m from the sprint,
in 0.60, 1.13 and 1.67 s (0.11 and 0.18 s from the jog and the sprint before). The stop clip is played by that ground
until the body is at rest (`GaitTransitions.STOP_DONE`, 0.02 m/s), counted from the tick the stick was let go, so its
planted feet hold the floor (under 3 mm in `test_gait_stops.gd`). Crouched, in the air or held by an action the body
stops by `deceleration` (36) as before. The rate is a function of the speed alone, so a predicting client and the server
stop a body at the same place (`test_net_gait_stops.gd`), and an AI's navigator lets go that far before its goal
([stopping](ai-navigator.md#navigator)). A game that changes a gait's speed or its stop clip sets the matching stop
deceleration to `(v_top² - v_bottom²) / (2 × travel)` over the band; a faster stop leaves the clip's feet sliding under
a body at rest.

**What a lean clip needs** (gdstudio #1159): its first frame is the pose leaning one way; what the tree adds is that
pose's difference from the idle's first frame, so it keys every bone the idle keys, the `ik_` targets too (where
its hands and feet are), or the difference pulls an unkeyed one back toward its rest. The template's own are
`gds/Lean_Left`, `Lean_Right`, `Lean_Fwd` and `Lean_Back` (`assets/animation/own/clips/lean.py`); each record says
its `lean` (`way`, degrees to the left of ahead, and the `degrees` the full pose leans) and its `reference`
(`Lean_Ref`, within 0.3 degrees a bone of the idle's first frame). On the player at full weight the head goes 210
to 330 mm the pose's way and the feet and targets stay within 0.1 mm (`test_own_directions.gd`).

The cost, from `tools/bench/gait_cost.tscn` (`gds template bench-web 3d-third-person gait_cost --run`, headless
Chrome on a workstation, the settings off and on in turns, players walking, blending, sprinting and stopping): 38 µs a
frame for one character, 17 µs a character with 40 (4.28 ms off, 4.97 ms on); headless desktop, 12 µs a character
with 40. The momentum blend reads 25 body bones a frame on each character and turns the ones that differ for 0.4 s
after a change; the transitions ask nothing of the body while no transition clip is in the libraries.

**The lean's cost** (gdstudio #1403). Built as one `AnimationNodeSub2` and two whole clips a way, the lean was the
dearest part of the tree: the parts bench read the tree at 1.96 to 2.03 times the body's step and the script at 1.23
to 1.25 (25 walking), and the budget case's ten walkers 1.76 to 1.92 times the calibration (1.31 to 1.46 with the
lean off). Since #1403 each axis takes its base off once (an `AnimationNodeAdd2` at minus the axis's lean, as only
one way of an axis leans at a time) and `LeanClips` keeps of each clip only the 23 of 61 tracks the poses move:
the tree 1.35 to 1.38 and the script 1.09 to 1.11, the budget case 1.48 to 1.64, the drawn bones within 0.0005 mm
of the old build (`test_gait_lean.gd`). Nothing depends on distance or sight. In headless Chrome
(`gait_cost.py` with `lean_off,on`), the lean a character a frame:

| | 10 walking | 40 walking |
| --- | ---: | ---: |
| Before | 32 to 37 µs (frame 1.82 to 1.92 ms) | 35 to 51 µs (7.9 to 8.9 ms) |
| After | 14 to 26 µs (1.74 ms) | 12 to 15 µs (6.2 to 6.7 ms) |

- **Approach:** Add every new `GaitSettings` export to `test_gait_parts.gd`'s pinned defaults in the same commit, and
  grep the tests for a state read as one clip (`get_node(state) as AnimationNodeAnimation`) when a state becomes a
  blend space. **Watch out for:** `ExportPins.differences` fails on an export the table lacks, and
  `test_player_animation_live.gd` read the air as a clip; both passed the jump's own suite and failed only in the full
  run. **Seen:** gdstudio #1371, 2026-11-14.

### Filmed online and on the local body {#gait-online}

<!-- new section: the gait settings said a puppet plays the same tree; nothing filmed or measured it, and the faults
     it found (gdstudio #1367) need a place the next clip and tree issues read -->

`tools/capture/puppet_gait_tour.tscn` (gdstudio #1367) films the starts, stops, the sprint reversal, a jog pivot and
the turns on the spot on Ada's own screen beside Bo's, where Ada is a puppet, both cameras across the lane
(`gds godot -- --path <game> --write-movie <folder>/pg.png --fixed-fps 60 --log-file <file>`, one movie frame a
physics frame; the views fill the window's top half). Each frame prints a `PUPPETGAIT` line per body: the speed, the
place, the body state, the transition clip, the largest turn of one bone since the last drawn pose (`PoseJump`,
`tools/capture/pose_jump.gd`, read in `skeleton_updated`, after every modifier) and the momentum blend's offset.
What it found on main at dc9dc2fb:

- **A puppet never plays its own clips.** `goal_speed` comes from `last_command`, which a puppet never fills, so any
  puppet above `standing_speed` starts `Walk_Stop`, finishes it within a few frames and starts it again: it glides
  frozen in the stop's last frame at every speed (gdstudio #1420).
- **The starts never play from standing.** The tree first sees the body at 0.47 m/s (one tick at 28 m/s²), past
  `standing_speed` (gdstudio #1421). Fixed by `START_GRACE` (gdstudio #1427), on her own predicted body online too
  (`test_net_starts.gd`, gdstudio #1453); a puppet's jog and sprint starts then showed the walk's, until the entry
  carried the goal speed ([puppets](online-client.md#puppets)).
- **The stops play in place.** The body halts at `deceleration` (36 m/s²: 0.53 m from a sprint, against the clip's
  4.82 m) and the clip runs on in place (gdstudio #1415).
- **The cuts land a frame after the momentum blend starts.** Into or out of a stop, the drawn pose jumps 25 to 77
  degrees in one bone on the frame after the clip changes, against 13 to 19 a frame in the steady gaits, while the
  blend's offset at the change read 0.3 to 4.5 degrees; the pistol hold switches in one frame at a sprint stop
  (gdstudio #1416).

- **Approach:** Measure a snap on the drawn skeleton: each followed bone's turn against its parent, copied in
  `skeleton_updated`, compared with the last drawn pose, beside the same number in the steady gait before. **Watch out
  for:** the momentum blend's own offset read under 5 degrees at every cut while the drawn pose jumped up to 77 the
  next frame, and a running gait alone turns a calf 15 to 20 degrees a frame at 60 frames a second, so a bare
  threshold reads every sprint as a snap. **Seen:** gdstudio #1367, 2026-11-13 (`pose_jump.gd`).
