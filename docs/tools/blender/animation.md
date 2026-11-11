# Animation

<!-- new section: clip rules lived in rig-sharing.md (export) and gaits.md (locomotion); nothing gave the clip conventions
(frame rate, naming, loops, in place) or how a clip is keyed and checked -->

How GDStudio authors animation clips in Blender, by script, on a shared skeleton ([Rigging](rigging.md)), and gets them
into Godot. Locomotion clips that keep a ground speed are on [Gaits](gaits.md); cleaning and exporting a kit's clips on
[Rig sharing](rig-sharing.md); clips that hold a weapon on [Weapons](weapons.md#hands-on-the-weapon).

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

## Clips solved from targets {#solved-clips}

<!-- new section: the page covered clips derived from a kit clip; nothing said how a clip is made from nothing on a rig
(the 3D Third Person prone and crawl clips, #1009) -->

A clip with no clip to start from is solved, frame by frame, from a few targets, by a script that keys the result
(`templates/3d-third-person/game/assets/animation/prone/build_prone_clips.py`: a prone idle, a low crawl and the two
transitions to the Universal Animation Library's crouch, on the Quaternius universal rig, one file a mannequin:
`prone.glb` for the female and `prone_male.glb` for the male, kit #1090). Godot imports the file with
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
- **Approach:** Give each body its own clip file when the clip rests limbs on the floor: the same build on that
  body's skeleton and skin with a short table of what differs, the same library name, clip names and speed. Read
  where each part's lowest vertex is before choosing what to change. **Watch out for:** the first male build with
  only the joint heights raised passed every floor number and lay on knees and elbows, the belly 5 cm off the
  floor and the head 10 cm higher than hers: his knees are 2.5 cm thicker (a straighter lying leg rests the belly)
  and his longer upper arms lift the shoulders (the collarbones draw back 16 degrees; elbows wide enough to do it
  alone put the fists 50 cm apart). **Seen:** gdstudio #1090, 2026-11-11 (`prone_male.glb`, `BODIES` in the build;
  the female's file is the same bytes).
- **Approach:** Hold the floor in a Godot test on the skin as the game plays the clip
  (`tests/fixtures/skinned_parts.gd`), and render two sheets at once into two folders. **Watch out for:** Godot's
  import drops keys within half a degree, so a planted hand is up to 3 mm lower in the game than in the build
  (1.5 mm under the floor there, 4.1 mm here); a shin counted with its foot read the toes; two renders into one
  folder lost a sheet, since the tiles share a name. **Seen:** gdstudio #1090, 2026-11-11.
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
