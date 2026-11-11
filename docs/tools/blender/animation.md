# Animation

<!-- new section: clip rules lived in rig-sharing.md (export) and gaits.md (locomotion); nothing gave the clip conventions
(frame rate, naming, loops, in place) or how a clip is keyed and checked -->

How GDStudio authors animation clips in Blender, by script, on a shared skeleton ([Rigging](rigging.md)), and gets them
into Godot. Locomotion clips that keep a ground speed are on [Gaits](gaits.md); cleaning and exporting a kit's clips on
[Rig sharing](rig-sharing.md); clips that hold a weapon on [Weapons](weapons.md#hands-on-the-weapon); clips with a
hand or a foot planted on an obstacle under [A clip that touches the world](#contacts).

## The conventions {#conventions}

| Rule | Value |
| --- | --- |
| Frame rate | 24 frames a second (the kit's and Deadnight's); glTF stores seconds, so Godot plays the same speed. A clip made to join a pack's library keeps the library's rate (the Universal Animation Library's 30) |
| Root motion | none: clips are in place and the game moves the body |
| Names | bare for whole-body states (`Idle`, `Walk`, `Run`), `<Action>_<Class>` for a held class (`Aim_Rifle`, `Reload_Pistol`), `<State>_<Variant>` for a variant (`Downed_Crawl`); a kit clip keeps its name (`HitReact`, `Death`) |
| Loops and events | not in glTF: a `clips.json` beside the model gives each clip's loop flag and event frames, and Godot adds the method tracks |
| A new gait | keeps the length of the gait it blends with (the zombie's Run is 16 frames, the Soldier's 17) |

Deadnight's naming and file rules are in its `docs/design/animation.md`. Godot's glTF import leaves every clip at
`loop_mode` none, so the loop flag is set on the Godot side ([Crowds](../../engines/godot/crowds.md)).

## Keyframes {#keyframes}

Author a clip from an existing pose of the rig (the kit's `Idle_Shoot` frame 0 for a hold), never from the bare rest
pose, and key every bone the clip touches on its first and last frame. A looping clip's last frame is its first again:
every bone's rotation and location equal on both, so the loop does not pop. Keep quaternion keys' signs continuous
from key to key, or the interpolation spins the long way round, and key location as well as rotation on IK-driven foot
bones ([Rig sharing](rig-sharing.md)).

A bone a clip leaves unkeyed takes the rest pose in Godot, or the pose of the clip played before: bake the static pose
into clips that key few bones (the kit's Idle keys 7 of 43), or key every bone ([Rig sharing](rig-sharing.md)).

A walk or run is measured, not judged by eye: the hips bob twice a cycle, the thighs swing in opposite phase, the arms
swing against the legs (left arm with right leg), and a foot is on the floor in every frame, with nothing under it.
Planted-foot speed gives a gait's ground speed ([Gaits](gaits.md)).

- **Approach:** For each limb, compute its forward swing from the joint positions (the thigh from hip to knee, the
  upper arm from shoulder to elbow) and check the phases against each other after the build: legs opposite, each arm
  with the other side's leg. **Watch out for:** a rotation about X has opposite senses for the swing you mean on a
  limb hanging down and one reached forward, so an arm keyed with the same sign as its own side's leg swung in step
  with it, which looks wrong at once in play and passes a check of amplitude alone. **Seen:** gdstudio #774, 2026-11-07
  (fix: the reference walk's arm signs were flipped; the `clip-walk` eval checks the correlation, not just the size).
- **Approach:** Before a keyed clip is shown to anyone, measure on every frame, on every model's skinned mesh, how
  deep each body part is inside another (leg in leg, arm in leg, limb in torso), and make the build fail over a few
  millimetres: the template's `assets/animation/limb_overlap.py` does it for the universal rig (5 mm on the vault
  clips; the library's 43 clips never cross the legs). **Watch out for:** feet and hands keyed as world positions
  put a shin through the other thigh on frames where every contact check passes, and a sheet of small tiles hides
  it. **Seen:** gdstudio #1016, 2026-11-10 (the maintainer found the vault clips' legs passing through each other, 75
  mm deep; fix: the check in `build_vault.py` and `tests/assets/test_vault_clips.gd`, the legs keyed again).

## Actions, slots and the NLA {#actions}

In Blender 5 an action plays on an object only through a slot (`animation_data.action_slot = action.slots[0]`), and
glTF roots import in quaternion rotation mode ([Modular kits](modular-kits.md)). Mute NLA tracks before posing by hand
or reading bones, or the tracks override the pose ([Gaits](gaits.md)).

- **Approach:** In Blender 5, set `bpy.context.preferences.edit.keyframe_new_interpolation_type` (and the handle type)
  before a script keys a clip, rather than editing the curves afterwards. **Watch out for:** a layered action has no
  `action.fcurves`; its curves sit in its layers, strips and channel bags, so a script written for Blender 4 that walks
  `action.fcurves` to change interpolation fails. **Seen:** gdstudio #774, 2026-11-07 (the `clip-walk` baseline run).

## Export {#export}

Export each clip as its own NLA track (`export_animation_mode="NLA_TRACKS"`) with `export_force_sampling=True`, and
leave the armature's `pose_position` at POSE: REST froze every clip ([Rig sharing](rig-sharing.md#what-broke)). Give
every build that exports clips a frozen list of them and assert it: a build that exports every action picks up clips
added since ([Build scripts](build-scripts.md#rebuilding)). The exporter writes every bone of every clip; strip the
channels a clip should not drive from the glb's JSON ([Rig sharing](rig-sharing.md#what-broke)).

Check a clip in Godot, not only in Blender: a headless script that plays each clip and asserts bone motion, plus a
capture ([Godot rig sharing](../../engines/godot/rig-sharing.md)).

## A clip that touches the world {#contacts}

<!-- new section: the page had loops and gaits; nothing said how a clip with a planted hand or foot on an obstacle is
keyed, checked and handed to the code that warps it (the vault clips, kit #1010) -->

A vault, a climb or a push puts a hand or a foot on something that stands still while the body moves. Key such a clip
in the **world of a reference obstacle**, not in place: the controls (the pelvis, each wrist and ankle, where each
elbow and knee points) get world positions, a planted hand is two keys at one place, and the body's root moves forward
at a constant speed that is taken out again on the way to the bones, so the exported clip is in place like every
other. A constant speed keeps a smooth curve the same in both spaces. Write the obstacle's size, the speed, where the
root starts and each contact's time into a file beside the clip: the code that warps the clip to another obstacle
reads them (the template's `assets/animation/vault/build_vault.py` and `vault_clips.json`).

The build checks, on every frame and on the skinned mesh, before it exports: the lowest vertex against the floor, the
deepest vertex inside the obstacle (12 mm allowed, as wide as a wall so the legs must clear the top), the planted
palm's gap to the surface, how far each planted wrist or ankle moves in the world while planted (0.5 mm on the vault
clips), that the body is never jerked to keep a hand in reach, and that no limb is inside another on either mannequin
([Keyframes](#keyframes); 5 mm allowed). It also checks what the body does between its contacts: its centre of mass
on the arc of a free fall while nothing touches it, the planted arm giving and then straight, the landing leg reaching,
an arm that has let go staying under its shoulder's height and gaining speed without a snap
([the vault clips](../../engines/godot/third-person/clips.md#vault-clips)).

- **Approach:** Where a body leaves the ground, key the pelvis from the centre of mass, not by eye: write its
  height for every frame (free fall between contacts, a curve with a height and speed at each end while a limb
  carries it), measure in each pose how far it is above the pelvis (segment masses on the bones), key the pelvis
  that much lower and repeat until it settles (`Clip.drive` and `Clip.settle`: three or four passes, under 0.2 mm).
  **Watch out for:** a pelvis on a smooth curve is not a body on an arc: legs that reach down and arms that swing
  move the pelvis the other way. **Seen:** gdstudio #1016, 2026-11-11 (both vaults within 0.3 mm of the arc; the
  build fails over 15 mm).
- **Approach:** Key an arm that has let go from **its own shoulder in the world's axes** (`Clip.shoulder` in
  `build_vault.py`), let the hand go while the elbow is still bent, and let it gain speed evenly from rest over four
  or five frames until it travels with the body. Fail the build on the wrist's height over its shoulder, its speed in
  the world and against the shoulder, and its change of speed in one frame. **Watch out for:** keyed in the hips' axes
  with the body rolled 56 degrees, the wrist went 0.30 m over the shoulder, above the head, at 11 m/s within two
  frames; a hand held until the arm is at full stretch is torn off by the shoulder; a hand that only rides with the
  body already moves at 3.6 m/s in the world. **Seen:** gdstudio #1016, 2026-11-11, a maintainer correction (fix:
  `Vault_High`'s right hand lets go a frame earlier; `FREE_*` in the build).
- **Approach:** Key the limbs that are in the air in the **hips' own axes** (a point from the pelvis bone, turned
  with the pelvis's keys: `hips()` in `build_vault.py`), the left foot with `left` above 0 and the right below it,
  and keep world positions for what touches the world. Take the leg paths from footage of the real move: over a
  speed vault the body lies near level and the legs go over stacked, one above the other with a gap, knees bent.
  **Watch out for:** with the body rolled 50 degrees, world keys that looked apart put the lower leg's foot above
  the upper leg's, so the legs crossed for eight frames; rolling further to lift the legs drops the lower hip onto
  the obstacle instead. **Seen:** gdstudio #1016, 2026-11-10 (fix: both vaults' legs and free arm keyed in the hips'
  axes; the overlap check reads 0.5 mm at most).
- **Approach:** Tell inside from outside on a part cut from a skinned mesh by closing its cut rims (a fan to each
  rim's middle) and casting rays; measure depth to the skin, and put the lowest spine bone with the pelvis.
  **Watch out for:** a nearest-surface test on the open part read a head beside a raised upper arm as 100 mm inside
  it (a point beyond a limb's open end lies behind its rim), and the female mannequin's hips are skinned to
  `spine_01`, which read the rest pose as 87 mm of chest in thigh. **Seen:** gdstudio #1016, 2026-11-10 (fix:
  `limb_overlap.py` closes the rims; its `--self-test` reads 0 on the rest pose and a crossing on swung legs).

- **Approach:** Let a planted hand pull the pelvis toward itself when the arm cannot reach, smooth that pull over a
  few frames, and keep the planted arm a little bent (0.94 of its length) so the arm takes up what the smoothing
  leaves. **Watch out for:** a pull applied only on the frames that needed it moved the body 30 to 45 mm for single
  frames (a jerk at 24 frames a second), and an arm allowed to its full length was straight, bent 43 degrees and
  straight again on three frames. **Seen:** gdstudio #1010, 2026-11-10 (fix: the smoothed pull and the jerk check in
  `build_vault.py`).
- **Approach:** Check that a planted bone stays in place, not only that it is at the right height. **Watch out
  for:** the first build measured the palm's gap to the top and the skin inside the box, both of which a hand sliding
  along the top passes. **Seen:** gdstudio #1010, 2026-11-10 (fix: the drift check on every planted wrist and ankle).
- **Approach:** Open a hand from the rest pose with the thumb lifted into the palm's plane, and measure the wrist's
  height over a surface on the skinned mesh. **Watch out for:** the universal rig's thumb rests pointing 28 degrees
  down, so a flat palm with rest-pose fingers put the thumb 72 mm into the box; the wrist bone rides 36 mm over a
  surface the female mannequin's palm lies on. **Seen:** gdstudio #1010, 2026-11-10.
- **Approach:** Solve a limb about its own hinge: the upper bone's direction to the elbow and the bend plane's normal
  give its whole rotation, with the hinge axis read from the rest pose (on the universal rig: down for the left
  elbow, up for the right, the body's left for both knees, as `upper x lower`). **Watch out for:** a swing from a base
  pose leaves the twist of that pose in the upper arm, and the elbow then bends about the wrong axis.
  **Seen:** gdstudio #1010, 2026-11-10 (`build_vault.py`, `LIMBS`).
- **Approach:** Take the first and last poses from the loop the clip joins, and key that loop's poses two frames
  outside the clip as well, so the curves leave and arrive at the loop's own speed. Read a library clip onto the rig
  as each bone's rotation relative to its parent on this rig's own bone lengths: that is what Godot plays on a
  mannequin with other proportions. **Watch out for:** the pack's clips sit on the male armature, whose upper arm is
  5 cm longer than the female's, so a pose copied as bone matrices stretches the other model's arms. **Seen:**
  gdstudio #1010, 2026-11-10 (the vaults start on the sprint's left foot strike and end on its right one; the joins
  measure under 20 mm in Godot).

## Clips solved from targets {#solved-clips}

<!-- new section: the page covered clips derived from a kit clip; nothing said how a clip is made from nothing on a rig
(the 3D Third Person prone and crawl clips, #1009) -->

A clip with no clip to start from is solved, frame by frame, from a few targets, by a script that keys the result
(`templates/3d-third-person/game/assets/animation/prone/build_prone_clips.py`: a prone idle, a low crawl and the two
transitions to the Universal Animation Library's crouch, on the Quaternius universal rig). Godot imports the file with
`importer="animation_library"` beside the libraries
([the libraries](../../engines/godot/third-person/character.md#animation-libraries)).

- **Give each bone a world turn from its rest, not angles on its own axes.** A glTF rig's bone axes are arbitrary, so
  a limb is aimed by mapping two rest directions (along the bone, and the joint's hinge) to where they should point;
  the trunk is a pitch, yaw and roll from the standing rest. The script keeps the rest matrices and the skin as arrays
  and skins the mesh itself (it must agree with Blender's evaluated mesh to a micrometre: check it on a frame of each
  clip), so every frame can be measured without a frame change.
- **Plant what carries weight, in the character's space.** A clip in place moves each planted point back at one speed
  for its share of the cycle and returns it leaving and landing at that speed; the speed is stride over planted time
  and is the number the game needs. A forearm on the floor is planted at the elbow and the hand; a pushing leg at the
  foot, never the knee, which rolls as the leg straightens (7 cm in the crawl). A forearm planted whole cannot turn
  while it is planted, so its angle to the body is chosen once, for the whole pull, from how people place it (the
  crawl's research is in the clips' README: `templates/3d-third-person/game/assets/animation/prone/README.md`).
- **Let the body give where a target leaves no freedom.** An elbow on the floor is exactly one upper arm from the
  shoulder, so the shoulder's height follows from where the elbow is: the crawl's spine pitches and rolls each frame
  by the amount (two unknowns, two elbows, Newton's method) that puts both shoulders at that distance, and the chest
  rides over the planted elbows by itself. The belly rests on the floor the same way: the pelvis's height is moved
  until the lowest vertex of the belly and thighs sinks a few millimetres.
- **Join another clip on its exact pose.** A transition reads the pose it joins (frame 0 of the library's crouch idle:
  joint places, trunk turns, the feet's world turns), keys its targets from those values, and mixes the solved limbs
  with that pose's own in local space over the first frames, so frame 0 is the pose to the bit while the planted foot
  stays put.
- **Export the armature with a one-triangle mesh skinned to the root.** Godot makes a `Skeleton3D` from a skin, and
  the track paths (`Armature/Skeleton3D:<bone>`) come from it; without a skinned mesh the bones import as plain nodes.
  The stand-in keeps the mannequin's mesh out of the file (0.66 MB for four clips).
- **The build's checks** are the clip's own: loops close, planted joints stay within a millimetre at the clip's speed,
  the lowest vertex by body part, a transition's first and last pose against the poses it joins, and the frozen clip
  list. A rebuild writes the same bytes, so `cmp` proves a script change did not move a clip.

- **Approach:** After the first build, read the lowest vertex of each body part (hand, forearm, foot, toes, knee,
  shoulder) on every frame, and render the pose large from the side, the top and a quarter view before tuning any
  number. **Watch out for:** a cross product in the wrong order pointed the kneecap up, so the lying feet were upside
  down and 3.5 cm under the floor; the rest thumb points 47 degrees under the palm and curled fingers reach 6 cm under
  a hand laid flat; a foot on its toes needs the toe bone bent at the floor; a knee bent under a low pelvis goes
  through the floor unless it points out to the side. One number for the whole mesh said only that something was
  under. **Seen:** gdstudio #1009, 2026-11-10 (fix: the per-part report, the thumb laid out, the toes bent at the
  floor, bent knees sent sideways).
- **Approach:** Set the scene's frame rate to the clip's before importing a glb of clips, in the build and in every
  script that renders it. **Watch out for:** Blender imports keys at seconds times the scene's rate, so a 30 frames a
  second library read into a new scene (24) had its 46-frame clip on frames 0 to 37 and every sampled frame fell
  between two keys. **Seen:** gdstudio #1009, 2026-11-10 (fix: `scene.render.fps = 30` before the import).
- **Approach:** Test a clip file of your own in Godot on both mannequins: every track finds its bone, a loop's last
  pose is its first, a transition's first and last pose equal the poses it joins (bone by bone, in the model's space),
  and a planted joint stays put while the model moves at the clip's speed. **Watch out for:** the importer keeps 57 of
  the file's 195 channels (it drops the scale tracks and the positions that never move), an `Array[StringName]` sorts
  by something other than the alphabet (compare `String`s), and a clip solved on the female mannequin rolls a planted
  elbow up to 3 cm on the male, whose upper arms are 5 cm longer, so the limits are per model. **Seen:** gdstudio
  #1009, 2026-11-10 (`tests/gameplay/test_prone_clips.gd`).
- **Approach:** Before keying a gait or a move the library has no clip of, research how real limbs do it, not only
  its speed: a manual or coaching text, a motion study and a dozen photographs. Write down, with sources, each
  limb's angle to the body, where hands and feet land, which limbs move together and each joint's path; build to
  those numbers and test them in Godot. **Watch out for:** the first crawl was researched for its speed and limb
  pairing only, so both forearms pointed almost straight ahead, shoulder-width apart, where every photograph of a
  crawling soldier has the forearms 45 to 80 degrees inward and the hands under the chin; every check passed and
  the pose was still wrong. **Seen:** gdstudio #1020, 2026-11-10, a maintainer correction (fix: the research table
  in the clips' README, forearms 40 degrees inward, a hand planting 0.29 m ahead of the other, and a Godot test).
- **Approach:** Rest a limb that carries weight for long the way a person can keep it up: a forearm lies rolled about
  45 degrees onto its outer edge (the palm down and in), the hand a fist in line with it, the thumb outside. Palm
  down is the end of the forearm's twist and bends the wrist back. Set the joint heights from the forearm's and
  the fist's lowest vertex and look at every finger in close-ups. **Watch out for:** the reworked crawl still lay on
  flat palms; a fist holds the wrist 6.6 cm up (a flat hand 4.5) and is 8 cm tall palm down, so a hand closing in a
  transition lifts first (37 mm under otherwise); lower elbows sink the chest until the collarbones push down 11
  degrees; one fist plays on both mannequins, so its curls sit between their hands. **Seen:** gdstudio #1020,
  2026-11-11, a maintainer correction (fix: `FOREARM_ROLL`, `FIST_CURL`, `fist_numbers`, a Godot test).
- **Approach:** Measure every model that plays a clip on its own skinned mesh, part by part against the floor, in
  the build; read a pose helper's effect off the bone it should move; tell inside from outside with rays, not only
  the nearest face's normal. **Watch out for:** the clips were held on the male by bone heights only, so nobody saw
  his forearms 4.6 cm and his thighs 3 cm under the floor (one clip file cannot rest both bodies); the finger curl
  never ran (`n[:-4]` of `index_01_l` is `index_`); a nearest-normal test called a finger 90 mm inside the thumb's
  open base. **Seen:** gdstudio #1020, 2026-11-11 (fix: `floor_mm` and `fist_mm` in the build's report; the male's
  own clip set is a follow-up).
- **Approach:** Run the limb overlap check on both mannequins inside the build, and when a transition crosses, move
  the keys of the limb that can leave first in time before changing its path. **Watch out for:** the transitions
  passed their own checks with the chest 25 to 50 mm in the front thigh going down and the left arm 51 mm in the
  thigh coming up; opening the knee to clear the chest put it into the male's longer arm (35 mm), and a pole
  target is only a hint; wider elbows in the crawl sank the chest 2.2 cm into the floor. **Seen:** gdstudio #1020,
  2026-11-10 (fix: the hands go up and over the knee by frame 3 and the knee opens from frame 2 to 6; coming up
  the left hand waits outside the knee until frame 19; at most 2.6 mm on both mannequins, the build fails over 5).
- **Approach:** When one clip's target moves, rebuild and read every clip that joins it. **Watch out for:** moving
  the prone idle's hands 2.5 cm forward put the going-down clip's hands 8 mm out of reach on the frame they land,
  since the transition takes its hand places from the idle. **Seen:** gdstudio #1009, 2026-11-10 (the build's miss
  check caught it; the dive was moved forward).

## The clip eval {#eval}

The `clip-walk` eval ([Agent evals](../../studio/agent-evals.md)) animates a walk on a given rig and measures the loop
seam, the in-place hips, the bob, the leg and arm swings and their phases, the arms' hang and the feet on the floor.
