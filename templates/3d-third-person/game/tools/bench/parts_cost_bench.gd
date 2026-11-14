extends Node
## What the template's parts cost a frame (gdstudio #926): a crowd of dressed characters (the
## body, the animation, the footsteps and the ragdoll, what an AI character reuses), idle and
## walking, and the world parts a level holds many of (pickups, targets, doors, weapons).
##
## Four sections, one line of JSON:
## - `crowd`: 1, 10, 25 and 50 characters on a flat floor, idle then walking a circle; the median
##   frame in milliseconds (`*_ms`: wall time from one frame to the next, desktop only; `*_work_ms`:
##   from the frame's first physics tick to the last node processed, which a browser reads too),
##   the nodes and the physics bodies each character adds, and what spawning one cost.
## - `parts`: 25 walking characters with each part's processing turned off and called here by
##   hand, timed apart: microseconds a character a frame for the body's step, the animation script,
##   the animation tree's own advance, the skeleton's update after it (what the engine defers to
##   the end of the frame, outside `*_work_ms`: the bones' global poses, the skeleton's modifiers
##   and the skin; gdstudio #1438), the footsteps, the ragdoll, every other node of the character
##   that processes (`others`, by name) and the physics tick after the scripts (`physics`: the
##   rest of the tick, the physics server's step among it, less an empty arena's). `modifiers`
##   splits the skeleton's update: each active modifier's share, read as the update's cost with
##   that one switched off, in turns with all of them on.
## - `death`: what the first death of a character costs (it takes a set of the ragdoll's bones from
##   the `RagdollPool`, or makes them) and a later one, in milliseconds; `death_male` the same on
##   the male mannequin, whose first death takes a set the pool made on the female and fits it.
## - `world`: 100 of one world part at a time against an empty arena (the median frame's growth,
##   in microseconds a part, by wall and by work) and how many of their nodes process each frame.
##
## Run it headless on the desktop (one physics tick a frame): `godot --headless --fixed-fps 60
## --path game res://tools/bench/parts_cost_bench.tscn` and in a browser from the web export `gds
## template bench-web 3d-third-person parts_cost_bench` makes (kit
## docs/engines/godot/web-probes.md#bench-web) (`tools/bench/parts_cost_bench.py`). On the web it
## puts the line in `window.__parts_cost_bench`. `tests/gameplay/test_parts_budget.gd` holds the
## counts in CI.

const CROWD: Array[int] = [1, 10, 25, 50]
const PART_CROWD := 25
const WORLD_COUNT := 100
const WARM_FRAMES := 60
const FRAMES := 300
## The parts the bench switches off and calls by hand; any other node of the character that
## processes is timed under `others`.
const HAND_PARTS: Array[String] = ["Animation", "Footsteps", "Ragdoll"]
## Rounds and frames of the modifiers' split (each round: all on, then each one off in turn).
const MODIFIER_ROUNDS := 3
const MODIFIER_FRAMES := 60
const CHARACTER := "res://gameplay/character/character_dressed.tscn"
const MALE := CharacterBodies.MALE
const WORLD_PARTS := {
	"pickup": "res://gameplay/pickup/pickup.tscn",
	"target": "res://gameplay/target/target.tscn",
	"door": "res://gameplay/door/door.tscn",
	"weapon": "res://gameplay/weapon/weapon.tscn",
}

var _arena: Node3D
var _works: Array[float] = []
var _tick_start := -1
var _frame_end: FrameEnd
var _sections: Array[String] = []


## Walks a slow circle when `walking` is on, else asks for nothing: a stand-in for an AI's
## controller that costs next to nothing itself.
## Processed after every other node: says when a frame's processing is over.
class FrameEnd:
	extends Node
	signal done

	func _init() -> void:
		process_priority = 1 << 30

	func _process(_delta: float) -> void:
		done.emit()


class Walker:
	extends CharacterController
	var walking := false
	var _turn := 0.0

	func sample() -> PlayerCommand:
		_command.clear()
		if walking:
			_turn += 0.01
			_command.move = Vector2(0.0, 1.0)
			_command.yaw = _turn
		return _command


func _ready() -> void:
	# Made here, not where it is declared: a script that loads the bench and frees it unrun (the
	# tools checks) would leave a node that never joined the tree.
	_frame_end = FrameEnd.new()
	add_child(_frame_end)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	add_child(floor_body)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 30.0, 40.0)
	camera.rotation.x = deg_to_rad(-35.0)
	add_child(camera)
	camera.make_current()
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		_sections.append(arg.trim_prefix("--"))
	var report := {"frames": FRAMES, "crowd": [], "parts": {}, "world": []}
	if _wants("crowd"):
		for count in CROWD:
			report.crowd.append(await _crowd(count))
	if _wants("parts"):
		report.parts = await _parts(PART_CROWD)
	if _wants("death"):
		report.death = await _death(false)
		report.death_male = await _death(true)
	if _wants("world"):
		var empty := await _empty_frame()
		for kind: String in WORLD_PARTS:
			report.world.append(await _world(kind, empty))
		report.empty_frame_ms = empty.wall
		report.empty_work_ms = empty.work
	var line := JSON.stringify(report)
	print("PARTS_COST_BENCH ", line)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__parts_cost_bench = %s;" % line, true)
	else:
		get_tree().quit()


# The sections to run: all of them, or on the desktop those named after `--` (`-- parts`,
# `-- crowd world`).
func _wants(section: String) -> bool:
	return _sections.is_empty() or _sections.has(section)


func _crowd(count: int) -> Dictionary:
	_new_arena()
	var nodes_before := get_tree().get_node_count()
	var bodies_before := _physics_bodies(get_tree().root)
	var start := Time.get_ticks_usec()
	var walkers := _spawn(count)
	var spawn_ms := (Time.get_ticks_usec() - start) / 1000.0
	var nodes := get_tree().get_node_count() - nodes_before
	var bodies := _physics_bodies(get_tree().root) - bodies_before
	var idle := await _median_frame()
	for walker in walkers:
		walker.walking = true
	var walking := await _median_frame()
	_arena.free()
	return {
		"characters": count,
		"idle_ms": idle.wall,
		"walking_ms": walking.wall,
		"idle_work_ms": idle.work,
		"walking_work_ms": walking.work,
		"nodes_each": float(nodes) / count,
		"bodies_each": float(bodies) / count,
		"spawn_ms_each": spawn_ms / count,
	}


# Microseconds a character a frame for each part, its own processing off and called here.
func _parts(count: int) -> Dictionary:
	_new_arena()
	# The physics tick's rest with nobody in the arena, taken off the crowd's below.
	var empty_rest := await _hand_frames([], [], {}, {})
	var walkers := _spawn(count)
	var bodies: Array[Character] = []
	var others: Array[Node] = []
	var hows := {}
	for walker in walkers:
		walker.walking = true
		var body := walker.get_parent() as Character
		bodies.append(body)
		body.set_physics_process(false)
		for part_name in HAND_PARTS:
			var part := body.get_node(part_name)
			part.set_process(false)
			part.set_physics_process(false)
		var tree := body.get_node("AnimationTree") as AnimationTree
		tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var skeleton := (body.model as CharacterModel).skeleton()
		skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
		for node in body.find_children("*", "", true, false):
			if node == walker or not (node.is_processing() or node.is_physics_processing()):
				continue
			hows[node] = {
				"name": String(node.name),
				"physics": node.is_physics_processing() and node.has_method(&"_physics_process"),
				"idle": node.is_processing() and node.has_method(&"_process"),
			}
			node.set_process(false)
			node.set_physics_process(false)
			others.append(node)
	var spent := {"step": 0, "animation": 0, "tree": 0, "skeleton": 0, "footsteps": 0, "ragdoll": 0}
	var other_spent := {}
	var rest := await _hand_frames(bodies, others, hows, spent, other_spent)
	var modifiers := await _modifier_split(bodies)
	_arena.free()
	var result := {"characters": count}
	for key: String in spent:
		result[key + "_us"] = float(spent[key]) / (FRAMES * count)
	result.physics_us = maxf(rest - empty_rest, 0.0) / count
	var other_us := {}
	for key: String in other_spent:
		other_us[key] = float(other_spent[key]) / (FRAMES * count)
	result.others = other_us
	result.modifiers = modifiers
	return result


# Steps `bodies` by hand for the warm-up and the measured frames, adding each part's microseconds
# to `spent` and each other processing node's, by name, to `other_spent`, and returns the median
# of the physics tick's rest: from the last part called to the frame's processing (the tick's
# deferred calls and the physics server's step), in microseconds.
func _hand_frames(
	bodies: Array[Character],
	others: Array[Node],
	hows: Dictionary,
	spent: Dictionary,
	other_spent: Dictionary = {},
) -> float:
	var rests: Array[float] = []
	for frame in WARM_FRAMES + FRAMES:
		await get_tree().physics_frame
		var delta := get_physics_process_delta_time()
		var counts := frame >= WARM_FRAMES
		var at := Time.get_ticks_usec()
		if not bodies.is_empty():
			at = _step_parts(bodies, delta, spent, counts, at)
		for node in others:
			var how: Dictionary = hows[node]
			if how.physics:
				node._physics_process(delta)
			if how.idle:
				node._process(delta)
			var now := Time.get_ticks_usec()
			if counts:
				other_spent[how.name] = other_spent.get(how.name, 0) + now - at
			at = now
		await get_tree().process_frame
		if counts:
			rests.append(float(Time.get_ticks_usec() - at))
	rests.sort()
	return rests[rests.size() / 2]


func _step_parts(
	bodies: Array[Character], delta: float, spent: Dictionary, counts: bool, at: int
) -> int:
	for body in bodies:
		body._physics_process(delta)
	at = _add(spent, "step", at, counts)
	for body in bodies:
		body.get_node("Animation")._physics_process(delta)
		body.get_node("Animation")._process(delta)
	at = _add(spent, "animation", at, counts)
	for body in bodies:
		(body.get_node("AnimationTree") as AnimationTree).advance(delta)
	at = _add(spent, "tree", at, counts)
	# The skeleton's deferred update, here instead of at the end of the frame.
	for body in bodies:
		_update_skeleton((body.model as CharacterModel).skeleton(), delta)
	at = _add(spent, "skeleton", at, counts)
	for body in bodies:
		body.get_node("Footsteps")._process(delta)
	at = _add(spent, "footsteps", at, counts)
	for body in bodies:
		body.get_node("Ragdoll")._physics_process(delta)
		body.get_node("Ragdoll")._process(delta)
	return _add(spent, "ragdoll", at, counts)


# What the engine does at the end of a frame for a skeleton whose bones moved: the modifiers in
# turn, the bones' global poses and the skin's transforms (`Skeleton3D`'s update notification).
static func _update_skeleton(skeleton: Skeleton3D, delta: float) -> void:
	skeleton.advance(delta)
	skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)


# Each active modifier's share of the skeleton's update, microseconds a character a frame: the
# update with all of them on less the update with that one off, in turns, the lowest of the rounds.
func _modifier_split(bodies: Array[Character]) -> Dictionary:
	var names: Array[String] = []
	for node in (bodies[0].model as CharacterModel).skeleton().get_children(true):
		var modifier := node as SkeletonModifier3D
		if modifier != null and modifier.active:
			names.append(_modifier_name(modifier))
	var best := {}
	for _round in MODIFIER_ROUNDS:
		var all_on := await _skeleton_frames(bodies, "")
		for modifier_name in names:
			var without := await _skeleton_frames(bodies, modifier_name)
			best[modifier_name] = minf(best.get(modifier_name, INF), all_on - without)
	for modifier_name: String in best:
		best[modifier_name] = maxf(best[modifier_name], 0.0)
	return best


# The skeleton's update a character a frame, microseconds, with the modifier named `off` switched
# off (none with `""`). The bodies walk and their trees advance as before, untimed.
func _skeleton_frames(bodies: Array[Character], off: String) -> float:
	var switched: Array[SkeletonModifier3D] = []
	for body in bodies:
		for node in (body.model as CharacterModel).skeleton().get_children(true):
			var modifier := node as SkeletonModifier3D
			if modifier != null and modifier.active and _modifier_name(modifier) == off:
				modifier.active = false
				switched.append(modifier)
	var spent := 0
	for frame in WARM_FRAMES / 6 + MODIFIER_FRAMES:
		await get_tree().physics_frame
		var delta := get_physics_process_delta_time()
		for body in bodies:
			body._physics_process(delta)
			body.get_node("Animation")._process(delta)
			(body.get_node("AnimationTree") as AnimationTree).advance(delta)
		var at := Time.get_ticks_usec()
		for body in bodies:
			_update_skeleton((body.model as CharacterModel).skeleton(), delta)
		if frame >= WARM_FRAMES / 6:
			spent += Time.get_ticks_usec() - at
	for modifier in switched:
		modifier.active = true
	return float(spent) / (MODIFIER_FRAMES * bodies.size())


# The engine's own simulator has a generated name.
static func _modifier_name(modifier: SkeletonModifier3D) -> String:
	return "Simulator" if modifier is PhysicalBoneSimulator3D else String(modifier.name)


# Milliseconds a death takes, the first (which brings the ragdoll's bones) and a later one, on the
# female mannequin or the male.
func _death(male: bool) -> Dictionary:
	_new_arena()
	var body := _spawn(1)[0].get_parent() as Character
	if male:
		var old := body.model.rig()
		body.model.remove_child(old)
		old.free()
		body.model.add_child((load(MALE) as PackedScene).instantiate())
	var spent: Array[float] = []
	for _death_index in 2:
		for _i in 30:
			await get_tree().physics_frame
		var start := Time.get_ticks_usec()
		body.die()
		spent.append((Time.get_ticks_usec() - start) / 1000.0)
		for _i in 30:
			await get_tree().physics_frame
		body.revive()
	_arena.free()
	return {"first_ms": spent[0], "later_ms": spent[1]}


func _world(kind: String, empty: Dictionary) -> Dictionary:
	_new_arena()
	var scene := load(WORLD_PARTS[kind]) as PackedScene
	for index in WORLD_COUNT:
		var part := scene.instantiate() as Node3D
		part.position = Vector3((index % 10) * 6.0 - 27.0, 0.5, floorf(index / 10.0) * 6.0 - 27.0)
		if kind == "door":
			part.set(&"auto_open_range", 2.0)
		_arena.add_child(part)
	var processing := 0
	for part in _arena.get_children():
		for node in [part] + part.find_children("*", "", true, false):
			if node.is_processing() or node.is_physics_processing():
				processing += 1
	var frame := await _median_frame()
	_arena.free()
	return {
		"kind": kind,
		"count": WORLD_COUNT,
		"us_each": (frame.wall - empty.wall) * 1000.0 / WORLD_COUNT,
		"work_us_each": (frame.work - empty.work) * 1000.0 / WORLD_COUNT,
		"processing_each": float(processing) / WORLD_COUNT,
	}


func _empty_frame() -> Dictionary:
	_new_arena()
	var frame := await _median_frame()
	_arena.free()
	return frame


func _new_arena() -> void:
	_arena = Node3D.new()
	add_child(_arena)


func _spawn(count: int) -> Array[Walker]:
	var walkers: Array[Walker] = []
	var scene := load(CHARACTER) as PackedScene
	for index in count:
		var body := scene.instantiate() as Character
		var walker := Walker.new()
		walker.name = "Walker"
		body.add_child(walker)
		body.controller = walker
		body.position = Vector3((index % 10) * 3.0 - 14.0, 0.0, floorf(index / 10.0) * 3.0 - 8.0)
		_arena.add_child(body)
		walkers.append(walker)
	return walkers


# The median frame after a warm-up, in milliseconds, two ways: `wall`, from one frame to the next
# (meaningless in a browser, which waits for the display), and `work`, from the frame's first
# physics tick to the last node processed (the scripts, the animation and the physics step; not
# the drawing).
func _median_frame() -> Dictionary:
	for _i in WARM_FRAMES:
		await get_tree().process_frame
	var walls: Array[float] = []
	_works.clear()
	_tick_start = -1
	get_tree().physics_frame.connect(_on_physics_frame)
	_frame_end.done.connect(_on_frame_end)
	var last := Time.get_ticks_usec()
	for _i in FRAMES:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		walls.append((now - last) / 1000.0)
		last = now
	get_tree().physics_frame.disconnect(_on_physics_frame)
	_frame_end.done.disconnect(_on_frame_end)
	walls.sort()
	_works.sort()
	var work := _works[_works.size() / 2] if not _works.is_empty() else -1.0
	return {"wall": walls[walls.size() / 2], "work": work}


func _on_physics_frame() -> void:
	if _tick_start < 0:
		_tick_start = Time.get_ticks_usec()


func _on_frame_end() -> void:
	if _tick_start >= 0:
		_works.append((Time.get_ticks_usec() - _tick_start) / 1000.0)
	_tick_start = -1


func _add(spent: Dictionary, key: String, since: int, counts: bool) -> int:
	var now := Time.get_ticks_usec()
	if counts:
		spent[key] += now - since
	return now


func _physics_bodies(node: Node) -> int:
	var found := 1 if node is PhysicsBody3D else 0
	for child in node.get_children():
		found += _physics_bodies(child)
	return found
