# Character variants from one rig

How to make many characters from one rigged model in the pinned Blender (5.2.3) so one AnimationLibrary still plays
on all of them. Learned building Deadnight's zombie variants (Deadnight issue #40, `tools/blender/build_zombies.py`
there) from the Quaternius Zombie (CC0); the clean-up before it is [rig sharing](rig-sharing.md).

## Keep the skeleton identical

| Change | How | Why it keeps the clips shared |
| --- | --- | --- |
| Height | the armature object's scale (do not apply it) | glTF keeps it as the node scale, Godot puts it on the `CharacterArmature` node; bone rests and position keys stay the source's |
| Build (broad, lean) | push vertices along their normals, times their weight to a group of bones | the mesh changes, the bones do not |
| Missing limb | delete faces whose vertices follow the limb's bones by more than half | same skeleton; the clip still turns the missing bones, harmlessly |
| Clothes | recolour faces (palette atlas): skin faces under the torso and arm bones become a shirt | no triangles, no bones |
| Accessory | a small mesh skinned 100 % to one bone, joined into the body | one mesh per character (draw calls) |

Applying a scale or moving bones gives each variant its own rest pose, and then position keys need rebasing per body
([Godot side](../godot/rig-sharing.md)).

## Measured (Quaternius Zombie, 7,822 tris)

- Collapse decimation to 51 % (4,000) and 19 % (1,500) keeps every colour of a swatch atlas in place: each face sits
  on one swatch, and no colour block moved or bled (checked on contact sheets of all seven variants).
- Recolouring by bone weight gives clean sleeve and collar lines: the mesh has edge loops at the joints.
- The Quaternius body is closed shells per limb: removing the forearm (715 faces) or the lower legs (1,243) leaves no
  open edge.
- A bone-skinned accessory joined into the body (a 10-sided cap with a one-segment chamfer) costs 76 tris.

## What broke

- **A clip with no channel for a bone exports the rest pose there.** The zombie's Idle, Yes and No have no shoulder or
  arm channels. Blender shows the pose the previous action left (so a sheet or measurement made by switching actions
  mixes two clips); the sampled export writes the rest pose (a T-pose). Fix: give each clip a held channel, from a
  donor clip's first frame (Walk), for every bone the donor turns and the clip does not.
- **One swatch can mean two things.** The zombie's bone colour is both its teeth and its belt buckle: recolour by
  swatch only where a colour means one part, by bone weight otherwise.
- **A UV layer with another name is dropped by a join.** Name the accessory's UV layer like the body's
  (`bm.loops.layers.uv.new(body.data.uv_layers.active.name)`), or the joined faces fall on texel (0, 0).
