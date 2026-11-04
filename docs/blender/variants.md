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
  Duplicated seam vertices keep their weights, so the parts never crack apart, as long as nothing moves one copy
  without the others (see the push below).
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

## A second body on the same parts

Learned building Deadnight's female Soldier (Deadnight issue #678, `tools/blender/build_soldier_parts.py` there): a
second character on the modular parts, same skeleton and clips, chosen in the look like any part.

- **The character is a part slot.** A `body` slot (`male`, `female`) appended last, with no mesh of its own: a part
  with a variant for her (`<slot>__<part>__female`, its far copy `..__female__far`) shows that variant, every other
  part is shared. The look, the save, the wire and the server need no new path; only the wire version moves.
- **One warp field for every outfit.** Her torso and legs are his, moved at rest by one smooth function of position
  (two Gaussian lobes for the chest, pushed forward only on the front; a narrower waist and slightly wider hips), so
  every top and every pair of trousers changes the same way and still meets at the waist. The arms at rest (z above
  1.34 kit metres) and the hands never move, so the grips hold.
- **Move the chest's weights to the trunk.** The kit weights the upper chest to the shoulder bones; a fuller chest
  weighted that way follows the arms. Moving 60 % of the pushed vertices' weight to `Torso` made her trunk stretch less
  than his in 52 of 55 clips.
- **Measure, then look.** `measure_soldier_body.py` (Deadnight) plays every clip, the other clip files' too, on his and
  her meshes: edge stretch on the trunk (the 99th percentile; the kit's own shoulder edges make the single worst edge
  meaningless), how deep the forearms go into the chest (the mean of the ten deepest vertices; one stray vertex by an
  open edge reads 100 mm), and how many vertices of each hair cut sit inside the collar. Then
  `render_soldier_views.py` shows the flagged clips front, side and back on a 0.5 m grid.
- **Numbers (kit metres, game is 0.8):** chest lobes at x 0.105, z 1.145, sigma 0.085 by 0.068, 90 mm forward (kept
  off z 1.28, where the sprint carries lay a forearm across the chest); waist 13 % narrower at z 1.04; hips 3 % wider
  at z 0.86 (5 % put the swinging hands into them). A bob's ends flare to r 0.40 at z 1.72 to clear the collar's top
  (r 0.36 at z 1.68). Her face pieces (lashes, a mouth, freckles or rosy cheeks) add 116-188 triangles, kept whole in
  the far heads; her heaviest look is 5,428 of 6,000, and his Projectionist worn by her is 2,000 of 2,000 far.
- **What broke:** a rebuild picked up clips shipped elsewhere
  ([lesson](../lessons/2026-11-02-a-parts-rebuild-picked-up-clips-that-ship-in-their-own-files.md)); her looks moved the
  far ratio of his parts ([lesson](../lessons/2026-11-02-a-new-variant-moved-the-far-lod-of-the-old-parts.md)); the
  short-sleeved tops had always pushed the hands off the grips
  ([lesson](../lessons/2026-11-02-short-sleeved-tops-pushed-the-hands-off-the-grips.md)); and the grip contact test
  had measured the far level of detail as well as the hand you see
  ([lesson](../lessons/2026-11-02-the-grip-test-measured-the-far-level-of-detail.md)).
- **Keep a hand's vertices where they are.** Any per-outfit push or pull (bare arms hugging the limb, cuffs pulled in)
  skips vertices whose main bone is a finger's, the way the grip test picks them; sparing only the hand's faces still
  moved its border vertices and sank the palm 3-13 mm into a grip.

## Closed, and fitting, in every combination

Learned when the maintainer saw a see-through neck, a mask-like face and arms through each other on Deadnight's modular
Soldier (Deadnight issue #895). A wardrobe is the product of its parts: check combinations, from every side, in every
pose, with back faces culled as the game draws them.

- **Find what each part relies on.** The kit Soldier has no neck: its head is a hood open underneath, closed by the
  vest's tall collar. Split into parts, the head was an open shell that only some tops closed. Give a part its own
  closure (a closed head with its own neck) instead of relying on the neighbour.
- **Render with back-face culling.** Workbench draws the inside of an open shell as if it were the outside, so every
  sheet hid the hole. Set `scene.display.shading.show_backface_culling = True` for any review render of a game mesh
  (Deadnight's `render_soldier_heads.py`).
- **Give a garment's opening an inside.** A collar is one sheet: a look down between it and the jaw saw its culled
  inside and out through it. A reversed copy of the collar's faces in a darker swatch is its lining; lining only half
  of it opened the rays again.
- **Move every copy of a vertex alike.** The kit body is split at every material and normal seam; pushing bare skin
  along each copy's own normal cracked the arms all along. Key the push by position (`round(co * 1e5)`), move every
  copy by the same offset, and taper it to nothing where the part meets another (wrist, ankle).
- **Join openings with a band, do not shrink the cover.** The cuff rings hid the sleeve's open end and the hand's open
  wrist; pulled in to look bare, they bared both. Drop the rings and bridge the two loops (sort each loop by angle
  round the limb, zip them into triangles, face them outward).
- **Recolouring keeps the shape.** The kit face is a panel set back inside a raised rim; painting the rim skin left
  its lit edges as a line from the chin up both cheeks. A face is modelled: here the head became the convex hull of
  the kit hood (so every hat still fits), a quad sphere pushed onto it, the hairline and beard cut in with
  `bisect_plane`, and a dark mouth decal.
- **Test it in the engine, in CI.** Deadnight's `BodyFit` skins the shown meshes on the CPU and casts physics rays
  against two `ConcavePolygonShape3D`s (both sides, front only): a ray whose first face is a back face with no front
  face within 6 cm behind it sees through. A sweep over every pair of parts that meet (neck, waist, wrists,
  shoulders, ankles) on both bodies runs in about 25 s. `ClipFit` samples every clip the player plays and counts limb
  and garment vertices inside another body part (six axis rays that all meet a back face first); clip faults that are
  the animation's are recorded per clip and may not get worse. Check the probe on a closed and an opened ball.
- **Physics probes in a test** need two physics steps after new shapes (one returned the last pose's surface) and
  bone poses reset before each sample (clips that do not key the fingers kept the last clip's). Step physics fast in
  the suite (`Engine.physics_ticks_per_second = 480`)
  ([lesson](../lessons/2026-11-03-a-physics-ray-probe-measured-the-last-pose.md)).
- **Orient new faces yourself.** `bmesh.ops.holes_fill` faced a neck cap down into the trunk and
  `recalc_face_normals` turned a thin mouth prism inside out (its front culled): after making faces, compare each
  normal with the way out (`normal_update()` first on a new face) and flip. A closed shell is one test, on one face
  whose way out is known: face by face from the middle turned the corners of a wide curved shape the wrong way.
- **A decal follows the surface inside its outline too.** Points on the outline alone leave a flat front that sinks
  behind a head's bulge on anything wider than about 0.1 m: cut the front where it sinks, lift the new corners onto the
  surface, keep it off a crease in the head, and smooth-shade it
  ([lesson](../lessons/2026-11-04-a-decal-flat-between-its-outline-sank-behind-the-face.md)).
- **An expression is a part, not a head.** Deadnight's mouths (#1061) left the head meshes for a slot of their own, with
  her variant of each: eight mouths on three heads of two characters are sixteen meshes, not forty-eight. A piece too
  small to decimate needs no far mesh: with no visibility range set, the one mesh shows at every distance.

## Pieces laid on a body

Learned adding Deadnight's ladder wearables (issue #1078): a bib, straps, a lanyard, buttons and braids laid over a kit
body that other parts also dress. Measure first what they all share; the numbers go on the game's page.

- **Find the surface every part shares.** Deadnight's tops are one trunk with different collars, and at the collars'
  foot the tall and the open collar coincide, so one ring round it fits every top. Lie on that surface, not on the
  thickest top: what stands proud (a vest's pouches) reads as worn over the piece, and a thicker piece takes the arms
  deeper in the clips that lay a forearm on the chest.
- **Rest a point on its footprint.** A coarse sheet or a flat strap sinks under the folds beside its points: take the
  highest of several rays under each point, and stand off a little more than the grid's chords.
- **Borrow the skin, by place.** Interpolate the weights over the nearest face (`poly_3d_calc`); pick the source faces by
  where they are, not by the bone that leads them, or the faces that move with the arms are skipped. A small rigid piece
  takes the weights at its middle, so it stays flat; a piece hanging on a strap takes one bone with the strap's lower end.
- **Look along the ray.** A ray or nearest-face search from outside finds whatever overhangs (a collar's flare above a
  shoulder), which then seats and skins the piece on the wrong part.
- **Her variant is a shear for a flat piece.** The body's warp moved vertex by vertex bends a card; moved whole it leaves
  its clip. Shear it: as far as the warp moves its top at the top, as far as its most forward point at the bottom.
- **A one-piece hides a slot** the way a hat hides hair: a flag in the catalog, read where the visible parts are listed,
  and a sweep of the joins it now owns (its ankles against every shoe), which the other part's sweep no longer sees.
- **Cut colour lines in; never paint them by face.** A sock's line painted by face centre was a row of teeth.
- **New looks must not recut old meshes.** A far ratio solved over every new look moved every far mesh; solve over the
  fixed set, assert the new looks against the budget. Keep a small piece under the keep-whole limit, or the far level
  cuts it to slivers.

## Clips that keep the arms out

Learned reworking Deadnight's Soldier clips that put the forearms and hands through the body (Deadnight issue #939,
`tools/blender/soldier_clips.py` and `tools/blender/arm_clearance.py` there). A clip authored by where a bone ends (a
hand on a grip, on a chest, on the ground) says nothing about what the forearm and the big kit hand pass through.

- **Measure while authoring.** `arm_clearance.py` runs the game's inside test on the kit body in Blender: every other
  part the arm must stay out of as one surface (the trunk, the head, the legs, the other forearm and hand), six axis
  rays from each forearm and hand vertex, inside when all six first meet a face turned away, at every key frame and
  eight samples. The build prints one `ARMS` line per clip; a pose search runs in one Blender session (about 1 s a
  pose). The game's sampler on the dressed parts stays the judge: the kit body has no trousers or jacket, so leave a
  margin and confirm in Godot.
- **Test the union, as the game does.** Each part's surface is open where its skin meets the next part's, so a hand in
  a fold (the lap, an armpit) sees a back face of one part or another down every axis while no part alone holds it
  deeper than 2 cm. A part-by-part proxy called it clear; the game's test counted 83 mm.
- **Author from what the game draws.** Where an IK holds the arms in one state, the clips of the states around it
  (equip, the quick melee) start and end on the IK's pose: Deadnight reads its dual pistols' hold in Godot (each hand
  at x ∓0.62, y -0.42, z 1.23 kit metres, the elbows out and down) and solves the clip's arms to it. A one-handed pose
  mirrored to the other arm puts both hands on the body's middle line.
- **What worked (kit metres):** a chest that pitches forward (19 degrees in a blow) lifts the free hand with it (the
  upper arm raised 20 degrees and swung 12 forward at the end of the blow) or it hangs into the knee; an arm raised over
  the head swings out 25 degrees, or the forearm goes through the side of the head; two hands on one target stay 0.52
  apart (0.18 apart, the hands crossed); a hand cannot rest on the belly of a body sitting up with its knees drawn in
  (18 places, 49-102 mm), so it rests over the knee; a carried rifle's grip sits 0.14 further ahead and 0.09 to his
  right, or the arm reaching across lies in the jacket (0.09 ahead alone pushed the upper arm's armband in).
- **Sample the key poses.** Four frames at each quarter's middle missed a windup at 0.25 s (83 mm into the head):
  Deadnight samples eight, and the Blender check adds every key frame.
- **The sampler loads what the game loads.** A clip in its own file is sampled only if the sampler adds that file:
  a test that finds it only because another suite put it in the shared library passes alone and fails in a run, or
  the reverse. Add every new clip file to the sampler in the same change (Deadnight `ClipFit.add_player_clips`).
- **A prop held to the face:** the hand sits along the prop from the point at the mouth, so a bottle tipped up past
  level from far round to the side puts the fist over the face. Deadnight's drink: 45 degrees round, at most 126 from
  upright, the elbow pole a little back; 58 and 135 put the fist 60 mm into the head.
- **A reach to a point beside the body (Deadnight's reload, #987):** split the check by target first (body, other arm),
  or one number hides two faults. Move the goal out of an ellipse round the hips rather than trust a straight line
  between two points; blend the two-bone pole to out and back as the arm hangs, since a pole along the arm says
  nothing and flips; hang the hand in line with the forearm. Chibi fists are 0.25 kit wide: the left hand takes the far
  end of a magazine or drum (the SMG's drum: 0.2 ahead of the grip and 0.22 below it, the model's units), never its
  middle beside the right fist.
- **Watch the blends too.** A full-body layer eased in (down, the crawl) passes through poses no clip has; measure the
  pose the game draws through the blend (Deadnight `tests/captures/clip_arms_tour.tscn -- --measure`).

## Proportions: measure the arm

Learned when the maintainer saw the female Soldier's arms as too long (Deadnight issue #978,
`tools/blender/soldier_arms.py` and `tools/blender/measure_arms.py` there). A kit body reused as a base carries its
limb lengths into every character made from it, and a second body made by warping only the trunk inherits the first
one's arms.

- **Measure the arm against the height before a body ships:** upper arm (shoulder joint to elbow joint), forearm (to
  the wrist), hand (wrist to the furthest fingertip of the skin), the sum over the height (sole to the top of the head,
  hair and hats left out), and where the fingertips hang standing. The Quaternius Soldier, Hazmat and Enemy share one
  arm: upper arm 0.388, forearm 0.440, hand 0.384 m, 0.53-0.57 of their heights, the forearm longer than the upper
  arm, the fingertips below the knee. Deadnight's is now 0.507: the forearm at 0.80 of the kit's (0.91 of the upper
  arm), the fingertips at the knee.
- **Change the rest on the imported kit body, before any clip is authored.** Move each wrist along the forearm toward
  the elbow with the hand's bones (head and tail, roll kept) and every vertex by its weights (a finger bone's share
  moves with the wrist, the forearm's in proportion to its distance from the elbow), in armature space. Clips that key
  only rotations on the arm (no Soldier clip keys an arm bone's position) play on the shorter arm unchanged; clips
  solved by reach are solved again on it by the same build. Keep the hand if grips are solved on it.
- **Places along the arm in the build's rules** (a cuff picked by `|x|`, a wrist seam) are written in the kit's numbers
  and read through one map of the change, or they miss it
  ([lesson](../lessons/2026-11-04-places-along-the-arm-in-kit-numbers-missed-the-shorter-arm.md)).
- **A shorter arm reaches less.** Before building, shorten the skeleton's rest at run time in a probe and read the
  IK's reach for every hold and view pitch: Deadnight's long guns needed 10 degrees more stance at the low ready (which
  turned the armband deeper into the chest) or a slide of the gun back along its barrel, which it now does, with the
  two-handed elbows bent further out so the shorter right forearm stays out of the jacket.
