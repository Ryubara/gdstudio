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

## A boss on the shared rig

Learned building Deadnight's boss zombie (Deadnight issue #98, `tools/blender/build_boss.py` there).

- **Scale and push go further than a brute:** armature scale 1.45 and 60-75 mm of push on the trunk and arms still
  share every clip unchanged (the kit Walk plays on it, checked headless).
- **Accessories go below the chin.** The kit head is 36 % of the height and hangs over the upper chest: a lamp placed
  halfway up the `Torso` bone was hidden from every camera. Halfway from `Abdomen` to `Neck`, on the belly, it reads
  from the front at every distance. Find the surface from the trunk's vertices only (weights to head, tongue and arm
  bones below 0.5), or the tongue and hands are taken for the chest.
- **A glow is a second image on the same material:** a black emission map lit only at the glowing swatch, linked to
  Emission Color with Emission Strength above 1, exports as `emissiveTexture` plus
  `KHR_materials_emissive_strength`; Godot 4.7.2 imports it with emission on (one material, one surface). Make the
  Base Color image node active again before Workbench renders, or the sheet comes out black.
- **A hitbox anchor is an empty parented to a bone.** glTF writes it as a child of the joint, and Godot imports it as
  a `BoneAttachment3D` with the node under it, following every clip.
- **Author clips that key every bone** (rotation and location) and the static-pose problems above go away.

## Modular parts

Learned building Deadnight's modular Soldier (Deadnight issue #100, `tools/blender/build_soldier_parts.py` there):
swappable parts on one skeleton, a look stored as a part id per slot plus palette indices.

- **One file, every part.** Export the armature, the clips and every part as its own skinned mesh (`<slot>__<part>`);
  the game shows one mesh per slot. Draw calls are the visible parts (5-7), one material per character.
- **Parts from the kit body.** Copy the body per part, delete the other regions' faces, move the faces onto atlas
  swatches. Tag faces by kit material, dominant bone and same-material island: islands find pouches, cuffs and
  collars, bones split sleeves (a sleeve has one long face from shoulder to elbow, so a split by face centre zigzags).
  Duplicated seam vertices keep their weights, so the parts never crack apart.
- **Colours a game can tint.** One atlas with a row of channel swatches (skin, hair, primary, secondary, accent and a
  shade of each); the game copies the image and fills those swatches per look. No shader needed, works under
  WebGL2.
- **Bone-parented meshes become skinned** (vertex group at weight 1 and an Armature modifier, at the rest pose), so
  every part exports the same way.
- **New pieces need the armature's parent inverse** (the clean-up keeps its import rotation) and a UV layer named like
  the body's.
- **The kit Soldier's eyes and brows live in its helmet mesh**: split them out before offering a look without it.
- **A band painted by face centre zigzags** (Deadnight #140): the kit's long triangles leave sawtooth edges. Cut the
  band into the mesh with `bmesh.ops.bisect_plane` on the faces it crosses (the cut interpolates the skin weights) and
  paint between the cuts.
- **A far level of detail in the same file** (Deadnight #139): a `<slot>__<part>__far` copy of each part, the Decimate
  moved first in the stack and applied (so the rest mesh is cut, weights interpolated), one ratio solved for the
  heaviest look. Keep small pieces whole (a 254-triangle cap at a third turned to slivers), and triangulate and drop
  zero-area faces before counting, or the glTF round trip disagrees with the count by a triangle.
