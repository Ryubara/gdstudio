+++
agent = "godot-engineer"
kind = "godot"
template = "3d-blank"
deliver = ["game/"]
read = ["engines/godot/project-conventions.md#rules", "engines/godot/project-conventions.md#scripted-edits"]
+++

# Build a pickup feature in the 3D Blank template

`game/` in this folder is a new game made from the kit's 3D Blank template, with GdUnit4 installed. Add pickups that
a player collects for points, built the way the kit's project conventions say (`engines/godot/project-conventions.md`)
and proven by your own tests. The template has no player: tests bring their own body.

The parts a test outside your code relies on, by these names:

- **The pickup.** `res://gameplay/pickup/pickup.tscn`, its root an `Area3D` with the script `pickup.gd`
  (`class_name Pickup`), in the group `pickups`, with `signal collected(value: int)` and `@export var tuning:
  PickupTuning`. When a physics body in the group `player` enters it, it emits `collected` once with its value and
  leaves the tree. A body outside that group does nothing. It spins about its vertical axis at its tuned speed, the
  whole pickup or its visible part, so it reads as something to take.
- **Its tuning.** `res://gameplay/pickup/pickup_tuning.gd` (`class_name PickupTuning`, a `Resource`) with
  `@export var value: int` and `@export var spin_speed_deg: float`, and `res://gameplay/pickup/pickup_tuning.tres`
  holding 10 and 90.
- **The score.** In `main.tscn`, a node in the group `score` with `var score: int` and
  `signal score_changed(score: int)` that adds every pickup's value as it is collected, and a `Label` in the group
  `score_label` whose text ends with the current score (`Score: 20`).
- **The level.** At least five pickups in `main.tscn`'s prototype level, at least 2 m apart, each 0.3 to 2 m above the surface
  under it, none inside a wall or a block.

## What judges it

| Measure | Limit |
| --- | --- |
| `gds check layout game` | no problems |
| gdlint and gdformat (`gdtoolkit` 4.5.0, the games' pin) on every script outside `addons/` | clean |
| A headless import of the project | no `ERROR` line |
| New test suites of your own | at least one |
| Your tests and the template's, run headless with GdUnit4 | all pass |
| The eval's acceptance suite (kept outside your folder, copied in for the check) | all pass |

`gds eval check pickup-feature <this folder>` runs all of them through the pinned Godot. Work from the brief and the
conventions, not from the check's acceptance suite.
