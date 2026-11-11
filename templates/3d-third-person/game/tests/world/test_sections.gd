# The two map sections behind the outer wall (kit #885): each is its own scene instanced in
# `main.tscn` at a doorway, closed all round, with spawn points and perception markers (the AI
# section) and a baked navigation mesh with test routes (the pathing section) that later AI work
# reads by name. What the real body does in them is `test_section_walks.gd`.
extends GdUnitTestSuite

const MAIN := "res://main.tscn"
const AI_SCENE := "res://world/prototype/ai_section/ai_section.tscn"
const PATHING_SCENE := "res://world/prototype/pathing_section/pathing_section.tscn"
## The eye of a standing body over its feet (`CharacterTuning.camera_height`).
const EYE := 1.55
## A path counts as reaching a point this close to it on the ground plane (the baked surface floats
## 0.2 m over the floor: the baker lifts it by two cells of 0.1 m).
const ARRIVE := 0.75

var _main: Node
var _ai: Node3D
var _pathing: Node3D


func before() -> void:
	_main = load(MAIN).instantiate()
	(_main.get_node("PlayerRig/Player") as Player).start_at_spawn = false
	add_child(_main)
	_ai = _main.get_node("World/AISection")
	_pathing = _main.get_node("World/PathingSection")
	for _frame in 4:
		await get_tree().physics_frame
	# The map takes the regions in over a few physics frames: wait until it answers.
	var map := _map()
	var probe: Vector3 = _route("Wide")[0]
	for _frame in 300:
		if NavigationServer3D.map_get_closest_point(map, probe).distance_to(probe) < ARRIVE:
			break
		await get_tree().physics_frame


func after() -> void:
	_main.free()


func test_each_section_is_its_own_scene_in_the_main_scene_at_a_doorway() -> void:
	assert_str(_ai.scene_file_path).is_equal(AI_SCENE)
	assert_str(_pathing.scene_file_path).is_equal(PATHING_SCENE)
	# A section's origin is the middle of its doorway on the floor, on the wall's outer face.
	assert_vector(_ai.global_position).is_equal(Vector3(-25.0, 0.0, -9.0))
	assert_vector(_pathing.global_position).is_equal(Vector3(25.0, 0.0, -6.0))


func test_a_body_fits_through_each_doorway() -> void:
	for section: Node3D in [_ai, _pathing]:
		var inward := -1.0 if section == _ai else 1.0
		var from := section.global_position + Vector3(-3.0 * inward, 0.95, 0.0)
		var to := section.global_position + Vector3(4.0 * inward, 0.95, 0.0)
		for side in [-1.2, 0.0, 1.2]:
			var offset := Vector3(0.0, 0.0, side)
			(
				assert_float(_cast_body(from + offset, to + offset))
				. override_failure_message("%s doorway at %.1f" % [section.name, side])
				. is_equal(1.0)
			)


func test_each_section_is_closed_all_round_but_its_doorway() -> void:
	for section: Node3D in [_ai, _pathing]:
		var holes: Array[String] = []
		var floor_block: ProtoBlock = section.get_node("Navigation/Boundary/Floor")
		var box := floor_block.global_transform * AABB(-floor_block.size / 2.0, floor_block.size)
		# The inside, from the floor less the 1 m walls (the doorway side has the map's wall).
		var inside := Rect2(
			box.position.x + 1.0, box.position.z + 1.0, box.size.x - 2.0, box.size.z - 2.0
		)
		if section == _ai:
			inside = Rect2(
				box.position.x + 1.0, box.position.z + 1.0, box.size.x - 1.0, box.size.z - 2.0
			)
		else:
			inside = Rect2(box.position.x, box.position.z + 1.0, box.size.x - 1.0, box.size.z - 2.0)
		for height: float in [0.3, 1.2, 2.5, 3.8]:
			for point in _perimeter(inside):
				var outward: Vector3 = point["out"]
				var start: Vector3 = point["at"] - outward * 0.3 + Vector3.UP * height
				var hit := _ray(start, start + outward * 2.0)
				var at_door := _in_doorway(section, start)
				if hit.is_empty() and not at_door:
					holes.append("%s at %s" % [section.name, start])
				elif not hit.is_empty() and at_door and height < 2.9:
					holes.append("%s doorway shut at %s" % [section.name, start])
		assert_array(holes).override_failure_message("\n".join(holes.slice(0, 12))).is_empty()


func test_the_enemy_and_friendly_spawns_stand_on_the_floor_and_face_each_other() -> void:
	var enemies := _points(&"enemy")
	var friends := _points(&"friendly")
	assert_int(enemies.size()).is_equal(6)
	assert_int(friends.size()).is_equal(4)
	for point in enemies + friends:
		var below := _ray(point.global_position + Vector3.UP, point.global_position + Vector3.DOWN)
		assert_bool(below.is_empty()).override_failure_message(point.name).is_false()
		assert_float((below["position"] as Vector3).y).is_equal_approx(0.0, 0.01)
		(
			assert_float(
				_cast_body(
					point.global_position + Vector3(0, 0.95, 0),
					point.global_position + Vector3(0, 1.0, 0)
				)
			)
			. override_failure_message(point.name + " is inside a solid")
			. is_equal(1.0)
		)
	for point in enemies:
		assert_float(-point.global_basis.z.x).override_failure_message(point.name).is_greater(0.99)
	for point in friends:
		assert_float(-point.global_basis.z.x).override_failure_message(point.name).is_less(-0.99)


func test_the_enemies_spawn_out_of_sight_of_the_doorway() -> void:
	var doorway := _ai.global_position + Vector3(1.5, EYE, 0.0)
	for point in _points(&"enemy"):
		for height: float in [0.5, 1.0, EYE]:
			var target := point.global_position + Vector3.UP * height
			(
				assert_bool(_ray(doorway, target).is_empty())
				. override_failure_message("%s is seen from the doorway" % point.name)
				. is_false()
			)


func test_the_watch_posts_see_the_seen_markers_and_not_the_hidden_ones() -> void:
	var perception := _ai.get_node("Perception")
	var watchers: Array[Node3D] = []
	for marker: Node3D in perception.get_children():
		if marker.name.begins_with("Watch"):
			watchers.append(marker)
	assert_int(watchers.size()).is_equal(2)
	var seen := 0
	var hidden := 0
	for marker: Node3D in perception.get_children():
		if marker.name.begins_with("Seen"):
			seen += 1
			var by_someone := false
			for watcher in watchers:
				by_someone = by_someone or _sees(watcher, marker, [EYE])
			(
				assert_bool(by_someone)
				. override_failure_message(marker.name + " is seen by nobody")
				. is_true()
			)
		elif marker.name.begins_with("Hidden"):
			hidden += 1
			for watcher in watchers:
				(
					assert_bool(_sees(watcher, marker, [0.5, 1.0, EYE]))
					. override_failure_message("%s sees %s" % [watcher.name, marker.name])
					. is_false()
				)
	assert_int(seen).is_equal(3)
	assert_int(hidden).is_equal(3)


func test_the_saved_navigation_meshes_match_a_fresh_bake() -> void:
	# A block moved without a bake leaves the saved mesh stale: bake again and compare. A bake
	# depends on where the region stands (the cells lie on the world's grid), so it is made the
	# way the bake tool makes it, with the section's scene alone at the origin.
	for path: String in [AI_SCENE, PATHING_SCENE]:
		var section: Node3D = auto_free(load(path).instantiate())
		var region: NavigationRegion3D = section.get_node("Navigation")
		region.enabled = false  # Kept off the map the other tests ask.
		add_child(section)
		var saved := region.navigation_mesh
		var fresh := saved.duplicate() as NavigationMesh
		fresh.clear()
		var source := NavigationMeshSourceGeometryData3D.new()
		NavigationServer3D.parse_source_geometry_data(fresh, source, region)
		NavigationServer3D.bake_from_source_geometry_data(fresh, source)
		var counts := (
			"%s: a fresh bake has %d polygons and %d vertices, the saved mesh %d and %d"
			% [
				section.name,
				fresh.get_polygon_count(),
				fresh.vertices.size(),
				saved.get_polygon_count(),
				saved.vertices.size()
			]
		)
		assert_int(fresh.get_polygon_count()).override_failure_message(counts).is_equal(
			saved.get_polygon_count()
		)
		assert_int(fresh.vertices.size()).override_failure_message(counts).is_equal(
			saved.vertices.size()
		)


func test_every_route_of_the_pathing_section_has_a_path_to_its_end() -> void:
	for route: Node3D in _pathing.get_node("Routes").get_children():
		var ends := _route(route.name)
		var path := NavigationServer3D.map_get_path(_map(), ends[0], ends[1], true)
		assert_bool(path.is_empty()).override_failure_message(route.name).is_false()
		(
			assert_float(_flat(path[path.size() - 1]).distance_to(_flat(ends[1])))
			. override_failure_message("%s ends at %s" % [route.name, path[path.size() - 1]])
			. is_less(ARRIVE)
		)


func test_the_routes_go_the_way_their_names_say() -> void:
	# Straight through the wide and narrow ways and the door, up the ramp and the stairs, across
	# the gap by its link; round the tight gap (too narrow for the agent) and the steep ramp.
	for route_name in ["Wide", "Narrow", "Door", "Gap", "Obstacles", "Kerb"]:
		(
			assert_float(_detour(route_name))
			. override_failure_message(
				"%s goes round: %.1f m more" % [route_name, _detour(route_name)]
			)
			. is_less(1.5)
		)
	for route_name in ["Ramp", "Stairs"]:
		(
			assert_float(_detour(route_name))
			. override_failure_message("%s: %.1f m more" % [route_name, _detour(route_name)])
			. is_less(6.0)
		)
	for route_name in ["Tight", "Steep"]:
		(
			assert_float(_detour(route_name))
			. override_failure_message("%s does not go round" % route_name)
			. is_greater(6.0)
		)
	var gap := _route("Gap")
	var crossing := RouteWalker.path_on(_map(), gap[0], gap[1])
	(
		assert_bool((crossing["links"] as PackedInt32Array).has(1))
		. override_failure_message("the gap is crossed by no link")
		. is_true()
	)


func test_the_drop_is_one_way_and_the_far_deck_is_reached_only_by_its_link() -> void:
	var drop := _route("Drop")
	var down := NavigationServer3D.map_get_path(_map(), drop[0], drop[1], true)
	assert_float(_flat(down[down.size() - 1]).distance_to(_flat(drop[1]))).is_less(ARRIVE)
	# Back up there is no drop: the way to the far deck is up the ramp and over the gap.
	var up := NavigationServer3D.map_get_path(_map(), drop[1], drop[0], true)
	var flat := PackedVector3Array()
	for point in up:
		flat.append(_flat(point))
	assert_float(RouteWalker.length_of(flat)).is_greater(
		_flat(drop[0]).distance_to(_flat(drop[1])) + 10.0
	)
	var link: NavigationLink3D = _pathing.get_node("GapLink")
	link.enabled = false
	for _frame in 10:
		await get_tree().physics_frame
	var gap := _route("Gap")
	var cut := NavigationServer3D.map_get_path(_map(), gap[0], gap[1], true)
	link.enabled = true
	assert_float(_flat(cut[cut.size() - 1]).distance_to(_flat(gap[1]))).is_greater(1.0)


func test_every_marker_of_the_ai_section_is_on_the_walking_mesh_from_a_friendly_spawn() -> void:
	var start := _points(&"friendly")[0].global_position
	var goals: Array[Node3D] = []
	goals.append_array(_points(&"enemy"))
	for marker: Node3D in _ai.get_node("Perception").get_children():
		goals.append(marker)
	for goal in goals:
		var path := NavigationServer3D.map_get_path(_map(), start, goal.global_position, true)
		assert_bool(path.is_empty()).override_failure_message(goal.name).is_false()
		(
			assert_float(_flat(path[path.size() - 1]).distance_to(_flat(goal.global_position)))
			. override_failure_message(
				"%s: the path ends at %s" % [goal.name, path[path.size() - 1]]
			)
			. is_less(ARRIVE)
		)


func _map() -> RID:
	return _ai.get_world_3d().navigation_map


func _route(route_name: String) -> Array[Vector3]:
	var route := _pathing.get_node("Routes/" + route_name)
	return [
		(route.get_node("Start") as Node3D).global_position,
		(route.get_node("End") as Node3D).global_position,
	]


# How much longer the route's path is than the straight line from its start to its end.
func _detour(route_name: String) -> float:
	var ends := _route(route_name)
	var path := NavigationServer3D.map_get_path(_map(), ends[0], ends[1], true)
	var flat := PackedVector3Array()
	for point in path:
		flat.append(_flat(point))
	return RouteWalker.length_of(flat) - _flat(ends[0]).distance_to(_flat(ends[1]))


func _flat(point: Vector3) -> Vector3:
	return Vector3(point.x, 0.0, point.z)


func _points(group: StringName) -> Array[SpawnPoint]:
	var found: Array[SpawnPoint] = []
	for node in _ai.get_node("Spawns").get_children():
		var point := node as SpawnPoint
		if point != null and point.spawn_group == group:
			found.append(point)
	return found


func _sees(watcher: Node3D, target: Node3D, heights: Array) -> bool:
	var eye := watcher.global_position + Vector3.UP * EYE
	for height: float in heights:
		if _ray(eye, target.global_position + Vector3.UP * height).is_empty():
			return true
	return false


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [(_main.get_node("PlayerRig/Player") as CollisionObject3D).get_rid()]
	return _ai.get_world_3d().direct_space_state.intersect_ray(query)


# How far along `from` to `to` a standing body's capsule moves before it touches something (1 when
# the way is clear).
func _cast_body(from: Vector3, to: Vector3) -> float:
	var capsule := CapsuleShape3D.new()
	capsule.radius = CharacterTuning.new().radius
	capsule.height = 1.7
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, from)
	query.motion = to - from
	query.collision_mask = 1
	query.exclude = [(_main.get_node("PlayerRig/Player") as CollisionObject3D).get_rid()]
	var result := _ai.get_world_3d().direct_space_state.cast_motion(query)
	return result[0]


# Points every 0.5 m along a rectangle's sides, with the way out of each side.
func _perimeter(inside: Rect2) -> Array[Dictionary]:
	var points: Array[Dictionary] = []
	var x := inside.position.x + 0.25
	while x < inside.end.x:
		points.append({"at": Vector3(x, 0, inside.position.y), "out": Vector3.FORWARD})
		points.append({"at": Vector3(x, 0, inside.end.y), "out": Vector3.BACK})
		x += 0.5
	var z := inside.position.y + 0.25
	while z < inside.end.y:
		points.append({"at": Vector3(inside.position.x, 0, z), "out": Vector3.LEFT})
		points.append({"at": Vector3(inside.end.x, 0, z), "out": Vector3.RIGHT})
		z += 0.5
	return points


# True for a point in the opening of the section's doorway (4 m wide, on the map's wall).
func _in_doorway(section: Node3D, point: Vector3) -> bool:
	var local := point - section.global_position
	return absf(local.z) < 2.0 and absf(local.x) < 1.6
