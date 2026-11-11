class_name SectionPilot
extends PlayerBot
## An autopilot for the player in the AI section (kit #969): it walks a loop of `waypoints` along
## the walking mesh's paths and, whenever a character hostile to the player is in its sight, turns
## the camera onto its chest, aims and fires, pressing the same actions a person would
## (`PlayerBot`'s way). For the section's soak and its captures; counted in physics steps.

## The loop it walks, in the world.
@export var waypoints := PackedVector3Array()
## How far it looks for a hostile, metres.
@export_range(1.0, 100.0, 0.5, "suffix:m") var sight := 22.0
## Steps between two looks for a hostile.
@export_range(1, 60) var look_steps := 6
## Steps between two pulls of the trigger while it is on a target.
@export_range(2, 120) var shot_steps := 18
## Degrees off the target it still fires.
@export_range(0.5, 20.0, 0.5, "suffix:deg") var fire_cone := 3.0

## The waypoint it walks to.
var waypoint := 0
## The hostile it is fighting, or null.
var target: AiCharacter = null

var _path := PackedVector3Array()
var _path_at := 0
var _since_shot := 0


func _physics_process(_delta: float) -> void:
	if player == null or camera_rig == null or waypoints.is_empty():
		return
	steps += 1
	if player.is_dead():
		release_all()
		return
	_end_press()
	if steps % look_steps == 0:
		target = _hostile_in_sight()
	_since_shot += 1
	if target != null and is_instance_valid(target) and not target.is_dead():
		_hold(&"move_forward", false)
		_hold(&"aim", true)
		var left := face(target.global_position + Vector3.UP * CHEST_HEIGHT)
		if absf(left) < fire_cone and _since_shot >= shot_steps:
			_since_shot = 0
			_press(&"fire")
			fired += 1
		return
	_hold(&"aim", false)
	if _path_at >= _path.size():
		_plan()
	if _path_at < _path.size() and _walk_level(_path[_path_at]):
		_path_at += 1
		if _path_at >= _path.size():
			waypoint = (waypoint + 1) % waypoints.size()


# One step toward `point`, the camera kept level (it looks at a point 10 m along the way at chest
# height, so it does not tip down as the point comes near); true once there.
func _walk_level(point: Vector3) -> bool:
	var flat := point - player.global_position
	flat.y = 0.0
	if flat.length() <= ARRIVE_DISTANCE:
		_hold(&"move_forward", false)
		return true
	var ahead := player.global_position + flat.normalized() * 10.0 + Vector3.UP * CHEST_HEIGHT
	_hold(&"move_forward", absf(face(ahead)) <= WALK_CONE_DEGREES)
	return false


# A path on the walking mesh to the next waypoint.
func _plan() -> void:
	var map := player.get_world_3d().navigation_map
	_path = NavigationServer3D.map_get_path(map, player.global_position, waypoints[waypoint], true)
	_path_at = 1 if _path.size() > 1 else 0
	if _path.is_empty():
		waypoint = (waypoint + 1) % waypoints.size()


# The nearest living character hostile to the player within `sight`, with a clear line to its
# chest.
func _hostile_in_sight() -> AiCharacter:
	var factions := AiFactions.find(player)
	var me := AiFactionMember.of(player)
	if factions == null or me == null:
		return null
	var eye := player.global_position + Vector3.UP * CHEST_HEIGHT
	var best: AiCharacter = null
	var nearest := sight * sight
	var space := player.get_world_3d().direct_space_state
	for node in get_tree().get_nodes_in_group(AiCharacter.GROUP):
		var other := node as AiCharacter
		if other == null or other.is_dead():
			continue
		var them := AiFactionMember.of(other)
		if them == null or factions.band_of_members(me, them) != AiRelations.Band.HOSTILE:
			continue
		var chest := other.global_position + Vector3.UP * CHEST_HEIGHT
		var far := eye.distance_squared_to(chest)
		if far > nearest:
			continue
		var query := PhysicsRayQueryParameters3D.create(eye, chest, PhysicsLayers.CAMERA_MASK)
		query.exclude = [player.get_rid()]
		if not space.intersect_ray(query).is_empty():
			continue
		nearest = far
		best = other
	return best
