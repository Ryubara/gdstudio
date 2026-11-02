# Rig sharing (Blender side)

How to clean a Quaternius character file in the pinned Blender (5.2.3) so its clips can go into one Godot
AnimationLibrary shared by every character. Learned in the spike `sandbox/rig-sharing/` (kit issue #10); the Godot
side is [Rig sharing (Godot)](../godot/rig-sharing.md).

## What the files hold

Measured with `sandbox/rig-sharing/blender/inspect_rig.py` on the Soldier (Toon Shooter kit, `PpLF4rt4ah`) and the
Zombie (`VlXjG0N8Eg`), both CC0 by Quaternius.

| | Soldier | Zombie |
| --- | --- | --- |
| Bones (`CharacterArmature`) | 43 | 50: the same 43 + Tongue1-5, Eyelid.L, Eyelid.R |
| Armature object scale | 100 (under a `RootNode` empty) | 100 (under a `RootNode` empty) |
| Body meshes, tris | Body 4388, Head 1352, ShoulderPad.L/.R 44 each: **5828** | Zombie 7570, Eyelid 252: **7822** |
| Held items | 14 weapons on the hand bones, 14 884 tris | none |
| Stray Icosphere | not in this file (other kit characters) | none |
| Clips | 14 | 16, **each stored twice** (`CharacterArmature\|Walk` and `Walk`) |
| Root motion | none: no `Root` location keys; `Body` bobs in place | none |
| Leaf empties | `*_end` empties at every bone tip | same |

## The recipe

`sandbox/rig-sharing/blender/clean_export.py <in.glb> <out.glb>`, run headless. In order:

1. **Import with `bone_heuristic="TEMPERANCE"`**, or the bone-attached meshes (helmet, pads, weapons) land in the
   wrong place.
2. **Delete held items and strays**: meshes parented to a hand bone, and unparented meshes. Delete the `*_end`
   empties too (they become nodes in Godot).
3. **Make the armature the root**: unparent it from `RootNode` (keep its world transform) and delete the empty.
4. **Apply the 100x scale, and scale the location keys by 100.** `transform_apply(scale=True)` rescales the rest
   pose but not the keys: the zombie's Walk bobs its `Body` 0.001 units in the file, 0.098 m after the fix.
   **Pin the bone-attached meshes**: record their world matrices at rest pose before the apply and set them back
   after, or the Soldier's helmet and shoulder pads float far above his head.
5. **One clip per name**: drop the duplicates, rename to the bare name. Remove the duplicates *before* renaming, or
   the rename collides and Blender makes `Walk.001`.
6. **Rename meshes that share a bone's name** (`Body` to `Body_Mesh`, `Head` to `Head_Mesh`). Godot keeps node
   names unique, so a mesh called `Body` turns the bone into `Body_2`, and that file's clips then target `Body_2`.
7. **Clear the pose bones but leave `pose_position` at `POSE`**, one NLA track per clip, and export glTF binary:
   `export_animation_mode="NLA_TRACKS"`, `export_force_sampling=True`, `export_leaf_bone=False`, Y up.

After it: Soldier 43 bones, 5828 tris, 14 clips; Zombie 50 bones, 7822 tris, 16 clips; both 1.0 object scale.

## What broke

- **`pose_position = "REST"` before the export freezes every clip.** The exporter samples the clips through the pose;
  with the armature in rest position every exported animation had 150 channels and none moved. Found by bisecting
  the script; leave `POSE` and zero the pose bones instead.
- **Applied scale without scaling the keys** shrinks every position key 100x (the hips barely move).
- **Applied scale moves bone-attached meshes.** The Soldier's helmet (`Head`, 1352 tris) and pads went from
  z 1.69-2.29 to 3.10-3.69 (file units); pinned at rest pose they come back exactly (checked by re-importing the
  export). Pinned in the *posed* state (the import leaves a clip active) they come back 0.06 off.
- **Mesh named like a bone** renames the bone in Godot (above).

## Avoid

- Exporting the raw file: in Godot its skeleton sits at `RootNode/CharacterArmature/Skeleton3D` with a global scale of
  100, so its track paths and position values match no cleaned character.

## Static pose and authored clips

Found building the Soldier's weapon clips (Deadnight #42).

- **Bake the static pose into every clip.** The kit clips key only the bones they move (the Soldier's `Idle` keys 7 of
  43). Every other bone sits at its glTF node transform (arms down), which is not Blender's rest pose (arms out). Read
  the pose bones right after the import, before any frame change, then key those values into each clip for every bone
  it leaves out. Before the export, set the pose bones to the static pose instead of clearing them, and export with
  `export_reset_pose_bones=False`. Deadnight: `tools/blender/soldier_clips.py` (`capture_static`, `bake_static`).
- **Bones a clip leaves out export at the rest pose.** With the pose bones cleared, unkeyed bones are sampled at
  Blender's rest, so the cleaned Soldier idles with his arms out and the zombie's Idle stands in a T-pose.
- **Quaternion keys of opposite sign swing the bone the long way.** Keep each key's sign continuous with the one
  before (negate when the dot product is negative).
- **The boots are weighted to the IK foot bones.** `Foot.L`/`Foot.R` hang from `Root` and carry location keys; key
  location as well as rotation on every bone in a derived clip.

## Posing by hand position

Found building the Soldier's grenade clips (Deadnight #102).

- **Measure the axes, do not trust notes.** On the kit spine X pitches forward, Y leans sideways and Z turns the
  chest (+ to his right); arm axes change meaning with the base pose. Probe each axis 30 degrees and print how far
  the hand bone moves: numbers settle in one run what renders leave ambiguous.
- **Solve the arm for a hand target.** Set the spine first, then search the upper and lower arm offsets for a target
  hand position (a coordinate search with a halving step, a few hundred pose evaluations, about a second) and paste the
  rounded offsets into the clip script, with the target in a comment. Deadnight's throw keys land within 6 cm.

## Bone axes in Godot, and clips that hold a weapon

Found rebuilding the Soldier's sprint carries on the solved hand grips (Deadnight #527).

- **A Godot bone's frame is the Blender pose bone's.** Measured on the cleaned Soldier (`soldier.glb`): every glTF
  node's world rotation equals the Blender pose bone's world rotation turned from Z up to Y up, with no per-bone
  correction (the exporter keeps the bone axes; positions map `(x, y, z)` to `(x, -z, y)`). So a transform the game
  keeps under a bone (a weapon's grip under the hand bone, a hand's place on a weapon) applies in Blender unchanged:
  the pose bone's world matrix (rotation orthonormal, head in metres) times the Godot transform is where the game
  draws it. Godot writes a `Transform3D` in a `.tres` as the basis row by row, then the origin.
- **The node transforms are the rest pose.** Compare frames at `pose_position = "REST"`; at the static pose the
  positions differ (arms down against arms out).
- **Build a two-handed clip as the weapon's pose, not the forearm's.** Say where the grip goes and which way the
  muzzle and the top point, then turn the right hand bone so the weapon (through the game's grip) points that way,
  reach the arm to it by two-bone IK, and reach the left hand to the grip's left-hand point and turn it to match. A
  clip that instead fixes the forearm and lets the weapon follow from where the hand happened to hold it moves the
  whole carry when the grip changes: the gun ended by the right leg with the left hand 0.2 m off it.
