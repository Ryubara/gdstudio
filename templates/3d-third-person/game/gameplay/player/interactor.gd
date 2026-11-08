class_name Interactor
extends Node3D
## Finds what the character can use: the nearest node of the group `interactable` that is within
## `reach` in front of this node. Anything with an `interact(by: Node3D)` method can join the
## group (a `Door` does when its `player_can_use` is on).

## The group a usable node joins.
const GROUP := &"interactable"
## Targets more than this far from straight ahead are ignored, in degrees.
const HALF_ANGLE := 75.0


## The usable node in front, or null. `reach` is in metres from this node, along `forward`.
func find_target(forward: Vector3, reach: float) -> Node3D:
	var best: Node3D = null
	var best_distance := reach
	var flat := Vector3(forward.x, 0.0, forward.z).normalized()
	for node in get_tree().get_nodes_in_group(GROUP):
		var candidate := node as Node3D
		if candidate == null or not candidate.is_inside_tree():
			continue
		var offset := candidate.global_position - global_position
		var distance := Vector2(offset.x, offset.z).length()
		if distance > best_distance:
			continue
		var heading := Vector3(offset.x, 0.0, offset.z).normalized()
		if distance > 0.05 and flat.angle_to(heading) > deg_to_rad(HALF_ANGLE):
			continue
		best = candidate
		best_distance = distance
	return best
