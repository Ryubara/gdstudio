+++
agent = "godot-engineer"
kind = "godot"
template = "3d-blank"
deliver = ["game/"]
read = [
  "engines/godot/project-conventions.md#rules",
  "engines/godot/gdscript.md#names-and-types",
  "engines/godot/test-speed.md#time-driven-values",
  "engines/godot/running-gdunit.md#command-line",
]

[limits]
min_scripts = 2
max_script_lines = 120
max_function_lines = 30
max_undocumented = 0
max_untyped = 0
max_hot_allocations = 0
min_test_cases = 6
+++

# Build a moving platform component in the 3D Blank template

`game/` in this folder is a new game made from the kit's 3D Blank template, with GdUnit4 installed. Build a moving
platform as a reusable component: a level designer drops the scene in a level, sets its stops and its tuning in the
inspector and it runs, with no code written. Build it the way the kit's project conventions say
(`engines/godot/project-conventions.md`) and prove it with your own tests. The template has no player: tests bring
their own body.

How it is built is judged as well as what it does: small typed scripts with one job each, a documented public surface,
the numbers in a resource and nothing allocated in a per-frame function.

## What a test outside your code relies on

By these names, all under `res://gameplay/platform/`:

- **The scene.** `moving_platform.tscn`, its root an `AnimatableBody3D` with `sync_to_physics` on, the script
  `moving_platform.gd` (`class_name MovingPlatform`), a `CollisionShape3D` and a visible mesh, in the group
  `moving_platforms`.
- **Its tuning.** `platform_tuning.gd` (`class_name PlatformTuning`, a `Resource`) with `@export var speed: float`
  (metres a second), `@export var pause_seconds: float` and `@export var mode: Mode`, where `enum Mode { PING_PONG,
  LOOP, ONCE }` is declared in `PlatformTuning` (so `PING_PONG` is 0, `LOOP` 1, `ONCE` 2); and `platform_tuning.tres`
  holding 2.0, 0.5 and `PING_PONG`.
- **The platform's inspector API.** On `MovingPlatform`: `@export var tuning: PlatformTuning`, `@export var stops:
  Array[Vector3]` (offsets from where the platform is placed; the placed position is stop 0, so stop `i` in the path
  is `stops[i - 1]` added to the start) and `@export var active: bool = true`. `stops` and `tuning` are read when the
  platform enters the tree.
- **Its signals and query.** `signal arrived(stop_index: int)`, emitted once each time it reaches a stop (index 0 is
  the start), and `signal finished`, emitted once when a `ONCE` platform reaches its last stop. `func is_moving() ->
  bool` is true only while it is travelling between stops (not while paused, finished or inactive).

## How it behaves

- It starts towards stop 1 the moment it enters the tree, if `active` and it has stops, and it travels each leg in a
  straight line at `speed`, stepping in `_physics_process` by the physics delta (so a test counts physics frames, not
  seconds). It lands exactly on a stop and never goes past it.
- At a stop it emits `arrived`, holds still for `pause_seconds` (physics time), then goes on. `PING_PONG` turns round
  at the last stop and back at the start (the start is a stop and emits `arrived(0)` too); `LOOP` goes from the last
  stop straight back to stop 0 without turning round; `ONCE` stops at the last stop and emits `finished`.
- `active = false` holds it still wherever it is; `true` carries on. With no stops or no tuning it does nothing and
  prints no error.
- A `CharacterBody3D` standing on it is carried along.
- In `main.tscn`'s prototype level there is at least one platform, in the group `moving_platforms`, with at least two
  stops, standing 0.3 to 3 m above the floor under its start, and it moves when the game runs.

## What judges it

| Measure | Limit |
| --- | --- |
| `gds check layout game` | no problems |
| gdlint and gdformat (`gdtoolkit` 4.5.0, the games' pin) on every script outside `addons/` | clean |
| A headless import of the project | no `ERROR` line |
| New test suites of your own, and test cases in them | at least 1 suite, at least 6 cases |
| Your tests and the template's, run headless with GdUnit4 | all pass |
| The eval's acceptance suite (kept outside your folder, copied in for the check) | all pass |
| Scripts you added: how many | at least 2 |
| Longest added script, in lines of code | at most 120 |
| Longest function in them, in lines of code | at most 30 |
| Public members (functions, signals, exports, enums) without a `##` doc comment, and scripts without a `##` description | 0 |
| Declarations without a type (variables, parameters, return types) | 0 |
| Allocations in `_process` or `_physics_process` (`.new(`, an array or dictionary literal, `str(`, a node list fetched, a lambda) | 0 |

`gds eval check moving-platform <this folder>` runs all of them through the pinned Godot. Work from the brief and the
conventions, not from the check's acceptance suite.
