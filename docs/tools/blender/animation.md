# Animation

<!-- new section: clip rules lived in rig-sharing.md (export) and gaits.md (locomotion); nothing gave the clip conventions
(frame rate, naming, loops, in place) or how a clip is keyed and checked -->

How GDStudio authors animation clips in Blender, by script, on a shared skeleton ([Rigging](rigging.md)), and gets them
into Godot. Locomotion clips that keep a ground speed are on [Gaits](gaits.md); cleaning and exporting a kit's clips on
[Rig sharing](rig-sharing.md); clips that hold a weapon on [Weapons](weapons.md#hands-on-the-weapon).

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

## The clip eval {#eval}

The `clip-walk` eval ([Agent evals](../../studio/agent-evals.md)) animates a walk on a given rig and measures the loop
seam, the in-place hips, the bob, the leg and arm swings and their phases, the arms' hang and the feet on the floor.
