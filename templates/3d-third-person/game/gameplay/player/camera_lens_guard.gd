class_name CameraLensGuard
extends RefCounted
## Keeps the point a third-person view is drawn from out of the level, every physics tick after
## the Phantom Camera host has moved the Camera node.
##
## The spring arm keeps the Camera node off a wall only along its own ray, so a ray that grazes a
## wall leaves the node millimetres from it, and the over-the-shoulder view (the Camera node's H
## and V Offset) then moves the picture half a metre sideways with no cast at all: a turn beside a
## wall put the view inside it. The guard sweeps a ball as big as the near plane's corners along
## the three legs from the arm's start to the eye (start to node, node to the shoulder, and
## straight from the start to the eye, which a thin wall between the first two would let past),
## pulls the node in along the first, and gives the share of the shoulder offset that fits in
## `room`. The share drops at once and grows back at `return_speed` shares a second.

## Added to the near plane's corner: the ball keeps this much more than the plane needs.
const SKIN := 0.03
## Halvings that look for the largest share of the offset seen straight from the arm's start.
const STRAIGHT_STEPS := 4

## The share (0 to 1) of the shoulder offset the view may use now.
var room := 1.0
## How far the guard pulled the Camera node in on its last tick (metres; 0 when the arm's own
## position was clear).
var pulled_in := 0.0

var _ball := SphereShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()


## Moves `camera` in toward `pivot` (the arm's start, inside the character) when the ball would
## touch a wall where the arm put it, and updates `room` for the view offset `view` (x along the
## camera's right, y along its up, metres). `mask` is the wall layers; `exclude` the bodies never
## counted (the character's own).
func guard(
	camera: Camera3D,
	pivot: Vector3,
	view: Vector2,
	mask: int,
	exclude: Array[RID],
	delta: float,
	return_speed: float
) -> void:
	var space := camera.get_world_3d().direct_space_state
	_ball.radius = near_radius(camera) + SKIN
	_query.shape = _ball
	_query.collision_mask = mask
	_query.exclude = exclude
	var basis := camera.global_basis.orthonormalized()
	var node := camera.global_position
	var arm := node - pivot
	var safe_node := pivot + arm * _sweep(space, pivot, arm)
	pulled_in = node.distance_to(safe_node)
	if pulled_in > 0.0001:
		camera.global_position = safe_node
	var offset := basis.x * view.x + basis.y * view.y
	var fits := 1.0
	if not offset.is_zero_approx():
		fits = _sweep(space, safe_node, offset)
		if _sweep(space, pivot, safe_node + offset * fits - pivot) < 1.0:
			fits = _straight_share(space, pivot, safe_node, offset, fits)
	room = minf(fits, minf(1.0, room + return_speed * delta))


## The distance from the eye to the farthest corner of `camera`'s near plane: a wall nearer than
## this shows through the picture.
static func near_radius(camera: Camera3D) -> float:
	var half_height := camera.near * tan(deg_to_rad(camera.fov) * 0.5)
	var size := camera.get_viewport().get_visible_rect().size
	var half_width := half_height * size.x / maxf(size.y, 1.0)
	return Vector3(half_width, half_height, camera.near).length()


# The largest share of `offset` (up to `most`) whose eye the arm's start sees straight: a wall
# edge between the arm and the shoulder blocks the line from the start to the eye.
func _straight_share(
	space: PhysicsDirectSpaceState3D, pivot: Vector3, node: Vector3, offset: Vector3, most: float
) -> float:
	var clear := 0.0
	var blocked := most
	for _step in STRAIGHT_STEPS:
		var share := (clear + blocked) * 0.5
		if _sweep(space, pivot, node + offset * share - pivot) < 1.0:
			blocked = share
		else:
			clear = share
	return clear


# The share of `motion` the ball moves from `from` before it would touch a wall (1 when nothing is
# in the way).
func _sweep(space: PhysicsDirectSpaceState3D, from: Vector3, motion: Vector3) -> float:
	if motion.is_zero_approx():
		return 1.0
	_query.transform = Transform3D(Basis.IDENTITY, from)
	_query.motion = motion
	var shares := space.cast_motion(_query)
	if shares.is_empty():
		return 1.0
	return shares[0]
