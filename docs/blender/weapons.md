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
of the character holding it beside the kit one. A kit hold puts the weapon in the hand, but not the fingers on it:
for that, solve each weapon's grip from its own sockets ([Hands on the weapon](#hands-on-the-weapon)).

**Hand guns.** The kit file's Revolver copy is rescaled like the AK's, so use the Shotgun hold for every gun, and size
one-handed guns against the hand ([Hands on the weapon](#hands-on-the-weapon),
[lesson](../lessons/2026-11-01-a-chibi-hand-needs-guns-sized-for-it.md)). Sweep a bent bar as one tube; boxes give a
bend a saw-tooth edge.

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

**Tools swung by a clip.** A tool that only an action clip swings (Deadnight's repair hammer, #326) takes the melee
hold and then a turn chosen from the clip itself: trace the striking face through one loop for a few turns about the
handle and tips in the swing plane, and keep the one whose face points along the blow and toward the target at the
lowest point. For the Soldier's `Repair_Board`, the bat's hold already faced the board; a 20-degree tip in the swing
plane squared the face to the downward blow. Draw a small tool large (the kit's knife is 1.4 m, longer than its
shovel), and size it in the hand for the fist: a hammer at the size rule's 0.29 m vanished in the Soldier's chibi
fist, at 0.45 m only the head showed, at 0.50 m it read. Give the tool its striking point as a node (`Face`, -Z out
of the face), as a gun carries its `Muzzle`.

## Hands on the weapon

The kit's clips never move the fingers: every clip holds the same fist, made for the kit's own guns, so copying a kit
hold puts every finger through or off any other weapon (Deadnight measured 8-42 mm into the gun and 20-80 mm off it on
all of its guns, [Deadnight #460](https://github.com/Ryubara/deadnight/issues/460)). Give each weapon its grip from
data instead:

- **Hand sockets in the model**, placed like the `Muzzle`: `Grip` (the right hand's handle, at its centre where the
  middle finger wraps; local +Z up the handle toward the index finger, local +Y the way the straight fingers point,
  which on a pistol grip is along the barrel), `Trigger` (the middle of the trigger's front face) and `Support` (the
  left hand's handle: the fore-end's rear, where a chibi arm reaches, or a vertical foregrip).
- **A solver closes the hand on them** in the hand bone's space, so the grip holds in every clip: lay the socket on
  the line across the knuckles, slide a gun until the trigger is level with the index knuckle, push it to the palm,
  turn it up to 30 degrees about the handle and slide it along the fingers until the index finger reaches the trigger,
  then bend every finger within joint limits to the bend that brings its tip 1 mm from the surface without going in.
  Measure the skinned mesh against the weapon's triangles, inside counted per closed piece (a kitbashed gun is many
  overlapping closed parts, so one parity test over the whole mesh is wrong).
- **The palm is four bones from the wrist** (`Index1`, `Middle1`, `Pinky1`, `Thumb1`). An IK that turns only the bone
  the weapon rides (`Index1.R`) leaves the other three with the forearm and tears the palm: turn them with it.
- **Check the arm reaches.** A chibi arm is short (the Soldier's is 0.66 m in the game): a solved left-hand grip is
  only right if the IK can put the hand there. Put the support at the fore-end's rear and turn the chest 20-30 degrees
  (left shoulder forward) for two-handed guns; a clamped IK leaves the hand short, inside the stock.
- **Size against the hand, not only the body.** The kit Soldier's fist is about 2.3 times a real one and his finger 3
  times, on a body at 0.8: the kit draws its guns about 1.33 times real for that (its AK beside the Soldier). Check a
  pistol grip against the three fingers under the trigger finger (about 1.0) and the guard's opening against the
  finger (at least about 0.9) before solving, and scale the weapon, never the hand.
- **Every view of the held weapon uses the same builder.** The night and any screen that shows the soldier with a
  weapon (the menu's stage, a wardrobe, a lobby) put it in the hand through one function (Deadnight's `HeldWeapon`:
  the weapon's own hold, the grip file's place, the arms' IK, the fingers). A view with its own copy keeps the old
  fist the day the grips are solved ([Deadnight #621](https://github.com/Ryubara/deadnight/issues/621),
  [lesson](../lessons/2026-11-02-the-menu-soldier-copied-the-hold-code-and-missed-the-grips.md)); test it by measuring
  the hands against the weapon on that view with the night's limits.

Deadnight's tools: `build_weapons.py` (`GRIPS`, `TRIGGERS`, `SUPPORTS`), `game/tests/art/solve_grips.gd`,
`HandContact`, `WeaponFit`, and the runtime `HandGripPose`; the design is its `docs/design/animation.md` "Grips".

## Moving parts and a reload's ammunition

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
  fingers, their tips 0.25 bone units out), as the [held prop lesson](../lessons/2026-11-02-a-held-prop-passed-its-tests-and-showed-nothing-in-the-fist.md)
  found for the grenade.
- Godot's axes for a gun drawn along Blender -X: the muzzle is -X, up +Y and **the gun's left is +Z** (Blender -Y). A
  break-open's muzzle drops with a positive turn about +Z; a cylinder swings out to the left with a positive turn about
  +X about a crane under its left side.

Deadnight's tools: `build_weapons.py` (`NODES`, `AMMO`); the motion is its `docs/design/animation.md` "Reloading".

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
