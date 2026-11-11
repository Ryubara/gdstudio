class_name Interactor
extends Node3D
## Finds what the character can use: the nearest `Interactable` within `reach` in front of this
## node. It asks the physics space once, when asked (the interact button), for the areas on
## `interact_mask` inside a cylinder of the reach around it, so nothing joins a group and nothing
## is called by a method name; the reach is measured on the ground plane to each one's
## `Interactable.reach_point()` (a swinging gate measures from where it stands closed).

## The most areas one search looks at (pickups and trigger zones share the Sensors layer).
const MAX_CANDIDATES := 32

## Targets more than this far from straight ahead are ignored.
@export_range(10.0, 180.0, 1.0, "suffix:deg") var half_angle := 75.0
## How far above and below this node a usable thing may be found, metres.
@export_range(0.2, 10.0, 0.1, "suffix:m") var reach_height := 1.5
## The physics layers an `Interactable` sits on: Sensors (`PhysicsLayers.SENSORS`).
@export_flags_3d_physics var interact_mask := PhysicsLayers.SENSORS

var _query := PhysicsShapeQueryParameters3D.new()
var _shape := CylinderShape3D.new()


func _init() -> void:
	_query.shape = _shape
	_query.collide_with_areas = true
	_query.collide_with_bodies = false


## The usable `Interactable` in front, or null. `reach` is in metres from this node, along
## `forward`.
func find_target(forward: Vector3, reach: float) -> Interactable:
	if not is_inside_tree() or reach <= 0.0:
		return null
	_shape.radius = reach
	_shape.height = reach_height * 2.0
	_query.transform = Transform3D(Basis.IDENTITY, global_position)
	_query.collision_mask = interact_mask
	var best: Interactable = null
	var best_distance := reach
	var flat := Vector3(forward.x, 0.0, forward.z).normalized()
	var space := get_world_3d().direct_space_state
	for found in space.intersect_shape(_query, MAX_CANDIDATES):
		var candidate := found.collider as Interactable
		if candidate == null or not candidate.enabled:
			continue
		var offset := candidate.reach_point() - global_position
		var distance := Vector2(offset.x, offset.z).length()
		if distance > best_distance:
			continue
		var heading := Vector3(offset.x, 0.0, offset.z).normalized()
		if distance > 0.05 and flat.angle_to(heading) > deg_to_rad(half_angle):
			continue
		best = candidate
		best_distance = distance
	return best
