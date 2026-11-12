# Realistic characters

<!-- new section: every Blender page is about flat-palette low-poly work; nothing held how a realistic game
character is made, what Blender and Godot can show of one, or what a first attempt reached (gdstudio #1151) -->

What GDStudio learned from its first realistic character: an experiment (gdstudio #1151) in how far a script-built
action-survival heroine gets in the pinned Blender alone, measured against current third-person games. The build
lives in `sandbox/realistic-character/` (eight Blender stages, a render script and a Godot test project); the asset
itself is not in the repository. Read [Where it fell short](#gaps) before planning any realistic asset: the
experiment is a working pipeline and a long way from the references. The maintainer's first review of pull
request #1175 (2026-11-11) found five faults, each with its section here: [hands](#hands), [hair](#hair),
[skin detail](#skin), [lines along the limbs](#limb-lines) and [shine](#shine).

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
| Hair | a groom of strands, rendered to a card atlas, cards placed by hand in layers | an atlas drawn with numpy, cards laid along paths (over the scalp to a tie, or falling off the head) |
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

## Hands {#hands}

<!-- new section: the first review found the hands too large for a woman; the cause was two faults, one in the mesh
and one in the rig, and neither had been measured (gdstudio #1151, pull request #1175) -->

A hand is judged against the body, so it is built to numbers. A woman's hand is 10 to 11 % of her height long and
about 4.8 % wide across the knuckles (ANSUR II, the US Army's survey: medians of 180 mm and 78 mm at a stature near
1.63 m), and about three quarters of her forearm (Drillis and Contini's segment lengths: hand 10.8 % of height,
forearm 14.6 %).

| | First build | Rework | A woman's |
| --- | --- | --- | --- |
| Hand length, wrist to middle fingertip | 197 mm, 11.7 % of 1.685 m | 178 mm, 10.6 % | 10 to 11 % |
| Hand breadth across the knuckles, thumb left out | 96 mm, 5.7 % | 82 mm, 4.9 % | about 4.8 % |
| Hand to forearm (elbow joint to wrist) | 0.88 | 0.77 | about 0.74 |
| Where the rig put the wrist | 8.5 cm up the forearm | on the wrist | |
| Where the rig put the knuckle joints | 4 to 5 cm short of the knuckles | 45 to 50 % of the hand's length from the wrist | |

`s01_sculpt.py` (`fit_hands`) scales each hand about its wrist in the hand's own frame (0.905 long, 0.86 wide),
narrows the wrist with it and lengthens the forearm by part of what the hand gave up, on the cage, so the sculpt
follows; the build then measures the result and fails outside 10.0 to 11.1 % and 4.4 to 5.1 %. `rc_lib.hand_frame`
is the measurement: the wrist is the last section before the palm flares (within 10 % of the forearm's thinnest
section), the breadth is read at the last section before the fingers part, once the thumb stands clear.

`s07_rig.py` finds the joints on the mesh: the wrist from the same measurement, the elbow 58.5 % of the way from the
shoulder joint to it, the four fingers as the pieces the hand falls into past the knuckle line, each finger's tip
and centre line from its own vertices, its joints at fixed shares of its length (the knuckle joint lies inside the
palm and cannot be read off the surface). A finger's bones are weighted only to its own piece of the hand. The
build then closes both hands (`rc_lib.pose_fist`) and asserts that every fingertip comes within three quarters of a
palm's length of the palm's middle (it measures 4.8 cm on a 9.2 cm palm) and that no edge of the hand stretches
more than six times (the webs between the fingers stretch 2.9 and 5.1 times: the weakest part left).

- **Approach:** Measure a character's hands against its height and forearm (length, breadth, hand to forearm)
  before texturing, hold them to the reference numbers in the build, and show them in a sheet beside the reference
  at the picture's own scale. **Watch out for:** a base mesh that calls itself realistic and female came with hands
  of 11.7 % of the height and 5.7 % wide, a man's breadth; nothing had measured them, and at full-body distance
  they were the first thing the maintainer saw. **Seen:** gdstudio #1151, pull request #1175, 2026-11-11 (fix:
  `fit_hands` and its assert).
- **Approach:** Find the wrist, the elbow and the finger joints on the mesh (section widths, the pieces the fingers
  fall into) and print where each landed as a share of the limb; never take a joint from where a UV tile or a
  material ends. **Watch out for:** the base mesh's hand tile starts 8.5 cm up the forearm, and the rig put the
  hand bone on that seam, so the forearm bent in the middle, the "hand" that turned was 28 cm long, the finger
  bones were stretched over it with every knuckle 4 to 5 cm short, and the watch sat mid-forearm. **Seen:** gdstudio
  #1151, pull request #1175, 2026-11-11 (fix: `joints`, `segment_hand` and `finger_joints` in `s07_rig.py`).
- **Approach:** Close the hand into a fist in the build and look at it from three sides before any clip plays on
  it; assert the fingertips' reach and the worst edge stretch. **Watch out for:** finger joints mapped from another
  rig's proportions were never bent, so nothing showed they were not on the knuckles; and a deformation that moves
  a limb's vertices by position alone (everything below the wrist along its axis) also moved a leg, which only the
  lowest-vertex check caught. **Seen:** gdstudio #1151, pull request #1175, 2026-11-11 (`check_fist`; the hand fit
  now takes the arm's own vertices). Not fixed: the thumb's base is placed by proportion, and a library clip that
  curls the thumb hooks it.

## UVs and the bake {#baking}

<!-- new section: GDStudio's first texture bake; materials.md#baking asked for its numbers to be written down -->

The skin the clothes hide is deleted from the cage first (the trunk under the top, the legs, the feet): 53,544
triangles of skin remain, and the UV space goes to what is seen. The cage's UVs are packed into two sets, head and
body, and three things come from it: the game mesh (Multires level 1 applied), the surface the textures are painted
on (level 3 applied, 856,704 triangles) and the cage itself for the normal bake.

- **Normals, sculpt and painted detail in one map:** a Cycles bake from the painted level-3 surface onto the game
  mesh itself (`bake(type="NORMAL", use_selected_to_active=True, cage_extrusion=0.0035, max_ray_distance=0.007)`),
  into a 32-bit float image saved as a 16-bit PNG. The game mesh is triangulated first, so the bake, the export's
  tangents and Godot all see the same triangles. The first build used Blender's Multires baker for the sculpt and
  laid the painted detail over it; that drew the lines of [Lines along a limb](#limb-lines).
- **Colour, roughness, masks:** emission bakes of the same node tree on the level-3 surface, eight samples each.
- **Ambient occlusion:** a Cycles `AO` bake, 64 samples, with every other object hidden from the render.

The whole skin stage (seven bakes of two 4K sets) runs in under two minutes on an RTX 5080; at a quarter size, 18
seconds. Texel density: about 84 pixels per centimetre on the head at 4K.

- **Approach:** Pack each UV set with only its faces selected (`mesh.select_all(DESELECT)`,
  `object.material_slot_select()`, then `uv.average_islands_scale()` and `uv.pack_islands()`), leave islands on the
  UDIM tiles they came on until after the pack, and assert each set's UV bounds afterwards. **Watch out for:** with
  UV sync selection on, `uv.select_all` selects every face of the mesh, so both sets packed into one square; and
  mirrored halves stored exactly two tiles apart, once shifted into 0..1, share their seam's UVs and are packed as
  one folded island. **Seen:** gdstudio #1151, 2026-11-11 (fix: no `uv.select_all`; the tiles are brought home after
  the pack; the build asserts 0..1).
- **Approach:** Keep a skin's normal map at 16 bits a channel from the bake to the file (a float bake target,
  `rc_lib.write_png16`), and set `colorspace_settings.name = "Non-Color"` on any 16-bit PNG before reading its
  pixels; assert that a normal map's mean is flat (within 0.02 of 0.5) wherever a script rewrites one.
  **Watch out for:** Blender takes a loaded 16-bit PNG for sRGB colour and hands back linearised floats, so the
  export's resize turned a flat normal (0.5) into 0.21 and tilted the whole map: in Godot each half of the face was
  lit from a different side, split along the UV seam, and it looked like a tangent fault. **Seen:** gdstudio #1151,
  pull request #1175, 2026-11-11 (fix: the colour space and the assert in `s08_export.py`; found by printing the
  map's mean, after an hour on tangents).
- **Approach:** Hide every helper mesh from the render before an occlusion bake, and print the map's median.
  **Watch out for:** the cage and the whole-body copy lie on the surface being baked and occluded it: the first
  build's skin occlusion had a median of 0.38 to 0.45 where an open surface gives 0.86 to 0.92, which darkened the
  skin's ambient light and made its highlights stand out. **Seen:** gdstudio #1151, pull request #1175, 2026-11-11
  (fix: `hide_render` on everything but the bake's own meshes in `s02_skin.py`).

## Lines along a limb {#limb-lines}

<!-- new section: the first review saw ridges along the arms in Godot; the first build had blamed 8-bit banding
without measuring, and the cause was the bake (gdstudio #1151, pull request #1175) -->

In Godot the first build's arms carried fine lines along their length, as if the mesh had never been smoothed.
The cause was found by switching one suspect off per capture (`godot/diag.gd`: one close view of the arm, the same
frame per variant) and scoring each capture (`godot/limb_lines.py`: the mean difference between the picture's
luminance and its own 9-pixel blur, inside the arm, in thousandths of full scale):

| Variant of the body skin's material, first build | Score |
| --- | --- |
| As shipped | 6.8 |
| Normal map off | 3.1 (what the colour map alone draws) |
| Normal map loaded uncompressed (no BC5) | 6.5 |
| Clearcoat off | 6.8 |
| Mesh alone, grey, no maps | 0.5 |
| **Rework: the same material with the new maps** | **4.7** (colour map alone 2.6; the rest is painted pores and creases) |

So not the mesh (smooth shading, weights and vertex normals are clean: 0.5), not the GPU compression, not the coat
and not 8-bit banding: the lines are in the normal map. Opened, the map showed a grid: a ridge along every edge
loop of the game mesh. Blender's Multires baker (`bake_image` with `use_multires`) writes the sculpt's detail
relative to the lower level's own surface, not to the mesh the engine draws with interpolated vertex normals and
MikkTSpace tangents, and the difference is one crease per quad. The fix is the bake of [UVs and the bake](#baking):
one Cycles bake from the high surface onto the triangulated game mesh. The 16-bit map changed nothing that could be
measured against its 8-bit BC5 import (4.5 against 4.7), so the test project keeps the compressed import; a tiling
pore normal is laid over the map in the skin shader for close range.

- **Approach:** When a surface shows lines in the engine, capture the same frame with one suspect off at a time
  (normal map, its compression, the coat, the maps altogether) and score the captures, then open the map that the
  numbers point at. **Watch out for:** the first build wrote the lines down as 8-bit banding under the coat, a
  guess that fitted what it saw, and its next step would have been 16-bit maps of the same ridges. **Seen:**
  gdstudio #1151, pull request #1175, 2026-11-11 (the table above).
- **Approach:** Bake a sculpt's normals onto the game mesh that will be exported, triangulated, with Cycles
  (selected to active); use the Multires baker only when the engine also subdivides. **Watch out for:** a Multires
  bake between levels 1 and 3 looks right in Blender's own viewport on the Multires object and puts a ridge on
  every level-1 edge once level 1 is applied and drawn as a plain mesh. **Seen:** gdstudio #1151, pull request
  #1175, 2026-11-11 (fix: `bake_normal` in `s02_skin.py`).

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

The build paints by rule (`s02_skin.py`), in three layers:

- **Zones** as float attributes on the level-3 vertices, from landmark Gaussians: red (cheeks, nose and its wings,
  ears, chin, knuckles, elbows), yellow (forehead), blue (around the eyes), oily (the middle of the forehead, the
  nose, the chin), large pores (nose, inner cheeks, chin), lips and the line where they meet, brows, scalp, freckles,
  grime, thin skin, moles, two scars, veins (inner wrist, back of the hand), peach fuzz, and where each kind of line
  sits. At 1.2 mm between vertices a zone edge is soft by itself; a zone with a hard edge (a threshold on a height)
  draws a line across the limb it cuts.
- **Lines**, each a zone times a pattern with the line's direction, since a vertex cannot hold a 0.3 mm line:
  forehead lines (the mid-level contours of a noise stretched level), finer ones under the eye, crow's feet (the
  same contours of a noise of the angle about the eye's outer corner, so they radiate), the fold from the nose's
  wing to the mouth's corner and two neck lines (drawn on the vertices, they are soft), lip lines at two scales, a
  coarser crease net on the knuckles, elbows and the backs of the hands.
- **Detail** as 3D procedural textures in object space, so no seam shows: blotches at 55 and 30 per metre, a finer
  red and sallow mottle at 210, a capillary net on the cheeks, the crease net (Voronoi distance to edge, 1,500 per
  metre), pores (Voronoi F1 at 1,900, and at 1,150 and twice as deep where pores are large), freckles, veins (a
  warped Voronoi net, blue-green at 30 %), dirt as thresholded noise with streaks.
- **Maps:** albedo; normal (16 bits); ORM (occlusion, roughness, unused); a mask (subsurface amount in red, the oil
  film in green, peach fuzz in blue); and a 512 px tiling normal of pores in a crease net, drawn from a Voronoi that
  wraps, which the engine lays over the baked map about every 2 cm.
- **Roughness:** dry skin 0.62 to 0.74 and never even (three scales of noise), 0.46 at the oiliest of the forehead
  and nose, lips 0.36 to 0.50, creases and joints rougher, dirt 0.82, the painted scalp 0.80.
- **Material:** Principled BSDF, subsurface `RANDOM_WALK_SKIN`, radius (1.0, 0.32, 0.16), scale 3.5 mm; the oil film
  as a coat of weight 0.25 at roughness 0.30; the fuzz as a sheen of 0.12.

Peach fuzz is not hair here: in Godot it is the material's rim term where the mask's blue says fine hair grows
(0.08, half tinted), which catches light at grazing angles the way down does and costs nothing. Cards of vellus
hair along the jaw stay on the gap list.

- **Approach:** Paint skin detail where a face has it, by zone and with a direction: lines as patterns that run
  the way the line runs, pores larger where they are, redness and veins where blood shows, and roughness that
  differs between forehead, cheek and lip. **Watch out for:** one pore noise and one crease net over the whole body
  is detail only in the sense that the map is not flat: from a bust's distance it reads as an even, slightly rough
  plastic, and the maintainer asked for exactly the things a rule had not placed (lines at the eyes, mouth and
  forehead, lips, redness at the nose, cheeks and ears, veins at the wrists, varied roughness). **Seen:** gdstudio
  #1151, pull request #1175, 2026-11-11 (fix: the zone and line layers above). Still short of a scan: see the gap
  list.
- **Approach:** Give every painted zone a soft edge, and look at each limb the zone crosses. **Watch out for:** an
  "arm" zone cut with a threshold on height drew a straight tone step across the upper arm, which read as a second
  seam once the normal map's lines were gone. **Seen:** gdstudio #1151, pull request #1175, 2026-11-11 (fix: the
  zone is a product of two smooth steps).

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
The look comes from the atlas, the layering and a shader with two shifted highlights
([Marschner and others, 2003](https://www.cs.cornell.edu/~srm/publications/SG03-hair-abstract.html);
[physically based hair shading in Unreal](https://blog.selfshadow.com/publications/s2016-shading-course/)).

`s04_hair.py` draws a 2K atlas of eight strips with numpy (dense locks to flyaways, one strip of short tapered hairs
for brows and lashes, a solid patch for the hair tie): colour with alpha, a normal across each strand, depth as
occlusion. The hair is a chestnut brown; one strand in seven is sun-lightened. Two styles are built, one worn at a
time:

| Style | How its cards run | Triangles |
| --- | --- | --- |
| Ponytail | 820 cards drawn back over the scalp from their roots to a tie high on the back of the head (each steps along the surface towards the tie, lifted 1 to 6 mm in the middle); 95 cards of tail that arc out and fall under gravity, fanned about one centre line; 110 short hairs along the hairline; two loose strands at each temple; a torus for the tie | 21,984 |
| Long, worn down | 500 cards from a part on her left: on the skull they are held to the surface and run away from the part, down and back off the forehead; below the ears they fall, pushed off the neck, shoulders and chest, with a slow wave shared by neighbours; 90 short hairs along the hairline | 20,060 |

A falling card's path is a small simulation (`fall`): each step turns towards a direction field that carries
gravity, and a point nearer the body than its clearance is pushed out to it; the clearance grows over the first
five steps so a root does not stand up. Normals are the scalp's under a card, or point away from a lock's centre
line, so a style shades as one volume. The hairline is three things: the scalp painted in the hair's colour and
fading over a centimetre in strokes (stage 2), thinner cards of fewer strands rooted on the rim, and the short hairs.
Brows (85 cards each) and lashes sit on the same atlas. Long hair is weighted to the head down to the jaw and to
the chest below it; the ponytail is rigid on the head.

In Godot the cards use `godot/hair.gdshader`: the built-in highlight is off and `light()` draws hair's two (a
sharp, colourless one shifted to the tip, a broad one in the hair's colour shifted to the root, each strand
shifting them a little), from the card's V axis. It runs in Forward+ and in Compatibility.

- **Approach:** Ask which hairstyle a character wears before building any, name two that a woman of today wears,
  and build the hair as a style (where it is gathered, where it parts, how long it is), not as cards along a
  field. **Watch out for:** a short cut swept back from a flow field was nobody's choice: it came from what the
  generator made easily, read as a dark cap in Godot, and the maintainer asked for a ponytail and for long hair worn
  down. **Seen:** gdstudio #1151, pull request #1175, 2026-11-11 (fix: `ponytail` and `long_hair`).
- **Approach:** Draw the hairline as a head has it, seen from the side (down to the front of the ear, over the
  ear, down behind it, level across the nape), and look at the head in profile and from behind with the hair on.
  **Watch out for:** one plane from the forehead to the nape was enough under a short cut and left the head bare
  behind the ears under a ponytail, like an undercut; the first redraw then cut the temple off above the ear.
  **Seen:** gdstudio #1151, pull request #1175, 2026-11-11 (fix: `rc_lib.scalp_mask`).
- **Approach:** Hold hair to the skull where it lies on it and let it fall only below the head's widest part.
  **Watch out for:** a path that is only pushed out of the body leaves the head in a straight line: the first long
  hair stood out sideways like a hat brim. **Seen:** gdstudio #1151, pull request #1175, 2026-11-11 (fix: `stick_z`
  in `fall`).
- **Approach:** Light a two-sided card with the normal the build stored, passed from `vertex()`, whichever side
  faces the camera, and keep the hair's colour, the painted scalp's and the highlights' strengths in step by
  looking at all three lightings. **Watch out for:** left to the engine, the side of a card that faces away is lit
  from inside the head and went black in patches; highlights tuned in daylight turned brown hair blond under a
  strong rim light; and a painted scalp lighter than the cards over it showed as a band along the hairline.
  **Seen:** gdstudio #1151, pull request #1175, 2026-11-11.

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

- **Approach:** Give a cut garment every face its outline may cross, whatever tile or part they belong to, and
  keep an armhole's edge on the trunk. **Watch out for:** the top was cut from the torso's tile only, so where the
  cut line ran onto the shoulder's cap (the arm's tile) the edge followed the tile's stair-stepped seam, and a
  shallow armhole ran through the fold in front of the armpit and ended in a point: a ragged armhole in Godot.
  **Seen:** gdstudio #1151, pull request #1175, 2026-11-11 (fix: the arm's faces above the armpit join the cut,
  and the armhole is 12.7 cm in radius).

Folds are noise ridges, coarse ones in the geometry and fine ones in the normal map. They read as wrinkled, not as
draped: nothing hangs. Each look (jersey, canvas, leather, webbing, polymer, steel) is a small procedural recipe with
its wear (fading, sweat patches, dried mud, scuffed edges from the Pointiness output), baked like the skin to albedo,
normal and ORM, with a mask for a tiling weave normal.

## The rig {#rig}

<!-- new section: what it took to put a realistic body on the prototype mannequin's skeleton contract -->

The character is rigged on the prototype mannequin's skeleton (kit #1149): the Universal Animation Library's 65 bones
with the library's rest orientations in a T pose, bodies differing only in rest translations, plus the contract's 17
leaves and two eye bones of our own (84 bones). `s07_rig.py` lays a fitting armature on her joints in the A pose she
was modelled in (the arm's and the hand's joints are measured on the mesh: [Hands](#hands)), weights the body, poses
it to the library's T, makes that the rest, and then gives every bone the rest orientation read from the template's
`mannequin_female.glb`. The build checks every bone's rest rotation in its parent against the library's (largest
difference 5.2e-6). In Godot the library's `Idle` plays on her with `Skeleton3D.motion_scale` 1.0732 (her pelvis rests
0.9836 m up).

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
files are written before the first import so the maps are compressed for the GPU. Skin and hair have shaders of
their own (`skin.gdshader`, `hair.gdshader`); clothes and gear are `StandardMaterial3D`. Both hairstyles are in the
file and the test project frees the one not worn.

| Feature | Forward+ | Compatibility (and the web) |
| --- | --- | --- |
| Albedo, normal, ORM maps | yes | yes |
| Subsurface scattering, transmittance | yes (screen space) | no: the property is ignored |
| Clearcoat (the oil film on the forehead, nose, chin and lips) | yes | yes |
| A tiling pore normal over the baked one | yes | yes |
| Rim where peach fuzz grows | yes | yes |
| Hair's two highlights (the hair shader's `light()`) | yes | yes |
| `StandardMaterial3D` anisotropy (the first build's one hair highlight) | yes | no |
| Hair alpha with depth pre-pass | yes | yes |
| Cornea as an additive highlight shell (premultiplied alpha) | yes | yes |
| Real refraction of the iris | only with a screen-reading shader, not built | no |
| Ambient occlusion in screen space | yes | no |

Frame cost, the character at bust distance with the library idle playing, 1080 by 1350, 4x MSAA, RTX 5080 (one
character; the empty scene's cost is subtracted; the first build's numbers in brackets):

| Renderer, hairstyle | GPU | CPU | Draw calls | Video memory |
| --- | --- | --- | --- | --- |
| Forward+, ponytail | +0.36 ms (0.18 to 0.54) [+0.33] | +0.06 ms [+0.05] | +37 | +400 MB [+412] |
| Forward+, long hair | +0.48 ms (0.18 to 0.66) | +0.06 ms | +37 | +399 MB |
| Compatibility, ponytail | +0.29 ms (0.20 to 0.49) [+0.19] | +0.16 ms [+0.14] | +35 | +152 MB [+165] |
| Compatibility, long hair | +0.36 ms (0.20 to 0.55) | +0.11 ms | +35 | +152 MB |

The two shaders and the heavier hair cost about a tenth of a millisecond; memory is as before (the coat maps went,
a detail tile came). On this card the character is cheap in time and expensive in memory. Nothing was measured on a
web build or a laptop GPU: the texture sets (five 4K maps among them) are far over what a browser tab should hold,
and a web version needs 1K to 2K sets and a level of detail first.

- **Approach:** When a library clip plays on a body of other proportions, keep only rotation tracks, plus the
  position tracks of `pelvis` and `root`. **Watch out for:** the library's file keys a position on every bone, which
  is its own body's bone lengths; played as they are they stretched her neck and limbs to the mannequin's.
  **Seen:** gdstudio #1151, 2026-11-11 (fix: `_idle` in the test project drops the other position tracks).
- **Approach:** Map a surface to its material by the mesh's node name when the file carries placeholder
  materials. **Watch out for:** exported with `export_materials="PLACEHOLDER"`, the surfaces arrive in Godot with
  no named material to match on. **Seen:** gdstudio #1151, 2026-11-11.
- **Approach:** Judge skin maps in the engine that will show them, early. **Watch out for:** an albedo tuned under
  Cycles' random-walk subsurface, which saturates and darkens it, is pale in Godot, and a roughness that reads as
  sweat under a path tracer reads as plastic under point lights. **Seen:** gdstudio #1151, 2026-11-11 (the shine
  was then fixed in Godot: [Shine](#shine)).
- **Approach:** Aim a character's eye bones at the camera (or at what she looks at) in any capture taken while a
  clip plays, and frame a close-up from the head bone. **Watch out for:** the library's idle tips the head back
  eight degrees; eyes left at rest then stare over the lens with white under the iris, which read as a fault of
  the eyes, and a camera placed for the rest pose framed her forehead. **Seen:** gdstudio #1151, pull request
  #1175, 2026-11-11 (fix: `_look` and the face shot in `main.gd`).

## Shine {#shine}

<!-- new section: the first review found the whole character too shiny, the skin above all; the cause was measured
in Godot and was not the first three suspects (gdstudio #1151, pull request #1175) -->

The first build read as wet. The channels were checked first: roughness in green and metal in blue survive the
bake and the import (metal is 0 on every set; the cloth's roughness median is 0.90, the skin's was 0.50). Then
`godot/diag.gd --what=shine` captured the bust with one suspect off at a time, and `godot/shine.py` compared each
capture with one that has every highlight off: "added" is the light the highlights add over the character, "hot"
the share of her pixels where a highlight adds more than a tenth of full scale.

| First build, Forward+ | Day: added, hot | Warm interior: added, hot |
| --- | --- | --- |
| As shipped | 7.1 %, 1.8 % | 12.1 %, 9.9 % |
| Clearcoat off | 7.2 %, 1.9 % | 12.3 %, 10.1 % |
| Reflected background off | 7.1 %, 1.8 % | 12.1 %, 9.9 % |
| Skin roughness 0.70 everywhere | 7.4 %, 0.9 % | 11.7 %, 7.1 % |
| Specular 0 on every material | 0.0 %, 0.0 % | 0.2 %, 0.2 % |

The coat and the reflected background did nothing that could be measured. The shine was the plain specular lobe:
every material at Godot's default of 0.5 (4 % reflectance) on skin whose roughness sat at 0.37 to 0.55, under an
occlusion map that was half black, so the ambient light under the highlights was dim. Roughness moves how hard the
spots are (the hot share), not how much light they add; the level of specular moves both.

| Material | Specular (Godot's scale) | Roughness |
| --- | --- | --- |
| Skin | 0.35 (2.8 % reflectance) | from the map: 0.62 to 0.74 dry, 0.46 at the oiliest, lips 0.36 to 0.50 |
| Oil film on the forehead, nose, chin and lips | clearcoat 0.06 times the mask | 0.45 |
| Cloth, leather, webbing, boots | 0.25 | from the map: cloth 0.90, leather and webbing 0.6 to 0.8; the metal channel is not read |
| Gear (polymer, steel, glass) | 0.5 | from the map, with its metal channel |
| Hair | built-in 0; its two highlights 0.02 and 0.04 | 1.0 |
| Eyes | default | 0.38; the cornea shell 0.04 |

The rework, measured the same way (the rest pose with the arms down, as the first build was):

| Rework | Day: added, hot | Dark interior | Warm interior |
| --- | --- | --- | --- |
| Forward+, ponytail | 3.9 %, 0.6 % | 8.0 %, 7.3 % | 7.8 %, 5.6 % |
| Compatibility, ponytail | 4.5 %, 4.4 % | 6.7 %, 9.1 % | 8.2 %, 6.3 % |
| Forward+, long hair | 5.8 %, 2.9 % | 10.6 %, 13.9 % | 12.3 %, 13.3 % |

With the ponytail the highlights add about half of what they did and the hard spots fall by a third to two thirds;
what is left on the skin is a soft sheen on the forehead, the nose and the lips, and the rim light's grazing
reflection along a shoulder. Long hair scores higher because hair's broad highlight covers far more of the frame;
it is the weakest of these numbers and is tuned by eye.

- **Approach:** When a character is too shiny in the engine, check that the channels survive first, then capture
  it with one suspect off at a time against a capture with every highlight off, and tune specular level and
  roughness per material in the engine, in every lighting. **Watch out for:** the first build put its shine down
  to the coat and to Cycles-tuned maps; the coat measured as nothing, the reflected background as nothing, and the
  cause was specular left at 0.5 on skin of roughness 0.5 over an occlusion map darkened by the bake's own helper
  meshes. A first measure (mean added light) could not tell wet from dry: it needed the share of hard spots, and
  the two captures of a pair must be of a still pose. **Seen:** gdstudio #1151, pull request #1175, 2026-11-11
  (the two tables above).

## Budgets {#budgets}

<!-- new section: the triangle and texture numbers a realistic hero was built to -->

| Mesh | Triangles | Texture set |
| --- | --- | --- |
| Skin (head, neck, shoulders, arms, hands) | 53,544 | head 4K, body 4K (2K in Godot): albedo, 16-bit normal, ORM, mask; a 512 px pore tile |
| Clothes | 32,062 | 4K: albedo, normal, ORM, mask, and a 256 px weave tile |
| Gear | 5,646 | 2K |
| Hair, ponytail (or long: 20,060) | 21,984 | 2K atlas: albedo with alpha, normal, ORM |
| Brows and lashes | 1,032 | the hair atlas |
| Eyes (both) | 7,744 | 2K albedo |
| **Total, one hairstyle worn** | **122,012** of a 130,000 budget (142,072 in the file with both) | |

The export fails over 130,000 triangles worn at once, on a missing bone, on a normal map that is not flat on average,
and when the file read back does not match what was built. A hero of a current third-person game is in the same range;
what differs is where the triangles and texels are spent, and that every one of them was placed by an artist.

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
generation; in a close-up she is uncanny. After the first review's rework the hands are a woman's, the hair is a
style, the skin is dry and has a face's detail, and the arms are smooth in Godot; the rows below are what is left.

| Gap | Why | Next step |
| --- | --- | --- |
| The face is a generic base with millimetre moves: no secondary forms, no designed character | skill and tool: no sculpting by script | an interactive sculpt session over the base (an agent driving Blender's sculpt mode, judged by renders), before any texture work |
| No expressions, teeth or tongue; the mouth is closed | time | a FACS-style set of shape keys once the face is sculpted |
| Skin detail is painted by rule: lines and pores sit where a face has them, but none is this face's, and there are no wrinkle maps that move with an expression | tool: no scan data | licensed scan data is a maintainer decision; wrinkle maps with the shape keys |
| Peach fuzz is a rim term, not hair | time | cards of vellus hair along the jaw and the forearms, on the hair atlas |
| Hair is cards along computed paths: no clumps of clumps, no hand-placed layers, the long style's ends are cut straight, and neither style moves | skill and time | a strand groom with Blender's hair curves, cards generated from its clumps; spring bones for the tail and the long locks |
| The hair's two highlights are tuned by eye; the skin shader has one specular lobe | time | a flow map for the hair; a second skin lobe |
| In Compatibility the eyes go dark (the occlusion shell and the highlight shell over them blend differently) and the hair cards show darker gaps; in both renderers the hair on the back of the head is much darker in shadow than the lit tail | time: seen in the last captures of the rework, not fixed | an eye occlusion drawn in the eye's own shader; alpha to coverage for the cards; a little light through the hair |
| Clothes are body shells with noise folds; the trousers are tight; no seams, hems or stitching | tool: no drape by script | drape each garment with Blender's cloth simulator from a sewn pattern, then retopologise and bake |
| Gear is bevelled boxes | time | model each piece as a real hard-surface asset, high to low |
| Eyes have no refraction or caustics in Godot, sparse lashes | time | a parallax iris shader; lash cards from a denser strip |
| Weights are by distance; twist bones carry no weights; the webs between the fingers stretch up to 5 times in a fist; the thumb's base is placed by proportion and a library clip hooks it | time | paint weights from clips that bend each joint; weight the twist bones; find the thumb's base on the mesh |
| No level of detail, no web run, video memory 400 MB | time | 2K and 1K sets, a 30,000-triangle level, then measure in a browser |
| The cloth's tiling weave normal is not wired in Godot (the skin's pore tile is) | time | the same two lines in a cloth shader |

## Running the build {#running}

<!-- new section: the commands, and the two traps of running a staged Blender build -->

```sh
python sandbox/realistic-character/build.py --blender "$(gds tool path blender)" --work <scratch folder> \
    --base <human_base_meshes_bundle.blend> --mannequin <mannequin_female.glb> --out <asset folder>
blender -b -P sandbox/realistic-character/blender/s90_render.py -- --work <scratch folder> --stage s07 \
    --engine CYCLES --shots dark:face,day:bust
```

`--quick` bakes at a quarter size; `--from s05` starts at a later stage. The render takes `--hair ponytail|long` and
`--pose relaxed|rest|fist` (with the shots `hand_back`, `hand_palm`, `hand_front` and `arm` for the T rest). The test
project takes `--hair=`, `--shine` (the pairs `shine.py` reads), `--rest` and `--only=<light>_<shot>`;
`res://diag.tscn` is the diagnostic of [Lines along a limb](#limb-lines) and [Shine](#shine). The Godot test project's
`asset/` folder is filled by stage 8 and is ignored by git; run `godot/write_imports.py` on it before the first
import. The lessons of running it are on [Build scripts](build-scripts.md#running).
