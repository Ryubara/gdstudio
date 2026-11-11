# Realistic characters

<!-- new section: every Blender page is about flat-palette low-poly work; nothing held how a realistic game
character is made, what Blender and Godot can show of one, or what a first attempt reached (gdstudio #1151) -->

What GDStudio learned from its first realistic character: an experiment (gdstudio #1151) in how far a script-built
action-survival heroine gets in the pinned Blender alone, measured against current third-person games. The build
lives in `sandbox/realistic-character/` (eight Blender stages, a render script and a Godot test project); the asset
itself is not in the repository. Read [Where it fell short](#gaps) before planning any realistic asset: the
experiment is a working pipeline and a long way from the references.

**Belongs here:** how the parts of a realistic character are made and budgeted, and what the build taught.
**Not here:** the low-poly rules ([Modelling](modelling.md)), the rig's contract (the prototype mannequin rig page of
kit #1149, once landed).

## How games make one {#pipeline}

<!-- new section: the order of work for a realistic character differs from the low-poly one: a sculpt comes first
and the game mesh is derived from it -->

A realistic character is two models. The **high-poly** one (tens of millions of polygons, sculpted, or a scan cleaned
by sculpting) carries the forms and the fine detail. The **game mesh** (60,000 to 150,000 triangles for a hero seen
close) is retopologised over it with loops where the face and joints bend, and the difference between the two is
**baked** into tangent-space normal maps, with ambient occlusion and other maps from the same bake
([Polycount: texture baking](http://wiki.polycount.com/wiki/Texture_Baking),
[normal map details](http://wiki.polycount.com/wiki/Normal_Map_Technical_Details)). Skin, eyes, hair, cloth and hard
gear are then separate problems, each with its own mesh layout, maps and shader. Studios scan heads and fabrics, drape
clothes in a cloth simulator and paint in dedicated tools; this experiment asked what remains when only Blender and a
script are allowed.

| Part | How games do it | What the experiment did |
| --- | --- | --- |
| Body and face | scan or sculpt, retopologise, bake | Blender Studio's CC0 base sculpt (multires), its cage reshaped by rule |
| Skin | scanned albedo and displacement, hand-painted zones, a subsurface shader | zones painted on vertices by rule, 3D procedural detail, baked to maps |
| Eyes | sclera and iris, a refracting cornea shell, an occlusion shell, a tear line | the same four meshes, an iris texture drawn with numpy |
| Hair | a groom of strands, rendered to a card atlas, cards placed by hand in layers | an atlas drawn with numpy, cards laid along a flow field |
| Clothes | drafted and draped in a cloth simulator, retopologised, baked | shells cut from the body's faces, folds as noise ridges |
| Gear | hard-surface high-poly, low-poly, bake | bevelled boxes and straps lofted around the body |

## The base and the sculpt {#sculpt}

<!-- new section: the first decision of the build, and the one that set its ceiling -->

Start from anatomy that is already right. The build takes the realistic female body of Blender Studio's
[Human Base Meshes](https://www.blender.org/download/demo-files/) bundle (v1.4.1, CC0, by Blender Studio and
community contributors): a 10,590-face cage with a three-level Multires sculpt, eyes, a mouth bag and UVs on 24 UDIM
tiles. It is a third-party base: committing anything derived from it needs a licence entry and the maintainer's
decision, like any other.

A headless script cannot sculpt with brushes. It can move the cage: `s01_sculpt.py` adds Gaussian pushes of 0.5 to
2.5 mm at face landmarks (jaw, chin, cheekbones, nose, lips, brows, lids, ears), a few millimetres of muscle, a small
asymmetry and a height scale (1.64 m to 1.69 m). The Multires levels follow the cage, so the sculpt survives. This
makes a different face, not a designed one: it is the weakest part of the result.

- **Approach:** Measure a base mesh's landmarks from an orthographic render of known scale (or from vertex
  queries) before writing any number that depends on them, and print them in the build. **Watch out for:** landmark
  heights guessed from proportion (shoulder top, neck base) were 4 cm too high, so the first tank top was a crew neck
  and the sling strap started above the shoulder. **Seen:** gdstudio #1151, 2026-11-11 (fix: the neckline and armhole
  numbers were re-read from a 0.9 mm per pixel front view).
- **Approach:** Give every helper copy of a mesh that shares space with the real one `hide_render = True` when it is
  made. **Watch out for:** the unskinned whole-body copy kept for cutting clothes sat exactly on the textured skin
  and rendered over it, so the first skin test came out white and looked like a material fault. **Seen:** gdstudio
  #1151, 2026-11-11.

## UVs and the bake {#baking}

<!-- new section: GDStudio's first texture bake; materials.md#baking asked for its numbers to be written down -->

The skin the clothes hide is deleted from the cage first (the trunk under the top, the legs, the feet): 53,544
triangles of skin remain, and the UV space goes to what is seen. The cage's UVs are packed into two sets, head and
body, and three things come from it: the game mesh (Multires level 1 applied), the surface the textures are painted
on (level 3 applied, 856,704 triangles) and the cage itself for the normal bake.

- **Normals of the sculpt:** Blender's bake from Multires (`scene.render.bake.use_multires`, type `NORMALS`,
  `bpy.ops.object.bake_image()`), viewport level 1 against render level 3. It needs no cage and no ray distance, and
  takes about a second for two 4K maps (Blender manual: Render, Cycles, Baking).
- **Painted detail:** pores, creases, lip lines and scars are bump nodes on the level-3 surface, baked with Cycles
  (`bake(type="NORMAL")`) in the surface's own UVs. The two normal maps are combined with reoriented normal mapping
  ([Blending in Detail](https://blog.selfshadow.com/publications/blending-in-detail/)).
- **Colour, roughness, masks:** emission bakes of the same node tree, eight samples each.
- **Ambient occlusion:** a Cycles `AO` bake, 48 samples.

The whole skin stage (seven bakes of two 4K sets) runs in under two minutes on an RTX 5080; at a quarter size, 18
seconds. Texel density: about 84 pixels per centimetre on the head at 4K.

- **Approach:** Pack each UV set with only its faces selected (`mesh.select_all(DESELECT)`,
  `object.material_slot_select()`, then `uv.average_islands_scale()` and `uv.pack_islands()`), leave islands on the
  UDIM tiles they came on until after the pack, and assert each set's UV bounds afterwards. **Watch out for:** with
  UV sync selection on, `uv.select_all` selects every face of the mesh, so both sets packed into one square; and
  mirrored halves stored exactly two tiles apart, once shifted into 0..1, share their seam's UVs and are packed as
  one folded island. **Seen:** gdstudio #1151, 2026-11-11 (fix: no `uv.select_all`; the tiles are brought home after
  the pack; the build asserts 0..1).
- **Approach:** Bake normal maps to 16 bits, or dither them, when a surface is smooth and carries a sharp second
  highlight. **Watch out for:** 8-bit normal maps under Godot's clearcoat showed contour bands across the shoulder
  and arm; the same maps under Cycles' softer coat hid them. **Seen:** gdstudio #1151, 2026-11-11 (not fixed: the
  first item of the gap list).

## Skin {#skin}

<!-- new section: skin is the first GDStudio material that is not a flat palette colour -->

Skin is translucent: light enters, scatters and leaves a few millimetres away, redder than it went in. Games fake it
in screen space ([separable subsurface scattering](https://www.iryoku.com/separable-sss/), after
[GPU Gems 3, chapter 14](https://developer.nvidia.com/gpugems/gpugems3/part-iii-rendering/chapter-14-advanced-techniques-realistic-real-time-skin))
or with profiles fitted to path tracing
([Christensen and Burley](https://graphics.pixar.com/library/ApproxBSSRDF/)), add a second specular lobe for the oil
on the surface, and break roughness up at pore scale
([Next-generation character rendering](https://www.iryoku.com/stare-into-the-future);
[Unreal's digital humans](https://dev.epicgames.com/documentation/en-us/unreal-engine/digital-humans-in-unreal-engine)).

The build paints by rule (`s02_skin.py`):

- **Zones** as float attributes on the level-3 vertices, from landmark Gaussians: red (cheeks, nose, ears, knuckles),
  yellow (forehead), blue (around the eyes), oily (the T-zone), lips, brows, scalp, freckles, grime, sweat, thin skin,
  moles, two scars. At 1.2 mm between vertices a zone edge is soft by itself; a lip line drawn this way is acceptable.
- **Detail** as 3D procedural textures in object space, so no seam shows: blotches at 55 and 30 per metre, a crease
  net (Voronoi distance to edge, 1,500 per metre), pores (Voronoi F1, 1,900 per metre), lip lines (noise stretched
  2,600 across), freckles (Voronoi cells, a random share of them a dot), dirt as thresholded noise with streaks.
- **Maps:** albedo; normal; ORM (occlusion, roughness, unused); a mask (subsurface amount in red, sweat film in green).
- **Material:** Principled BSDF, subsurface `RANDOM_WALK_SKIN`, radius (1.0, 0.32, 0.16), scale 3.5 mm, the sweat
  film as coat weight (roughness 0.14, IOR 1.33).

Sweat is a low-roughness film plus beads; grime raises roughness and lowers the subsurface amount. Both read better
as a coat over rough skin than as a single low roughness, which looks like plastic.

## Eyes {#eyes}

<!-- new section: the layered eye is a recipe of its own -->

An eye that is one textured sphere looks dead. Games layer it
([Unreal's digital humans](https://dev.epicgames.com/documentation/en-us/unreal-engine/digital-humans-in-unreal-engine)):
the eyeball with a recessed iris; a clear cornea shell that bulges over the iris, refracts it and carries the wet
highlight; an occlusion shell that darkens the eye where the lids meet it; a tear line along the lower lid.
`s03_eyes.py` builds the four (3,872 triangles an eye): a 12.4 mm sphere, a 6.1 mm iris 0.9 mm concave, a 1.5 mm
corneal bulge, and an iris and sclera texture drawn with numpy (radial fibres, a collarette, a limbal ring, veins).

The lid contour is measured, not modelled: 64 rays around the eye's axis find the angle at which the eyeball goes
under a lid. The occlusion shell's vertex alpha, the tear line and the lash roots all come from that contour, so
they follow whatever the sculpt does to the lids. In Cycles the cornea is a transmissive Principled BSDF mixed with a
transparent one on shadow rays, or the iris under it goes dark.

## Hair {#hair}

<!-- new section: hair cards are a new asset class for GDStudio -->

Real-time hair is still mostly **cards**: strips of a few quads textured with many strands, in layers, because a
strand groom (100,000 curves) costs too much outside a showcase
([hair in Unreal](https://dev.epicgames.com/documentation/en-us/unreal-engine/hair-rendering-and-simulation-in-unreal-engine)).
The look comes from the atlas, the layering and an anisotropic shader with two shifted highlights
([Marschner and others, 2003](https://www.cs.cornell.edu/~srm/publications/SG03-hair-abstract.html);
[physically based hair shading in Unreal](https://blog.selfshadow.com/publications/s2016-shading-course/)).

`s04_hair.py` draws a 2K atlas of eight strips with numpy (dense clumps to flyaways, one strip of short tapered hairs
for brows and lashes): colour with alpha, a normal across each strand, depth as occlusion. Cards (15,400 triangles)
are traced from 1,500 scalp samples along a flow field (back and to her right on top, down at the sides), follow the
head at 1 to 5 mm and lift at the tip; their normals are the scalp's, so the cut shades as one volume. Brows (85
cards each) and lashes sit on the same atlas; a painted cap under the cards hides the scalp.

This is where rule-built work fell furthest from the references: see the gap list.

## Clothes and gear {#clothes}

<!-- new section: cloth cut from the body is a technique of its own, and so are its limits -->

Game clothes are drafted as sewing patterns and draped in a cloth simulator, which is where believable folds come
from; the drape is then retopologised and baked. The build has no drape. `rc_cloth.py` instead:

- **cuts a garment from the body's own faces** along the zero line of a field (edges split at the crossing, so a
  neckline is a clean curve), pushes it off the body and relaxes it under an outward-only constraint, so it bridges
  hollows the way stretched cloth does (`shell`);
- **lofts belts and straps** around the convex outline a plane cuts from the body and the clothes (`plane_ring`,
  `strap`): a belt is a horizontal plane, a sling a tilted one;
- **lofts a boot** over convex sections of the foot.

Folds are noise ridges, coarse ones in the geometry and fine ones in the normal map. They read as wrinkled, not as
draped: nothing hangs. Each look (jersey, canvas, leather, webbing, polymer, steel) is a small procedural recipe with
its wear (fading, sweat patches, dried mud, scuffed edges from the Pointiness output), baked like the skin to albedo,
normal and ORM, with a mask for a tiling weave normal.

## The rig {#rig}

<!-- new section: what it took to put a realistic body on the prototype mannequin's skeleton contract -->

The character is rigged on the prototype mannequin's skeleton (kit #1149): the Universal Animation Library's 65 bones
with the library's rest orientations in a T pose, bodies differing only in rest translations, plus the contract's 17
leaves and two eye bones of our own (84 bones). `s07_rig.py` lays a fitting armature on her joints in the A pose
she was modelled in, weights the body, poses it to the library's T, makes that the rest, and then gives every bone
the rest orientation read from the template's `mannequin_female.glb`. The build checks every bone's rest rotation in
its parent against the library's (largest difference 5.2e-6). In Godot the library's `Idle` plays on her with
`Skeleton3D.motion_scale` 1.0732 (her pelvis rests 0.9836 m up).

- **Approach:** Weight a sculpt-derived body by distance to each bone's segment, limited to the bones of the
  vertex's own body part and smoothed over the surface, when bone heat fails; then make the face rigid on the head.
  **Watch out for:** bone heat cannot solve a body with a mouth bag and eye sockets
  (`Bone Heat Weighting: failed to find solution`) and leaves it unweighted with exit code 0; and a face that shares
  weights with the neck slides over eyes, lashes and hair that are rigid on the head as soon as a clip turns the neck
  (the eyeballs stood 8 mm out of their sockets). **Seen:** gdstudio #1151, 2026-11-11 (fix: `body_weights` and the
  rigid face in `s07_rig.py`).
- **Approach:** After deleting imported objects in a script, skip `None` when walking `view_layer.objects`.
  **Watch out for:** `bpy.data.objects.remove` on a just-imported rig leaves a dead entry in the view layer until
  the next update, and `o.select_set` fails on it. **Seen:** gdstudio #1151, 2026-11-11.

## In Godot {#godot}

<!-- new section: what Godot 4.7 shows of a realistic character, measured in both renderers -->

The file Godot gets has no textures in it: glTF cannot say subsurface, a coat mask or hair, so the materials are
built in the test project (`sandbox/realistic-character/godot/main.gd`) from the texture sets, and the `.import`
files are written before the first import so the maps are compressed for the GPU.

| Feature | Forward+ | Compatibility (and the web) |
| --- | --- | --- |
| Albedo, normal, ORM maps | yes | yes |
| Subsurface scattering, transmittance | yes (screen space) | no: the property is ignored |
| Clearcoat (the sweat film) | yes | yes |
| Anisotropy (hair highlight) | yes | no |
| Hair alpha with depth pre-pass | yes | yes |
| Cornea as an additive highlight shell (premultiplied alpha) | yes | yes |
| Real refraction of the iris | only with a screen-reading shader, not built | no |
| Ambient occlusion in screen space | yes | no |

Frame cost, the character at bust distance with the library idle playing, 1080 by 1350, 4x MSAA, RTX 5080 (one
character; the empty scene's cost is subtracted):

| Renderer | GPU | CPU | Draw calls | Video memory |
| --- | --- | --- | --- | --- |
| Forward+ | +0.33 ms (0.19 to 0.52) | +0.05 ms | +37 | +412 MB |
| Compatibility | +0.19 ms (0.26 to 0.45) | +0.14 ms | +35 | +165 MB |

On this card the character is cheap in time and expensive in memory. Nothing was measured on a web build or a
laptop GPU: the texture sets (five 4K maps among them) are far over what a browser tab should hold, and a web
version needs 1K to 2K sets and a level of detail first.

- **Approach:** When a library clip plays on a body of other proportions, keep only rotation tracks, plus the
  position tracks of `pelvis` and `root`. **Watch out for:** the library's file keys a position on every bone, which
  is its own body's bone lengths; played as they are they stretched her neck and limbs to the mannequin's.
  **Seen:** gdstudio #1151, 2026-11-11 (fix: `_idle` in the test project drops the other position tracks).
- **Approach:** Map a surface to its material by the mesh's node name when the file carries placeholder
  materials. **Watch out for:** exported with `export_materials="PLACEHOLDER"`, the surfaces arrive in Godot with
  no named material to match on. **Seen:** gdstudio #1151, 2026-11-11.
- **Approach:** Judge skin maps in the engine that will show them, early. **Watch out for:** an albedo tuned under
  Cycles' random-walk subsurface, which saturates and darkens it, is pale in Godot, and a roughness that reads as
  sweat under a path tracer reads as plastic under point lights. **Seen:** gdstudio #1151, 2026-11-11 (not fixed).

## Budgets {#budgets}

<!-- new section: the triangle and texture numbers a realistic hero was built to -->

| Mesh | Triangles | Texture set |
| --- | --- | --- |
| Skin (head, neck, shoulders, arms, hands) | 53,544 | head 4K, body 4K: albedo, normal, ORM, mask |
| Clothes | 32,851 | 4K: albedo, normal, ORM, mask, and a 256 px weave tile |
| Gear | 5,721 | 2K |
| Hair | 15,400 | 2K atlas: albedo with alpha, normal, ORM |
| Brows and lashes | 1,032 | the hair atlas |
| Eyes (both) | 7,744 | 2K albedo |
| **Total** | **116,292** of a 130,000 budget | |

The export fails over 130,000 triangles, on a missing bone, and when the file read back does not match what was
built. A hero of a current third-person game is in the same range; what differs is where the triangles and texels
are spent, and that every one of them was placed by an artist.

## What Blender can and cannot do here {#blender}

<!-- new section: the answer to the experiment's question -->

**Can, by script:** reshape a Multires sculpt, bake it (Multires and Cycles bakes are fast and dependable), paint by
rule, build layered eyes, lay hair cards, cut and loft clothes, fit a rig to a contract, render in Cycles and EEVEE,
export a file Godot plays.

**Cannot, by script:** sculpt. Brushes need a person or an agent looking at the model stroke by stroke, and the
face, the hair and the folds of cloth are exactly the parts made that way. Blender has the tools (sculpt mode, the
cloth simulator, hair curves with its groom tools); a headless build does not reach them.

**Does not have:** scanned skin or fabric, a pattern-based cloth drape of the kind games use, a painting tool
comparable to the dedicated ones. Procedural detail is even everywhere, and real skin and cloth are not.

## Where it fell short {#gaps}

<!-- new section: the honest result of the experiment, each gap with its next step -->

Reached: one command builds a rigged, clothed, textured character that renders in three engines and plays a library
clip. Not reached: the references. At full-body distance in Cycles she reads as a game character of an older
generation; in a close-up she is uncanny; in Godot the skin is pale and oily.

| Gap | Why | Next step |
| --- | --- | --- |
| The face is a generic base with millimetre moves: no secondary forms, no designed character | skill and tool: no sculpting by script | an interactive sculpt session over the base (an agent driving Blender's sculpt mode, judged by renders), before any texture work |
| No expressions, teeth or tongue; the mouth is closed | time | a FACS-style set of shape keys once the face is sculpted |
| Skin detail is uniform procedural noise; no pore direction, no wrinkle maps | tool: no scan data | micro-detail tiling normals by region; licensed scan data is a maintainer decision |
| 8-bit normal maps band under Godot's clearcoat | time | 16-bit normal bakes, or dithering |
| Skin is pale and plastic in Godot | time: tuned only under Cycles | grade the albedo and roughness in Godot; a skin shader with its own profile |
| Hair is a dark cap: no layered silhouette, a hard hairline, no clumps of clumps | skill: a flow field is not a groom | a strand groom with Blender's hair curves, cards generated from its clumps, then hand placement |
| No real hair shader in Godot (one highlight, Forward+ only) | time | a spatial shader with two shifted highlights and a flow map |
| Clothes are body shells with noise folds; the trousers are tight; no seams, hems or stitching | tool: no drape by script | drape each garment with Blender's cloth simulator from a sewn pattern, then retopologise and bake |
| Gear is bevelled boxes | time | model each piece as a real hard-surface asset, high to low |
| Eyes have no refraction or caustics in Godot, sparse lashes | time | a parallax iris shader; lash cards from a denser strip |
| Weights are by distance; twist bones carry no weights; finger joints are mapped from the library, never checked in a fist | time | paint weights from clips that bend each joint; weight the twist bones |
| No level of detail, no web run, video memory 412 MB | time | 2K and 1K sets, a 30,000-triangle level, then measure in a browser |
| The tiling weave normal is not wired in Godot | time | a detail normal on a second UV set |

## Running the build {#running}

<!-- new section: the commands, and the two traps of running a staged Blender build -->

```sh
python sandbox/realistic-character/build.py --blender "$(gds tool path blender)" --work <scratch folder> \
    --base <human_base_meshes_bundle.blend> --mannequin <mannequin_female.glb> --out <asset folder>
blender -b -P sandbox/realistic-character/blender/s90_render.py -- --work <scratch folder> --stage s07 \
    --engine CYCLES --shots dark:face,day:bust
```

`--quick` bakes at a quarter size; `--from s05` starts at a later stage. The Godot test project's `asset/` folder is
filled by stage 8 and is ignored by git; run `godot/write_imports.py` on it before the first import. The lessons of
running it are on [Build scripts](build-scripts.md#running).
