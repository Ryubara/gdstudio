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
| Frame rate | 24 frames a second (the kit's and Deadnight's); glTF stores seconds, so Godot plays the same speed |
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
clips), and that the body is never jerked to keep a hand in reach.

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

## The clip eval {#eval}

The `clip-walk` eval ([Agent evals](../../studio/agent-evals.md)) animates a walk on a given rig and measures the loop
seam, the in-place hips, the bob, the leg and arm swings and their phases, the arms' hang and the feet on the floor.
