# Weapons in the Toon Shooter style

How to build original weapons that sit beside the Quaternius Toon Shooter kit (CC0) and drop into its characters'
hands. Learned on Deadnight's first four weapons ([Deadnight #16](https://github.com/Ryubara/deadnight/issues/16));
the scripts are in Deadnight's `tools/blender/` (`build_weapons.py`, `weaponlib.py`, `render_turntable.py`,
`render_hold.py`), and the game's numbers are in its style bible and `docs/research/weapons.md`.

## Axes, origin and the hold

The kit characters carry every weapon as a mesh parented to the right hand's `Index1.R` bone, origin on the bone.
The copy in the hand uses the standalone file's own mesh data, so a weapon that follows the kit file's frame drops into
the same hold:

| Kind | Axes (Blender; the glTF is the same with Y up) | Origin |
| --- | --- | --- |
| Guns | muzzle along -X, up +Z, thin across Y | the grip, behind the trigger (72-89 % along from the muzzle) |
| Melee | standing up along +Z | the grip, near the handle end (13-40 % of the length) |

Copy the hold from a kit weapon that is unit-scale in the character file: the **Shotgun** for long guns, the
**Shovel** for melee (offset about 2 mm from the bone). The AK and Sniper copies carry rescaled mesh data (object
scale 0.21-0.42), so their transform does not carry over to a weapon at true size. Prove each new weapon with a render
of the character holding it beside the kit one.

**Hand guns and the chibi fist.** The kit characters' hands are two to three times real size on a body at 0.8, so a
one-handed gun sized against the body vanishes in the fist (only the barrel shows). Measure the weapon against the
hand that holds it, give one-handed guns a size exception (like the repair hammer, about 1.6x), and use the Shotgun
hold for every gun: the kit file's Revolver copy is rescaled like the AK's. Sweep a bent bar as one tube; boxes give
a bend a saw-tooth edge ([lesson](../lessons/2026-11-02-hand-guns-disappeared-into-a-chibi-fist.md)).

**Thrown weapons.** The kit characters carry no kit grenade, so a grenade has no kit hold to copy. Model it standing up
along +Z with the origin in the body's centre (the fist), and give each moving part its own node, origin at its
pivot (Deadnight's `Pin` slides out, its `Spoon` swings off its hinge). In Godot the gun hold turned 90 degrees about
the weapon's X (`HOLD_GUN * Basis(Vector3.RIGHT, PI / 2)`) stands it fuze up in the fist; the turn that looks right
in a Blender preview against the kit copy is a different one, so choose the hold from candidates rendered in Godot.

## Attachment points

Where an effect or a hand meets a weapon is part of the model, so **attachment points are the modeller's job**: whoever
builds a weapon places them in Blender, and gameplay code reads them instead of typing offsets from the body.

- **Every firearm carries an empty named `Muzzle`** at the centre of the barrel's open end, parented to the weapon's
  root, with **-Z pointing out of the barrel** (Godot's forward). In Blender that is the empty's local **+Y**: the glTF
  export turns Blender +Y into -Z. For a gun along Blender -X, turn the empty 90 degrees about Z
  (`rotation_euler = (0, 0, pi/2)`); it arrives in Godot turned 90 degrees about Y, -Z along the barrel.
- **Two barrels side by side get one `Muzzle` centred between them**, at the barrels' end face.
- **Melee weapons and grenades get none.**
- **Every level of detail carries it at the same point**, so the flash does not jump when the far level swaps in.
- **A test proves it:** load each firearm's file, find `Muzzle`, check it sits within 1 cm of the bounds' front face
  along the barrel and points along it. Deadnight's is `game/tests/art/test_weapon_muzzle.gd`, built by its
  `build_weapons.py` (`MUZZLES`) and drawn by `render_muzzle.py`.

## Building by script

| Lesson | Detail |
| --- | --- |
| Draw real, then fatten | Drawn at real proportions, a gun looks spindly beside the kit. Scale every part 1.4-1.5x across its length before chamfering to get the kit's chunky cross-sections |
| Big receiver, shallow stock | The kit's guns read as a large grey block; keep the stock shallow with a slanted butt, or the fattening turns it into a wedge |
| Chamfer only the big parts | A one-segment chamfer (about 17 mm at kit scale) costs a box 44 tris instead of 12; leave screws, pins, sights and lever segments hard |
| Kitbash, never weld | Separate closed parts; levers and guards are overlapping boxes along a path |
| Round parts by lathe | One turned profile with the chamfers in it; flat shading keeps the kit's facets |
| Far level from the same description | No chamfers, half the sides on round parts, small parts left out: 22-32 % of the held count |
| One material per family | A small palette atlas, every face's UVs collapsed on its colour swatch, roughness 0.415, metallic 0.4 |
| Compare rebuilds by geometry | The glTF export's triangle order changes from run to run, so a rebuilt file never matches the old one byte for byte: compare nodes, vertex buffers and the triangle set, and commit only the files the change is for |
| Look at it | A turntable sheet beside two kit weapons at the same scale shows what numbers miss: the first pass had the right lengths and triangle counts, and still read thin |

## Budgets

Kit guns are 1.0-1.45k tris and melee 660-760. For a third-person web game, one held and world model at 1.5k and a far
level at 500 is enough. Deadnight's four came out at 432-1,092 tris and 108-352 for the far level.
