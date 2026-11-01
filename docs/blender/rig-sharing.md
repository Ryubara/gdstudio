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
- **Mesh named like a bone** renames the bone in Godot (above).

## Avoid

- Exporting the raw file: in Godot its skeleton sits at `RootNode/CharacterArmature/Skeleton3D` with a global scale of
  100, so its track paths and position values match no cleaned character.
