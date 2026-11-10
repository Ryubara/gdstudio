# `SpawnPoint` of `gds_game` on its own: its group, a pick that passes over a point taken in the
# same frame and a switched-off one, the radius and the facing. The points are built in code; a
# game's suites start characters on the points of its scene (3D Third Person's
# `test_spawn_point.gd`).
extends GdUnitTestSuite

var _rng := RandomNumberGenerator.new()


func before_test() -> void:
	_rng.seed = 7


func _point(group_name := &"heroes", at := Vector3.ZERO) -> SpawnPoint:
	var point: SpawnPoint = auto_free(SpawnPoint.new())
	point.spawn_group = group_name
	point.position = at
	add_child(point)
	return point


func _pick(group_name: StringName) -> SpawnPoint:
	return SpawnPoint.pick(get_tree(), group_name, _rng)


func test_a_point_joins_its_group_and_moves_when_the_group_changes() -> void:
	var point := _point()
	assert_object(_pick(&"heroes")).is_same(point)
	point.spawn_group = &"villains"
	assert_object(_pick(&"heroes")).is_null()
	assert_object(_pick(&"villains")).is_same(point)


func test_a_point_switched_off_is_never_picked() -> void:
	var point := _point()
	point.enabled = false
	assert_object(_pick(&"heroes")).is_null()
	point.enabled = true
	assert_object(_pick(&"heroes")).is_same(point)


func test_two_picks_in_one_frame_take_two_points_then_repeat_one() -> void:
	_point(&"heroes", Vector3.LEFT)
	_point(&"heroes", Vector3.RIGHT)
	var first := _pick(&"heroes")
	assert_object(_pick(&"heroes")).is_not_same(first)
	assert_object(_pick(&"heroes")).is_not_null()


func test_the_radius_scatters_the_spawn_inside_the_circle_and_keeps_the_facing() -> void:
	var point := _point(&"heroes", Vector3(3.0, 1.0, 0.0))
	point.rotation.y = PI / 2.0
	assert_vector(point.spawn_transform(_rng).origin).is_equal(point.global_position)
	point.radius = 2.0
	var moved := false
	for _try in 20:
		var spawn := point.spawn_transform(_rng)
		var away := spawn.origin.distance_to(point.global_position)
		assert_float(away).is_less_equal(2.0)
		assert_float(spawn.origin.y).is_equal_approx(1.0, 0.0001)
		assert_vector(spawn.basis.z).is_equal_approx(point.global_basis.z, Vector3.ONE * 0.0001)
		moved = moved or away > 0.01
	assert_bool(moved).is_true()


func test_the_same_seed_gives_the_same_spot() -> void:
	var point := _point()
	point.radius = 5.0
	_rng.seed = 11
	var once := point.spawn_transform(_rng).origin
	_rng.seed = 11
	assert_vector(point.spawn_transform(_rng).origin).is_equal(once)


func test_the_marker_shows_in_the_game_only_when_asked_and_its_absence_is_a_warning() -> void:
	var point: SpawnPoint = auto_free(SpawnPoint.new())
	assert_array(Array(point._get_configuration_warnings())).has_size(1)
	var marker := MeshInstance3D.new()
	marker.name = "Marker"
	point.add_child(marker)
	marker.owner = point
	marker.unique_name_in_owner = true
	add_child(point)
	assert_array(Array(point._get_configuration_warnings())).is_empty()
	assert_bool(marker.visible).is_false()
	point.show_in_game = true
	assert_bool(marker.visible).is_true()
