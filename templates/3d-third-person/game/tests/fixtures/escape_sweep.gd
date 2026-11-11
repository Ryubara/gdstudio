class_name EscapeSweep
extends Node
## Runs the real player body at the map's walls from everything it can stand on, to find a way
## out or onto a wall's top (kit docs/engines/godot/map-review.md, "Chains of props are stairs").
## It starts a `Player` on the floor in front of every block and on every top it gets onto from the
## floor, sprints it along each of the four directions and presses jump at a few moments, all
## through the input actions; every place a run comes to rest high up is a start for one more
## round (a chain of hops). A run ends in a fault when it rests on a boundary wall or outside every
## play area.
##
## It runs on the main scene without its camera (so the four directions are the world's axes) and
## every body is on no collision layer of its own, so a hundred of them run at once without meeting.

## Ticks after the start at which jump is pressed.
const JUMP_TICKS: Array[int] = [0, 6, 12]
## The thorough sweep (`thorough`) also jumps later in the run-up and runs on the diagonals.
const THOROUGH_JUMP_TICKS: Array[int] = [0, 6, 12, 20, 28]
const RUN_TICKS := 75
## Starts are this far inside a top's edge.
const INSET := 0.4
## A place a run rests at is a start for the next round when it is this high.
const HIGH := 0.9
## The stick directions a run holds, on the world's axes (no camera: forward is -Z).
const DIRECTIONS: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
const DIAGONALS: Array[Vector2] = [
	Vector2(0.7071, -0.7071),
	Vector2(0.7071, 0.7071),
	Vector2(-0.7071, 0.7071),
	Vector2(-0.7071, -0.7071)
]

## Each fault as text.
var faults: Array[String] = []
## Runs on the diagonals too and jumps later in the run-up (about three times as long).
var thorough := false
## How many runs were made.
var runs := 0
## The highest place a run came to rest (metres).
var highest := 0.0
## Each place a run came to rest above 2.5 m, by its cell, with the round it was reached in.
var high_places := {}

var _main: Node
var _walls: Array[AABB] = []
var _areas: Array[Rect2] = []
var _players: Array[Player] = []


## Sets up the sweep on an instance of `main.tscn` that is not in the tree yet.
func setup(main: Node) -> void:
	_main = main
	for part in ["PlayerRig", "Hud", "Screens"]:
		var node := main.get_node_or_null(part)
		if node != null:
			main.remove_child(node)
			node.free()
	add_child(main)


## Runs `rounds` rounds and fills `faults`.
func sweep(rounds := 2) -> void:
	for _frame in 4:
		await get_tree().physics_frame
	for wall in MapReach.barriers(_main):
		_walls.append(MapReach.box_of(wall))
	# The bodies here are on no layer, so a prop would never push back: hold the props still.
	for prop: RigidBody3D in _main.find_children("*", "RigidBody3D", true, false):
		prop.freeze = true
	_areas = _play_areas()
	var starts := _starts()
	var seen := {}
	for start in starts:
		seen[_cell(start)] = true
	for round_index in rounds:
		var landed := await _round(starts)
		for spot in landed:
			if spot.y > 2.5 and not high_places.has(_cell(spot)):
				high_places[_cell(spot)] = "%s in round %d" % [spot.snappedf(0.1), round_index + 1]
		starts = []
		for spot in landed:
			if spot.y > HIGH and not seen.has(_cell(spot)):
				seen[_cell(spot)] = true
				starts.append(spot)
		if starts.is_empty():
			break


func _round(starts: Array[Vector3]) -> Array[Vector3]:
	_ensure_players(starts.size())
	var landed: Array[Vector3] = []
	var directions := DIRECTIONS + DIAGONALS if thorough else DIRECTIONS
	for direction in directions:
		for jump_tick in THOROUGH_JUMP_TICKS if thorough else JUMP_TICKS:
			for index in starts.size():
				_players[index].teleport(starts[index])
			for _frame in 3:
				await get_tree().physics_frame
			_hold(direction)
			Input.action_press(&"sprint")
			for tick in RUN_TICKS:
				await get_tree().physics_frame
				if tick == jump_tick:
					Input.action_press(&"jump")
				elif tick == jump_tick + 12:
					Input.action_release(&"jump")
			for action in [
				&"move_left", &"move_right", &"move_forward", &"move_back", &"sprint", &"jump"
			]:
				Input.action_release(action)
			for _frame in 20:
				await get_tree().physics_frame
			for index in starts.size():
				var spot := _players[index].global_position
				runs += 1
				highest = maxf(highest, spot.y)
				landed.append(spot)
				var why := _fault(spot)
				if not why.is_empty():
					faults.append(
						(
							"%s from %s running %s, jump at %d"
							% [why, starts[index], direction, jump_tick]
						)
					)
	return landed


# Holds the move actions so that the stick points along `stick` (x right, y down the screen).
func _hold(stick: Vector2) -> void:
	for pair in [
		[&"move_right", stick.x],
		[&"move_left", -stick.x],
		[&"move_back", stick.y],
		[&"move_forward", -stick.y]
	]:
		if pair[1] > 0.0:
			Input.action_press(pair[0], pair[1])


func _ensure_players(count: int) -> void:
	while _players.size() < count:
		var player := load("res://gameplay/player/player.tscn").instantiate() as Player
		player.start_at_spawn = false
		player.collision_layer = 0
		add_child(player)
		for child in player.get_children():
			if not (child is CollisionShape3D):
				child.process_mode = Node.PROCESS_MODE_DISABLED
		_players.append(player)
	for index in _players.size():
		_players[index].process_mode = (
			Node.PROCESS_MODE_INHERIT if index < count else Node.PROCESS_MODE_DISABLED
		)
		if index >= count:
			_players[index].teleport(Vector3(0, -100, 0))


# Where the first round starts: on the floor in front of the middle of each face of every block
# (the run along the face's way in climbs it), and on every top the body gets onto from the floor
# (a low top, a slice of a ramp or staircase). The rounds after start where these came to rest.
func _starts() -> Array[Vector3]:
	var starts: Array[Vector3] = []
	var radius := CharacterTuning.new().radius
	for block: ProtoBlock in _main.find_children("*", "ProtoBlock", true, false):
		if block.get_parent().name == "Boundary" and block.name == "Floor":
			continue
		var box := MapReach.box_of(block)
		if box.size.y < 0.3 or box.position.y > 0.5:
			continue
		var middle := box.get_center()
		var out := radius + 0.3
		for spot in [
			Vector3(box.position.x - out, 0.05, middle.z),
			Vector3(box.end.x + out, 0.05, middle.z),
			Vector3(middle.x, 0.05, box.position.z - out),
			Vector3(middle.x, 0.05, box.end.z + out),
		]:
			if _in_areas(spot) and _clear(spot):
				starts.append(spot)
	for top: Dictionary in MapReach.reachable_tops(_main):
		var box: AABB = top["box"]
		if box.end.y < HIGH or not (top["walk"] or box.end.y <= ReachBench.MEASURED_REACH):
			continue
		var middle := box.get_center()
		starts.append(Vector3(middle.x, box.end.y + 0.05, middle.z))
	return starts


# True when a standing body fits at `spot` (its feet there) without touching a solid.
func _clear(spot: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = CharacterTuning.new().radius
	capsule.height = 1.7
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, spot + Vector3.UP * 0.95)
	query.collision_mask = 1
	return (
		(_main.get_node("World/Level") as Node3D)
		. get_world_3d()
		. direct_space_state
		. intersect_shape(query, 1)
		. is_empty()
	)


func _in_areas(spot: Vector3) -> bool:
	for area in _areas:
		if area.has_point(Vector2(spot.x, spot.z)):
			return true
	return false


# Why a resting place is a fault, or "" when it is not.
func _fault(spot: Vector3) -> String:
	if spot.y < -0.5:
		return "fell out of the map at %s" % spot
	for wall in _walls:
		var over := Rect2(
			wall.position.x - 0.4, wall.position.z - 0.4, wall.size.x + 0.8, wall.size.z + 0.8
		)
		if over.has_point(Vector2(spot.x, spot.z)) and spot.y > wall.end.y - 0.3:
			return "stood on a boundary wall at %s" % spot
	if spot.y > 12.0:
		return "was thrown up to %s" % spot
	return "" if _in_areas(spot) else "left the play areas at %s" % spot


# Where a body may be: the inside of each floor's walls, and the doorways between them.
func _play_areas() -> Array[Rect2]:
	var areas: Array[Rect2] = []
	for floor_block: ProtoBlock in _main.find_children("Floor", "ProtoBlock", true, false):
		if floor_block.get_parent().name != "Boundary":
			continue
		var box := MapReach.box_of(floor_block)
		areas.append(Rect2(box.position.x, box.position.z, box.size.x, box.size.z).grow(-0.3))
	return areas


func _cell(spot: Vector3) -> Vector3i:
	return Vector3i(roundi(spot.x), roundi(spot.y * 2.0), roundi(spot.z))
