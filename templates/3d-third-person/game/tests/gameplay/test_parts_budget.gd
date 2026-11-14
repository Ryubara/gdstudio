# On the clock: the frame budget times ten walking characters against a calibration loop.
# What the template's parts may cost (gdstudio #926), held in CI: counts tight, time loose
# (docs/engines/godot/performance-budgets.md#budgets-counts-tight-time-loose). A living dressed
# character carries no ragdoll bones, a still target and a door nobody nears cost no query, and
# ten walking characters stay under a frame budget measured as a share of a fixed loop of script
# run in the same process, in the same frames, so a slow runner and a busy machine scale both.
# `tools/bench/parts_cost_bench.tscn` prints the numbers this budget was set from.
extends GdUnitTestSuite

const CHARACTER := "res://gameplay/character/character_dressed.tscn"
## A living dressed character: 62 nodes and 17 physics bodies before #926 (16 bones, their shapes
## and their simulator were made at the spawn), 29 and 1 after; the hit zones (#876) add 13 nodes
## and their body; the weapon system (#887) adds 4: the `Loadout` and the weapon's empty click,
## reload and draw sounds (idle players, no processing until one plays); the pistol's hold (#1001)
## adds 6: `WeaponHold`, its three skeleton modifiers (5.6 microseconds a character a frame
## carried), the `SupportHand` marker and the model's `Support` socket; its `Health` node (#925) 1;
## the reload's `MagazineHand` marker (#1031) 1, a `Marker3D` that is never processed; the
## `MinimapHeading` (#1047) 1, a plain `Node` read only when a minimap draws its arrow; the
## `NoiseMaker` (#966) 1, which looks at the body's movement every 6th tick; the `AimLayer` (#1253)
## 2, the node and its skeleton modifier (inactive until the character aims). The count takes in the
## empty, inactive `PhysicalBoneSimulator3D` every `Skeleton3D` makes as an internal child when it
## enters the tree (the engine's compatibility one, which `find_children` lists), not the walker
## the test adds. A character whose skeleton made the pool's sets (the first of a game) kept its
## `RagdollDrawing` after handing them over, one node more alone than in the full run (#1210).
## The prototype body (kit #1187) has 3 more than the Quaternius female it replaced: three meshes
## (its levels of detail) where she had one, and the `MannequinTwist` modifier. The aim layer's
## `AimHeadModifier` (kit #1334) is one more. The reload's new magazine (#1052) adds 2: a
## `BoneAttachment3D` on the left hand and its mesh, hidden but through a reload (the old
## magazine's body is made at the first reload, not at the spawn).
## The melee blow (#1254) adds 1: the weapon's `MeleeSound`, an idle player like the other three.
## The momentum blend (#1158) adds 1: `MomentumBlend`, the skeleton's first modifier.
## The slide's rack (#1337) adds 2: the hold's `HoldRackArm` and `HoldRackFingers` modifiers,
## inactive but through the rack after an empty reload. The hold's `HandFloor` (#1356) adds 1, a
## modifier inactive unless the body lies and aims. The aim layer's `AimUprightModifier` (kit #1351)
## adds 1, inactive until the fists aim. The peek lean (#1400) adds 3: the body's `PeekShape`,
## disabled unless it leans, the `PeekLayer` and its `PeekModifier`, idle while upright. The left
## shoulder (#1435) adds 3: `LeftShoulder` and its `LeftShoulderCross` and `LeftShoulderArm`,
## inactive unless the pistol aims on a left lean. The shot hull (kit #1431) adds 2, `ShotHull`
## and its `Shape`, and 1 body: a static capsule a ray meets before it asks the parts.
const NODES_ALIVE := 77
const BODIES_ALIVE := 3
const CROWD := 10
## Frames a window times, and windows a measure takes the best of.
const FRAMES := 90
const WINDOWS := 3
## Ten walking characters' frame (their scripts, the animation and the physics step, less the same
## arena's frame before they came), as a multiple of the calibration loop below, run once at the
## end of every measured frame: medians of each window's frames and loops, the lowest of the
## windows' ratios. Both sides are timed in the same frames, so a moment the machine takes the
## processor away moves both (#1324), and a window the runner slowed for its own reasons is
## outvoted by the other two; a frame twice as slow is twice in every window.
## The limits sit between the highest ratio seen and twice the lowest, by system, as the AI cost
## gate's (kit docs/engines/godot/running-gdunit.md#timing-gates; #1451): the same code reads
## differently on each of GitHub's processor models (one model's runs agree within a few
## percent, the models 1.5 times apart), and Linux and Windows build it to different speeds.
## Rulers of animation, physics and spread-out memory work were timed beside the loop over 100 CI
## runs and none followed the frame better (third-person/parts-cost.md#parts-cost). Linux: 150
## soak runs on five processor models read 1.26 to 1.78 (one window of 450 read 2.24), twice as
## slow 2.54 at the least; Windows: 10 desktop runs beside 9 to 11 other Godot processes, 1.54 to
## 1.83, twice as slow 3.07 at the least.
const FRAME_RATIO_LIMITS := {"Linux": 2.2, "Windows": 2.4}
## How many times its work the teeth case's frame costs.
const SLOW_FACTOR := 2.0

var _arena: Node3D
var _work: Array[float] = []
var _loop: Array[float] = []
var _tick_start := -1
var _factor := 1.0


func before_test() -> void:
	_arena = auto_free(Node3D.new())
	add_child(_arena)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	_arena.add_child(floor_body)


func _spawn(index: int) -> Character:
	var body := (load(CHARACTER) as PackedScene).instantiate() as Character
	var walker := Walker.new()
	walker.name = "Walker"
	body.add_child(walker)
	body.controller = walker
	body.position = Vector3((index % 5) * 3.0 - 6.0, 0.0, floorf(index / 5.0) * 3.0 - 3.0)
	_arena.add_child(body)
	return body


func _bodies(node: Node) -> int:
	var found := 1 if node is PhysicsBody3D else 0
	for child in node.get_children():
		found += _bodies(child)
	return found


func test_a_living_character_carries_no_ragdoll_until_it_dies() -> void:
	# An empty pool, as in a game's first seconds: this character's skeleton makes its sets, run
	# alone or after suites that filled it.
	var pool := RagdollPool.instance(get_tree())
	pool.clear()
	var body := _spawn(0)
	await InputSim.ticks(get_tree(), 30)
	assert_int(pool.parked()).is_greater(0)
	# The body and everything under it, internal children included, less the walker the test added.
	var nodes := body.find_children("*", "", true, false)
	nodes.erase(body.get_node("Walker"))
	var drawings := nodes.filter(func(node: Node) -> bool: return node is RagdollDrawing)
	assert_int(drawings.size()).is_equal(0)
	assert_int(nodes.size()).is_equal(NODES_ALIVE)
	assert_int(_bodies(body)).is_equal(BODIES_ALIVE)
	body.die()
	await InputSim.ticks(get_tree(), 2)
	assert_int(_bodies(body)).is_equal(BODIES_ALIVE + CharacterRagdoll.BODIES.size())


func test_a_standing_target_is_not_processed_until_it_is_hit() -> void:
	var target := (load("res://gameplay/target/target.tscn") as PackedScene).instantiate() as Target
	_arena.add_child(target)
	await InputSim.ticks(get_tree(), 2)
	assert_bool(target.is_processing()).is_false()
	Health.of(target).apply(HitRecord.blow(1.0))
	assert_bool(target.is_processing()).is_true()
	await InputSim.ticks(get_tree(), 30)
	assert_float(target.tilt()).is_equal(target.drop_angle)
	# Down, it waits to stand up; once up it rests again.
	assert_bool(target.is_processing()).is_true()
	await InputSim.ticks(get_tree(), int((target.reset_time + target.drop_time) * 60.0) + 10)
	assert_bool(target.is_down()).is_false()
	assert_float(target.tilt()).is_equal(0.0)
	assert_bool(target.is_processing()).is_false()


func test_ten_walking_characters_stay_under_the_frame_budget() -> void:
	var row := await _measure_crowd(1.0)
	print("PARTS_BUDGET\n" + JSON.stringify(row))
	var limit := _frame_limit()
	(
		assert_float(row.ratio)
		. override_failure_message(
			(
				"10 walking characters took %.3f ms a frame, %.2f times the ruler (limit %.2f): %s"
				% [row.frame_ms, row.ratio, limit, JSON.stringify(row)]
			)
		)
		. is_less(limit)
	)


func test_ten_characters_twice_as_slow_fail_the_frame_budget() -> void:
	var row := await _measure_crowd(SLOW_FACTOR)
	print("PARTS_BUDGET_SLOW\n" + JSON.stringify(row))
	(
		assert_float(row.ratio)
		. override_failure_message(
			(
				"10 characters twice as slow passed the frame budget at %.2f (limit %.2f): %s"
				% [row.ratio, _frame_limit(), JSON.stringify(row)]
			)
		)
		. is_greater_equal(_frame_limit())
	)


## This system's frame limit (Linux's on a system with none of its own).
static func _frame_limit() -> float:
	return FRAME_RATIO_LIMITS.get(OS.get_name(), FRAME_RATIO_LIMITS["Linux"])


## The empty arena's frame, then ten walkers' in `WINDOWS` windows, each beside the loop; `factor`
## makes each of the walkers' frames cost that many times itself (the teeth case).
func _measure_crowd(factor: float) -> Dictionary:
	await InputSim.ticks(get_tree(), 10)
	_factor = 1.0
	await _measure_frames()
	var base := _median(_work)
	for index in CROWD:
		_spawn(index)
	await InputSim.ticks(get_tree(), 60)
	_factor = factor
	var ratios: Array[float] = []
	var frames: Array[float] = []
	var loops: Array[float] = []
	for _window in WINDOWS:
		await _measure_frames()
		var frame := maxf(_median(_work) - base, 0.0)
		var loop := maxf(_median(_loop), 0.001)
		frames.append(snappedf(frame, 0.001))
		loops.append(snappedf(loop, 0.001))
		ratios.append(snappedf(frame / loop, 0.001))
	var best := ratios.find(ratios.min())
	return {
		"system": OS.get_name(),
		"ratio": ratios[best],
		"frame_ms": frames[best],
		"loop_ms": loops[best],
		"base_ms": snappedf(base, 0.001),
		"ratios": ratios,
		"frames_ms": frames,
		"loops_ms": loops,
	}


# Times each frame's work, from its first physics tick to the last node processed, then runs the
# calibration loop once in the same frame: both lists see the same load.
func _measure_frames() -> void:
	_work.clear()
	_loop.clear()
	_tick_start = -1
	var end := FrameEnd.new()
	add_child(end)
	get_tree().physics_frame.connect(_on_physics_frame)
	end.done.connect(_on_frame_end)
	for _i in FRAMES:
		await get_tree().process_frame
	get_tree().physics_frame.disconnect(_on_physics_frame)
	end.done.disconnect(_on_frame_end)
	end.queue_free()


func _median(values: Array[float]) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _on_physics_frame() -> void:
	if _tick_start < 0:
		_tick_start = Time.get_ticks_usec()


func _on_frame_end() -> void:
	if _tick_start < 0:
		return
	var spent := Time.get_ticks_usec() - _tick_start
	if _factor > 1.0:
		var until := _tick_start + int(spent * _factor)
		while Time.get_ticks_usec() < until:
			pass
		spent = Time.get_ticks_usec() - _tick_start
	_work.append(spent / 1000.0)
	_tick_start = -1
	_loop.append(_calibration_ms())


# A fixed piece of script of the kind the parts run (arithmetic, vectors, an array and a
# dictionary), in milliseconds.
func _calibration_ms() -> float:
	var start := Time.get_ticks_usec()
	var sum := Vector3.ZERO
	var names: Dictionary[int, float] = {}
	var values: Array[float] = []
	for index in 10000:
		var at := Vector3(index, index * 0.5, -index).normalized()
		sum += at * 0.01
		values.append(at.length())
		names[index % 64] = sum.x
	return (Time.get_ticks_usec() - start) / 1000.0


## Processed after every other node: says when a frame's processing is over.
class FrameEnd:
	extends Node
	signal done

	func _init() -> void:
		process_priority = 1 << 30

	func _process(_delta: float) -> void:
		done.emit()


## Walks a slow circle: a stand-in for an AI's controller.
class Walker:
	extends CharacterController

	var _turn := 0.0

	func sample() -> PlayerCommand:
		_command.clear()
		_turn += 0.01
		_command.move = Vector2(0.0, 1.0)
		_command.yaw = _turn
		return _command
