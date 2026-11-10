class_name MapReach
extends RefCounted
## What the player can stand on in a map and which walls keep it in, worked out from the map's
## blocks and the player's measured numbers: the reach (`ReachBench.MEASURED_REACH`) and how far
## a sprinting jump carries up onto a higher top (`hop`, from `ReachBench.MEASURED_CARRY`). The
## map tests read it (`test_map_reach.gd`, `test_escape_sweep.gd`; kit
## docs/engines/godot/map-review.md, "Compute the reach").


## True when another block lies over the whole top of `box` lower than a standing body (a pillar
## under a roof): nobody stands there.
static func _covered(root: Node, block: ProtoBlock, box: AABB) -> bool:
	var body := CharacterTuning.new().height
	for other: ProtoBlock in root.find_children("*", "ProtoBlock", true, false):
		if other == block:
			continue
		var over := box_of(other)
		var above := over.position.y >= box.end.y - 0.01 and over.position.y < box.end.y + body
		var spans := (
			over.position.x <= box.position.x
			and over.end.x >= box.end.x
			and over.position.z <= box.position.z
			and over.end.z >= box.end.z
		)
		if above and spans:
			return true
	return false


## The walls that keep the player in: every block of a `Boundary` but its floor.
static func barriers(root: Node) -> Array[ProtoBlock]:
	var walls: Array[ProtoBlock] = []
	for block: ProtoBlock in root.find_children("*", "ProtoBlock", true, false):
		if block.get_parent().name == "Boundary" and block.name != "Floor":
			walls.append(block)
	return walls


## Every top the body gets onto from the floor, as `{name, box, height, walk}`: a walkable ramp or
## staircase, a top within the reach of the floor, or a top within the reach of another such top
## a jump away (`hop`). A moving platform counts with the whole box it sweeps.
static func reachable_tops(root: Node) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var max_slope := deg_to_rad(CharacterTuning.new().max_slope)
	for block: ProtoBlock in root.find_children("*", "ProtoBlock", true, false):
		if block.get_parent().name == "Boundary":
			continue
		var name := str(root.get_path_to(block))
		var sloped := block.kind == ProtoBlock.Kind.RAMP or block.kind == ProtoBlock.Kind.STAIRS
		if sloped and atan2(block.size.y, block.size.x) <= max_slope:
			# Walked up: a slice a metre long at each height, the highest at the top end.
			for slice in _slices(block):
				candidates.append({"name": name, "box": slice, "height": slice.end.y, "walk": true})
			continue
		var box := box_of(block)
		if not _covered(root, block, box):
			candidates.append({"name": name, "box": box, "height": box.end.y, "walk": false})
	for platform: MovingPlatform in root.find_children("*", "MovingPlatform", true, false):
		var box := visual_box(platform)
		box = box.merge(AABB(box.position + platform.global_basis * platform.travel, box.size))
		candidates.append(
			{
				"name": str(root.get_path_to(platform)),
				"box": box,
				"height": box.end.y,
				"walk": false
			}
		)
	var reached: Array[Dictionary] = []
	var changed := true
	while changed:
		changed = false
		for candidate in candidates:
			if reached.has(candidate):
				continue
			var height: float = candidate["height"]
			var gets_on: bool = candidate["walk"] or height <= ReachBench.MEASURED_REACH
			for top in reached:
				if gets_on:
					break
				var rise: float = height - top["height"]
				gets_on = (
					rise <= ReachBench.MEASURED_REACH
					and gap(top["box"], candidate["box"]) <= hop(rise)
				)
			if gets_on:
				reached.append(candidate)
				changed = true
	return reached


## How far across (edge to edge) a sprinting jump carries the body onto a top `rise` metres
## higher than the one it takes off from: the measured carry (`ReachBench.MEASURED_CARRY`) plus
## its grid step, between the measured rises in a straight line. A drop carries farther: what the
## longer fall adds at the sprint speed. Over the measured reach it carries nowhere.
static func hop(rise: float) -> float:
	var carry: Dictionary = ReachBench.MEASURED_CARRY
	var rises: Array = carry.keys()
	rises.sort()
	if rise > rises[rises.size() - 1]:
		return 0.0
	var step := ReachBench.CARRY_STEP
	if rise <= rises[0]:
		var tuning := CharacterTuning.new()
		var fall_gravity := tuning.gravity() * tuning.fall_gravity_scale
		var longer := (
			sqrt(2.0 * (tuning.jump_height - rise) / fall_gravity)
			- sqrt(2.0 * (tuning.jump_height - rises[0]) / fall_gravity)
		)
		return carry[rises[0]] + step + tuning.sprint_speed * longer
	for index in range(1, rises.size()):
		var high: float = rises[index]
		if rise <= high:
			var low: float = rises[index - 1]
			var along := (rise - low) / (high - low)
			return lerpf(carry[low], carry[high], along) + step
	return carry[rises[rises.size() - 1]] + step


# A ramp or staircase (it rises toward its +X) cut into slices a metre long, each as high as its
# top end.
static func _slices(block: ProtoBlock) -> Array[AABB]:
	var slices: Array[AABB] = []
	var count := maxi(ceili(block.size.x), 1)
	var run := block.size.x / count
	for index in count:
		var x0 := -block.size.x / 2.0 + run * index
		var height := block.size.y * (index + 1) / count
		var local := AABB(
			Vector3(x0, -block.size.y / 2.0, -block.size.z / 2.0),
			Vector3(run, height, block.size.z)
		)
		slices.append(block.global_transform * local)
	return slices


static func box_of(block: ProtoBlock) -> AABB:
	return block.global_transform * AABB(-block.size / 2.0, block.size)


## The box round every visible mesh under `node`.
static func visual_box(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if not mesh.visible or mesh.mesh == null:
			continue
		var part := mesh.global_transform * mesh.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


## The distance between two boxes on the ground plane (0 when they overlap).
static func gap(a: AABB, b: AABB) -> float:
	var dx := maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
	var dz := maxf(0.0, maxf(a.position.z - b.end.z, b.position.z - a.end.z))
	return Vector2(dx, dz).length()
