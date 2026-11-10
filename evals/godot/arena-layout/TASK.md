+++
agent = "level-designer"
kind = "godot"
template = "3d-blank"
deliver = ["game/"]
read = [
  "engines/godot/map-review.md#0-before-the-walk",
  "engines/godot/map-review.md#7-collision-hygiene-out-of-bounds-and-skipped-doors",
  "engines/godot/navigation-in-tests.md#a-small-mesh-of-your-own",
  "engines/godot/project-conventions.md#rules",
]
+++

# Lay out a small arena for the dead to arrive in

`game/` in this folder is a new game made from the kit's 3D Blank template, with GdUnit4 installed. Lay out one arena
for a co-op, wave-based, third-person survival game: a 40 m square the players hold against the dead, who arrive from
four gates. Build it from the template's pieces (`res://world/blocks/proto_block.tscn`, a box, cylinder, ramp or
staircase made from one `size`, with collision) as a new scene, `res://world/arena/arena.tscn`, and prove its
layout with a test of your own. Do not change `main.tscn`. The template has no player: the check brings the real
body's numbers.

A layout is judged by numbers measured on the real thing, never by how it looks in a capture, so measure as you
design (a script of your own is fine, and so is a generator for the scene; `engines/godot/map-review.md` is the
checklist a review walks).

## The real body

A capsule 0.4 m in radius and 1.8 m tall, eyes at 1.6 m, chest at 1.0 m. It steps up 0.4 m, gets onto a block up to
1.1 m high from level ground by hopping, and falls off anything higher. The dead use the same body.

## What the scene holds

- **Root and floor.** A `Node3D` root. Everything the body can reach lies inside a 40 m square centred on the origin
  (`|x|` and `|z|` at most 20 m); the ground is at height 0.
- **One player spawn.** A `Marker3D` in the group `player_spawn`, standing on the ground with room for the capsule.
- **Four enemy gates.** `Marker3D` nodes in the group `enemy_gates`, each standing on ground the body can walk to from
  the spawn.
- **Cover.** Between 8 and 16 solid pieces in the group `cover`, each with its top 1.3 to 1.5 m above the ground (too
  high to hop, low enough to shoot over), at least 2 of them in each quarter of the arena (`x` and `z` each side of
  0).
- **One landmark.** A solid piece in the group `landmark`, its top at least 6 m above the ground, so a player knows
  where they are.
- **A navigation mesh.** A `NavigationRegion3D` with a baked `NavigationMesh` for an agent as large as the body, saved
  in the scene.

## What judges it

| Measure | Limit |
| --- | --- |
| `gds check layout game`, gdlint and gdformat (`gdtoolkit` 4.5.0) on every script outside `addons/`, a clean headless import | no problems, no `ERROR` |
| New test suites of your own (your tests and the template's all pass) | at least 1 |
| The arena scene loads; one spawn; four gates; one landmark; one baked navigation region | exactly as listed |
| Ground the body can walk on, from the spawn, by a flood fill with the real body (step, hop, fall, capsule clearance) | at least 600 m2 |
| Places the body can reach outside the 40 m square, and places at a drop into the void (a way out, a wall top to fall from) | 0 each |
| Cover pieces, their tops, per quarter | 8 to 16; 1.3 to 1.5 m; at least 2 |
| Gates: nearest to the spawn; nearest two apart; nearest to the middle along an axis | at least 12 m; 15 m; 14 m |
| Gates out of the spawn's sight (a ray at chest height) | at least 3 of 4 |
| Longest clear line at chest height along the four axes, from every walkable place | at most 30 m |
| Mean clear run at chest height | 6 to 14 m |
| Share of 600 seeded random pairs of places that see each other at chest height | 0.15 to 0.6 |
| Share of the ground the landmark's top is seen from (a ray from the eye) | at least 0.85 |
| Share of the ground within 0.6 m of the navigation mesh | at least 0.95 |

`gds eval check arena-layout <this folder>` runs all of them through the pinned Godot and prints the measured value
beside each limit, and the first place a limit is broken (the longest line, a gate the body cannot walk to).
