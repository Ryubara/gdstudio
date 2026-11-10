class_name RouteWalker
extends RefCounted
## Walks the real `Player` along a list of points by pressing the move actions with the strengths
## a stick would give, relative to the camera that draws the scene, as a person does. It sprints
## at a navigation link and jumps where the floor ends ahead (a gap), and never moves the body
## itself, so arriving is proof that the body can go that way.

## How near a point counts as reached (metres, on the ground plane).
const REACH_POINT := 0.45
## A walk that comes no nearer its next point for this long is stuck.
const STUCK_SECONDS := 3.0
const MOVE_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_forward", &"move_back", &"sprint", &"jump"
]

## Why the last walk stopped, for a failure message.
var report := ""
## The points that were reached, in order.
var reached := 0


## A path on the navigation map from `from` to `to`, with the points where a link starts
## (`{"points": PackedVector3Array, "links": PackedInt32Array}`, a 1 for a point a link owns: the
## query marks a link's start, and the stretch from it to the next point is the link).
static func path_on(map: RID, from: Vector3, to: Vector3) -> Dictionary:
	var query := NavigationPathQueryParameters3D.new()
	query.map = map
	query.start_position = from
	query.target_position = to
	query.metadata_flags = NavigationPathQueryParameters3D.PATH_METADATA_INCLUDE_TYPES
	var result := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(query, result)
	var links := PackedInt32Array()
	for type in result.path_types:
		links.append(1 if type == NavigationPathQueryResult3D.PATH_SEGMENT_TYPE_LINK else 0)
	return {"points": result.path, "links": links}


## The length of a path on the ground plane and up and down.
static func length_of(points: PackedVector3Array) -> float:
	var total := 0.0
	for index in range(1, points.size()):
		total += points[index - 1].distance_to(points[index])
	return total


## Walks `player` through `points` (a link's start marked 1 in `links`: the stretch after it is
## crossed with a sprint and a jump). True when it reached the last point within `seconds`.
func walk(
	player: Player,
	points: PackedVector3Array,
	links: PackedInt32Array = PackedInt32Array(),
	seconds := 30.0
) -> bool:
	reached = 0
	report = ""
	var tree := player.get_tree()
	var index := 0
	var best := INF
	var since_best := 0.0
	var clock := 0.0
	var jumped_at := -1
	while index < points.size():
		await tree.physics_frame
		var delta := 1.0 / Engine.physics_ticks_per_second
		clock += delta
		var target := points[index]
		var to := target - player.global_position
		to.y = 0.0
		if to.length() < REACH_POINT:
			index += 1
			reached = index
			best = INF
			since_best = 0.0
			continue
		# A link's first point is the one the query marks: the stretch after it crosses the link.
		var on_link := index > 0 and index <= links.size() and links[index - 1] == 1
		# Run fast at a link, and jump where the floor ends ahead, as a person does at a gap.
		var to_link := on_link or (index < links.size() and links[index] == 1)
		_steer(player, to.normalized(), to_link)
		if on_link and jumped_at != index and player.is_on_floor():
			if not _floor_ahead(player, to.normalized()):
				Input.action_press(&"jump")
				jumped_at = index
		elif jumped_at == index and not player.is_on_floor():
			Input.action_release(&"jump")
		if to.length() < best - 0.05:
			best = to.length()
			since_best = 0.0
		else:
			since_best += delta
		if since_best > STUCK_SECONDS or clock > seconds:
			report = (
				"stopped at %s heading for point %d of %d (%s), %.1f m away after %.1f s"
				% [player.global_position, index, points.size(), target, to.length(), clock]
			)
			release()
			return false
	release()
	return true


## Lets go of every action a walk presses.
static func release() -> void:
	for action in MOVE_ACTIONS:
		Input.action_release(action)


# True when there is floor under the body's front edge, a step ahead.
static func _floor_ahead(player: Player, direction: Vector3) -> bool:
	var ahead := player.global_position + direction * (PlayerTuning.new().radius + 0.15)
	var query := PhysicsRayQueryParameters3D.create(
		ahead + Vector3.UP * 0.3,
		ahead + Vector3.DOWN * 0.6,
		player.collision_mask,
		[player.get_rid()]
	)
	return not player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


# Presses the move actions so that the camera-relative stick points along `direction`.
func _steer(player: Player, direction: Vector3, sprint: bool) -> void:
	var view := _view_basis(player)
	var right := direction.dot(view.x)
	var back := direction.dot(view.z)
	_press(&"move_right", right)
	_press(&"move_left", -right)
	_press(&"move_back", back)
	_press(&"move_forward", -back)
	if sprint:
		Input.action_press(&"sprint")
	else:
		Input.action_release(&"sprint")


static func _press(action: StringName, strength: float) -> void:
	if strength > 0.001:
		Input.action_press(action, clampf(strength, 0.0, 1.0))
	else:
		Input.action_release(action)


# The same view the character moves by (`Player._view_basis`): the drawing camera, flat.
static func _view_basis(player: Player) -> Basis:
	var camera := player.get_viewport().get_camera_3d()
	if camera == null:
		return Basis.IDENTITY
	var forward := -camera.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return Basis.IDENTITY
	forward = forward.normalized()
	return Basis(forward.cross(Vector3.UP), Vector3.UP, -forward)
