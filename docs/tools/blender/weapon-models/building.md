# Building a weapon model

<!-- new section: weapons.md passed 44 KB with four weapon pull requests adding to it (gdstudio #1123, from #1081's
     report), so its sections on the model itself moved here; weapons.md keeps the hold and the hands, and a short
     section per moved anchor that links to each -->

The weapon model itself: its attachment points, the parts that move in a reload, building it by script, palette cells
in Godot, what reads on a phone, many weapons built at once and the budgets. The axes, the hold and the hands on the
weapon are on [Weapons](../weapons.md).

## Attachment points {#attachment-points}

Where an effect or a hand meets a weapon is part of the model, so **attachment points are the modeller's job**: whoever
builds a weapon places them in Blender, and gameplay code reads them instead of typing offsets from the body.

- **Every firearm carries an empty named `Muzzle`** at the centre of the barrel's open end, parented to the weapon's
  root, with **-Z pointing out of the barrel** (Godot's forward). In Blender that is the empty's local **+Y**: the glTF
  export turns Blender +Y into -Z. For a gun along Blender -X, turn the empty 90 degrees about Z
  (`rotation_euler = (0, 0, pi/2)`); it arrives in Godot turned 90 degrees about Y, -Z along the barrel.
- **Two barrels side by side get one `Muzzle` centred between them**, at the barrels' end face.
- **Melee weapons and grenades get none.**
- **A gun with an ejection port carries `Eject`** at the port's centre, keeping the weapon's own axes: its local
  +Y is the gun's right side in Blender, so its -Z in Godot points out of the port (Deadnight #786, for a case
  effect).
- **Every level of detail carries it at the same point**, so the flash does not jump when the far level swaps in.
- **A test proves it:** load each firearm's file, find `Muzzle`, check it sits within 1 cm of the bounds' front face
  along the barrel and points along it. Deadnight's is `game/tests/art/test_weapon_muzzle.gd`, built by its
  `build_weapons.py` (`MUZZLES`) and drawn by `render_muzzle.py`.

**Tools swung by a clip.** A tool that only an action clip swings (Deadnight's repair hammer, #326) takes the melee
hold and then a turn chosen from the clip itself: trace the striking face through one loop for a few turns about the
handle and tips in the swing plane, and keep the one whose face points along the blow and toward the target at the
lowest point. For the Soldier's `Repair_Board`, the bat's hold already faced the board; a 20-degree tip in the swing
plane squared the face to the downward blow. Draw a small tool large (the kit's knife is 1.4 m, longer than its
shovel), and size it in the hand for the fist: a hammer at the size rule's 0.29 m vanished in the Soldier's chibi
fist, at 0.45 m only the head showed, at 0.50 m it read. Give the tool its striking point as a node (`Face`, -Z out
of the face), as a gun carries its `Muzzle`.

- **Approach:** Place a `Muzzle` empty at the barrel tip of every firearm in Blender (-Z out of the barrel in Godot),
  and test that it sits at the barrel end and that the flash spawns on it. **Watch out for:** attachment points belong
  to the model, and the muzzle was a fixed offset from the body, the same for every gun, so the flash sat away from the
  barrel. **Seen:** Deadnight, 2026-11-01 (fix: every firearm carries `Muzzle`, and `test_weapon_muzzle.gd` checks it
  (above)).

## Moving parts and a reload's ammunition {#moving-parts-and-a-reloads-ammunition}

A reload reads when something on the gun moves (a drum comes off, the barrels break open, a cylinder swings out, a
lever is thrown) and the left hand brings something back from the belt. Both are the modeller's, like the `Muzzle`:

- **The moving part is its own node**, built on its own and joined at its pivot (the hinge pin, the crane, the lever's
  pin, a drum's centre), parented to the weapon's root so the weapon keeps its origin. The game turns it about an axis
  of the model or slides it, and nothing else needs to change: the grip sockets, the `Muzzle` and the triangle count
  stay the same (Deadnight #683 split five guns this way and every count and size came out identical). Move with the
  part what moves in the real gun: a break-open's forend goes with its barrels, a lever rifle's trigger stays.
- **The ammunition is a small model of its own** beside the gun's (`<gun>_ammo.glb`: two shells, a round, a
  speedloader, a flare cartridge), never a hidden node in the gun's file, which every other view of the gun (a wall buy,
  a prize, the menu) would then show. A drum that is the gun's own part is the same mesh again.
- **Draw the ammunition for the fist, not the gun.** At the gun's size a shell vanished inside the Soldier's left
  hand; the game holds it at 1.5 times the gun's size, standing out of the fingertips (the hand bone's +Y runs along the
  fingers, their tips 0.25 bone units out), as the grenade showed: it passed every hold test and was hidden in the
  fist from the side, so a small held prop gets close views of its own in the capture sheet (Deadnight #285).
- Godot's axes for a gun drawn along Blender -X: the muzzle is -X, up +Y and **the gun's left is +Z** (Blender -Y). A
  break-open's muzzle drops with a positive turn about +Z; a cylinder swings out to the left with a positive turn about
  +X about a crane under its left side.

Deadnight's tools: `build_weapons.py` (`NODES`, `AMMO`); the motion is its `docs/design/animation.md` "Reloading".

## Building by script {#building-by-script}

| Lesson | Detail |
| --- | --- |
| Draw real, then fatten | Drawn at real proportions, a gun looks spindly beside the kit. Scale every part 1.4-1.5x across its length before chamfering to get the kit's chunky cross-sections |
| Big receiver, shallow stock | The kit's guns read as a large grey block; keep the stock shallow with a slanted butt, or the fattening turns it into a wedge (Deadnight's PPSh, MP5 and M4A1 first came out with butts 0.16-0.20 m deep in drawing units and read as wedges; 0.14-0.16 m read). Render a turntable beside a kit-style gun after the first build, before solving anything against it |
| Chamfer only the big parts | A one-segment chamfer (about 17 mm at kit scale) costs a box 44 tris instead of 12; leave screws, pins, sights and lever segments hard |
| Kitbash, never weld | Separate closed parts; levers and guards are overlapping boxes along a path |
| Round parts by lathe | One turned profile with the chamfers in it; flat shading keeps the kit's facets |
| Turn along the barrel | A tank lying on a gun, a nozzle or a bezel turns about X, not Z; a profile closed into a loop turns into a ring with a hole (a lens set inside a bezel, a nozzle with a glowing disc deep in it), where a capped cylinder would hide what is inside (Deadnight's `weapon_specs/_revolve.py`) |
| Far level from the same description | No chamfers, half the sides on round parts, small parts left out: 22-32 % of the held count. A turned part with rounded ends gets a far profile of its own: keeping every other point made a tank's two ends unlike. Look at the far level in a turntable beside the near one |
| One material per family | A small palette atlas, every face's UVs collapsed on its colour swatch, roughness 0.415, metallic 0.4 |
| Compare rebuilds by geometry | The glTF export's triangle order changes from run to run, so a rebuilt file never matches the old one byte for byte: compare nodes, vertex buffers and the triangle set, and commit only the files the change is for |
| Look at it | A turntable sheet beside two kit weapons at the same scale shows what numbers miss: the first pass had the right lengths and triangle counts, and still read thin |
| Chamfers cost on round parts | A 12-sided cylinder is 44 triangles bare and 92 chamfered, a box 12 and 44: chamfer the big parts that face the camera and leave collars, rings and small blocks bare; count on the first build ([Build scripts](../build-scripts.md#checks)) |
| Trim is a band, not a cap | A rim drawn as a slightly larger capped cylinder covers the face it trims; draw it as a band round the edge, then read the cells by area |
| A copied guard needs its frame | A trigger guard copied from another gun keeps its opening only if the frame above the trigger sits at the donor's height: 5-7 mm lower took Deadnight's MP5 and M4A1 from 0.95 to 0.83-0.86 of the finger; measure the fit after the first build |

## Palette cells in Godot {#palette-cells-in-godot}

Every face's UVs sit on the centre of one swatch of a G x G palette, so a shader or an emission texture can tell the
parts apart by colour cell with no extra texture. In Godot (the glTF flips V) **a face's cell is
`floor(UV.x * G) + G * floor(UV.y * G)`**, cell 0 the top-left swatch; in Blender it is
`floor(u * G) + G * floor((1 - v) * G)`. Check the formula on one known swatch: read the mesh's UVs in Godot and
sample the palette there (Deadnight #786 did it for its 4 x 4 weapon palette; a row taken from Blender's bottom-up
V lit nothing).
A swatch that must glow (an energy cell, a lamp) gets its own cell and is lit by an emission texture of the atlas's
layout, black but for that cell, on a copy of the material: no second material, no extra draw call. Append new
swatches at the end of the palette's list, so no older swatch moves and no model has to be rebuilt.

## What reads on a phone {#what-reads-on-a-phone}

From a shoulder camera in the aim pose every gun is a fist and a barrel tip: a weapon is recognised from the side,
at the hip, reloading and in other players' hands. A weapon is drawn at about `screen height / (2 d tan(fov / 2))`
pixels a metre; for a 60 degree vertical field of view and a landscape phone 390 logical pixels tall that is 130 px/m
for the player's own weapon (2.6 m away) and 42 px/m for a teammate 8 m away. Render the set flat black at those sizes
and look:

- At 42 px/m a pixel is 2.4 cm: trigger guards, lever loops, sights and screws vanish; drums, magazines, grips and
  barrel blocks stay. Deadnight's lever rifle and double shotgun were one shape there, and its revolver and flare gun
  differed only by colour.
- So give each weapon **one signature mass at least about 7 cm across in the game** (3 px at 42 px/m) that changes its
  side outline, make no two weapons of one class share an outline, give a colour mass of its own where outlines are
  close, and never put a weapon's identity in a part the far level drops.
- **A sleeve round a tube is not a mass.** Deadnight's pump shotgun (#796) first had its pump drawn just round the
  magazine tube, 6.4 cm deep in the drawing: at 42 px/m it was a bar and a stock, the double shotgun's outline. Deepened
  to 8.8 cm (8.8 x 1.3 x 0.8 = 9 cm in the game) it hangs below the tube as a block with a gap of bare tube behind it,
  and the outline is its own. A moving part that is the signature (a pump, a feed cover, a box) is drawn to the mass
  rule, not to the real part's size.

Deadnight's `tools/blender/render_weapon_plan.py --silhouette --px-per-m 42` draws it; the measured set is its
`docs/research/weapon-models.md`.

## Many weapons in parallel {#many-weapons-in-parallel}

When several agents build weapons at once, give each weapon its own module (Deadnight's
`tools/blender/weapon_specs/<id>.py`: its builders and one `SPEC` dict with the node pivots, sockets and ammunition,
loaded by the one build script) instead of entries in the build script's shared tables, and settle what they must
agree on before they start: the palette's new cells (added once, by the planner), the size rule, the budgets, each
weapon's signature and class. The game-side lists of models (tests, the grip solver) still take a line each: add yours
on a line of its own and merge main before pushing.

**A model before its hold.** The model batches land before the build issue adds the weapon to the catalogue and
writes its hold file, but the model still has to be seen in the hands. Film it through the night's own builder with a
hold made in the capture (Deadnight's `game/tests/captures/model_hands_sheet.gd`: a `WeaponHold` built from the plan's
numbers, handed to `PlayerAnimation` the way `equip` does, beside catalogue weapons equipped the normal way), never a
copy of the hold code. Solve the grip at the size the hold will use: the grip test compares each grip's `model_scale`
with its weapon's hold, so a hold written later at another size needs the grip solved again; say the size in the pull
request. A plan render that reads the sizes from the hold files takes the new models with their size given
(`render_weapon_plan.py --add id=row@model_scale`). Two parallel batches each wrote that capture and that flag under
the same names (Deadnight #816 and #818): before writing a tool a batch needs, look in the open pull requests of the
other batches for one.

## Budgets {#budgets}

Kit guns are 1.0-1.45k tris and melee 660-760. For a third-person web game, one held and world model at 1.5k and a far
level at 500 is enough. Deadnight's first ten came out at 432-1,172 tris and 108-374 for the far level (24-50 %
of the near count).
