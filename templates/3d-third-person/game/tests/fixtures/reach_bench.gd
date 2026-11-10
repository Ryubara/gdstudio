class_name ReachBench
extends Node3D
## Measures how high a ledge the real `Player` gets onto from level ground: it runs (and sprints)
## the character at a block of each height from several distances and presses jump at several
## moments, all through the input actions a player presses. The most a body climbs is more than
## `PlayerTuning.jump_height`: the step-up at an edge and the capsule's rounded foot add to it, so
## a map judges its walls against this number, never the tuning (kit
## `docs/engines/godot/map-review.md`, "Measure the reach").
##
## Each height and distance gets a lane of its own, side by side, and every lane runs at once
## with the same presses; a lane's player is alone on its block. Free it with `auto_free`.

## The most the player is measured to climb from level ground (metres): the highest block the
## bench gets it onto, the one number every reach test of the maps reads. `test_jump_reach.gd`
## pins it, so a change to the jump, the step-up or the capsule fails there first.
const MEASURED_REACH := 1.35
## The widest gap (metres, edge to edge, on a 0.25 m grid) the player sprints and jumps across
## onto a top this much higher than the one it runs on (`measure_carry`), pinned by
## `test_jump_reach.gd`. The body lands higher than its 1.25 m jump: its rounded foot rides up a
## ledge's edge, so a 3 m gap is crossed onto a top 1.35 m up.
const MEASURED_CARRY := {0.0: 5.75, 0.5: 5.25, 1.0: 4.5, 1.25: 3.5, 1.35: 3.0}
## The grid the carry is measured on: the true widest gap is under the next step.
const CARRY_STEP := 0.25
## The ticks after the start at which jump is pressed (held for `JUMP_HOLD` ticks).
const JUMP_TICKS: Array[int] = [0, 3, 6, 9, 12, 16, 20, 26, 32]
const JUMP_HOLD := 12
## How far from the block's face each run starts, in metres.
const STARTS: Array[float] = [1.0, 2.0, 3.0, 4.0]
const RUN_TICKS := 90
const LANE_WIDTH := 8.0
const BLOCK_DEPTH := 6.0
## The carry bench's runway: its top's height and how far back from its edge a run starts.
const RUNWAY_HEIGHT := 2.0
const RUNWAY_START := 6.0
## The ticks of a run-up at which the carry bench presses jump (the edge comes at about 62).
const CARRY_JUMP_TICKS: Array[int] = [48, 52, 55, 58, 60, 62, 64, 66, 68, 70, 72]
const CARRY_RUN_TICKS := 120

const PLAYER_SCENE := preload("res://gameplay/player/player.tscn")

var _lanes: Array[Dictionary] = []


## Whether the body got onto a block of each height in `heights` (metres), as
## `{height: true or false}`, sprinting and running.
func measure(heights: Array[float]) -> Dictionary:
	_build(heights)
	for _frame in 4:
		await get_tree().physics_frame
	var climbed := {}
	for height in heights:
		climbed[height] = false
	for sprint in [true, false]:
		for jump_tick in JUMP_TICKS:
			await _run(sprint, jump_tick)
			for lane in _lanes:
				var player: Player = lane["player"]
				var height: float = lane["height"]
				if player.is_on_floor() and player.global_position.y > height - 0.1:
					climbed[height] = true
	return climbed


## The widest gap the body sprints and jumps across onto a top `rise` metres higher than the
## one it runs on, for each rise in `rises`, from the gaps in `gaps` (metres, edge to edge), as
## `{rise: widest gap crossed, or 0}`.
func measure_carry(rises: Array[float], gaps: Array[float]) -> Dictionary:
	_build_carry(rises, gaps)
	for _frame in 4:
		await get_tree().physics_frame
	var widest := {}
	for rise in rises:
		widest[rise] = 0.0
	for jump_tick in CARRY_JUMP_TICKS:
		_release()
		for lane in _lanes:
			(lane["player"] as Player).teleport(lane["start"], PI)
		for _frame in 3:
			await get_tree().physics_frame
		Input.action_press(&"move_forward")
		Input.action_press(&"sprint")
		for tick in CARRY_RUN_TICKS:
			await get_tree().physics_frame
			if tick == jump_tick:
				Input.action_press(&"jump")
			elif tick == jump_tick + JUMP_HOLD:
				Input.action_release(&"jump")
		_release()
		for lane in _lanes:
			var player: Player = lane["player"]
			var rise: float = lane["rise"]
			var crossed: bool = (
				player.is_on_floor()
				and player.global_position.y > RUNWAY_HEIGHT + rise - 0.1
				and player.global_position.z < lane["edge"]
			)
			if crossed:
				widest[rise] = maxf(widest[rise], lane["gap"])
	return widest


## The highest of `heights` the body climbed (0 when none).
static func highest(climbed: Dictionary) -> float:
	var best := 0.0
	for height: float in climbed:
		if climbed[height]:
			best = maxf(best, height)
	return best


func _build(heights: Array[float]) -> void:
	var count := heights.size() * STARTS.size()
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(count * LANE_WIDTH + 20.0, 1.0, 40.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(count * LANE_WIDTH / 2.0, -0.5, 0.0)
	add_child(floor_body)
	var index := 0
	for height in heights:
		for start in STARTS:
			var x := index * LANE_WIDTH
			var block := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(LANE_WIDTH - 2.0, height, BLOCK_DEPTH)
			shape.shape = box
			block.add_child(shape)
			block.position = Vector3(x, height / 2.0, -BLOCK_DEPTH / 2.0)
			add_child(block)
			var player := PLAYER_SCENE.instantiate() as Player
			player.start_at_spawn = false
			player.position = Vector3(x, 0.02, start)
			add_child(player)
			_lanes.append({"player": player, "height": height, "start": Vector3(x, 0.02, start)})
			index += 1


func _build_carry(rises: Array[float], gaps: Array[float]) -> void:
	var count := rises.size() * gaps.size()
	_add_box(
		Vector3(count * LANE_WIDTH / 2.0, -0.5, 0.0), Vector3(count * LANE_WIDTH + 20.0, 1.0, 60.0)
	)
	var index := 0
	for rise in rises:
		for gap in gaps:
			var x := index * LANE_WIDTH
			var runway := RUNWAY_START + 4.0
			_add_box(
				Vector3(x, RUNWAY_HEIGHT / 2.0, runway / 2.0),
				Vector3(LANE_WIDTH - 2.0, RUNWAY_HEIGHT, runway)
			)
			var top := RUNWAY_HEIGHT + rise
			_add_box(
				Vector3(x, top / 2.0, -gap - BLOCK_DEPTH / 2.0),
				Vector3(LANE_WIDTH - 2.0, top, BLOCK_DEPTH)
			)
			var player := PLAYER_SCENE.instantiate() as Player
			player.start_at_spawn = false
			var start := Vector3(x, RUNWAY_HEIGHT + 0.02, RUNWAY_START)
			player.position = start
			add_child(player)
			_lanes.append(
				{"player": player, "rise": rise, "gap": gap, "edge": -gap, "start": start}
			)
			index += 1


func _add_box(centre: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = centre
	add_child(body)


# One run of every lane: back to the start, then forward (sprinting or not) with a jump pressed
# at `jump_tick`.
func _run(sprint: bool, jump_tick: int) -> void:
	_release()
	for lane in _lanes:
		(lane["player"] as Player).teleport(lane["start"], PI)
	for _frame in 3:
		await get_tree().physics_frame
	Input.action_press(&"move_forward")
	if sprint:
		Input.action_press(&"sprint")
	for tick in RUN_TICKS:
		await get_tree().physics_frame
		if tick == jump_tick:
			Input.action_press(&"jump")
		elif tick == jump_tick + JUMP_HOLD:
			Input.action_release(&"jump")
	_release()


func _release() -> void:
	for action: StringName in [&"move_forward", &"sprint", &"jump"]:
		Input.action_release(action)
