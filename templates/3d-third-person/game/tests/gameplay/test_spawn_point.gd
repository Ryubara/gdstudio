# The spawn point's inspector contract: every export has its default pinned, and each one that has
# an effect is changed on a running point and its effect read.
extends GdUnitTestSuite

const SCENE := "res://gameplay/spawn_point/spawn_point.tscn"

var _point: SpawnPoint
var _rng := RandomNumberGenerator.new()


func before_test() -> void:
	_rng.seed = 11
	_point = load(SCENE).instantiate() as SpawnPoint
	add_child(_point)


func after_test() -> void:
	_point.free()


func test_every_export_has_its_default_pinned() -> void:
	var pins := {
		&"spawn_group": &"player",
		&"radius": 0.0,
		&"enabled": true,
		&"show_in_game": false,
	}
	assert_array(ExportPins.differences(_point, pins)).is_empty()
	assert_array(ExportPins.wrong_values(_point, pins)).is_empty()


func test_the_scene_holds_the_arrow_and_has_no_warning() -> void:
	assert_object(_point.get_node("%Marker")).is_not_null()
	assert_array(_point._get_configuration_warnings()).is_empty()


func test_the_group_name_moves_the_point_between_groups_live() -> void:
	assert_object(SpawnPoint.pick(get_tree(), &"player", _rng)).is_same(_point)
	_point.spawn_group = &"wave"
	assert_object(SpawnPoint.pick(get_tree(), &"player", _rng)).is_null()
	assert_object(SpawnPoint.pick(get_tree(), &"wave", _rng)).is_same(_point)


func test_a_point_switched_off_is_not_picked_and_comes_back_when_switched_on() -> void:
	_point.enabled = false
	assert_object(SpawnPoint.pick(get_tree(), &"player", _rng)).is_null()
	_point.enabled = true
	assert_object(SpawnPoint.pick(get_tree(), &"player", _rng)).is_same(_point)


func test_the_radius_scatters_the_spawn_inside_the_circle() -> void:
	_point.position = Vector3(10.0, 0.0, 10.0)
	assert_vector(_point.spawn_transform(_rng).origin).is_equal(Vector3(10.0, 0.0, 10.0))
	_point.radius = 3.0
	var farthest := 0.0
	var moved := false
	for _try in 20:
		var spot := _point.spawn_transform(_rng).origin
		farthest = maxf(farthest, spot.distance_to(Vector3(10.0, 0.0, 10.0)))
		moved = moved or spot != Vector3(10.0, 0.0, 10.0)
	assert_bool(moved).is_true()
	assert_float(farthest).is_less_equal(3.0)


func test_the_arrow_shows_in_the_game_only_when_asked() -> void:
	var marker := _point.get_node("%Marker") as MeshInstance3D
	assert_bool(marker.visible).is_false()
	_point.show_in_game = true
	assert_bool(marker.visible).is_true()
	_point.show_in_game = false
	assert_bool(marker.visible).is_false()


func test_the_arrow_points_the_way_the_point_faces() -> void:
	# The marker's long axis lies along the point's -Z, the blue arrow of the editor.
	var marker := _point.get_node("%Marker") as MeshInstance3D
	assert_float(marker.position.z).is_less(0.0)


func _more_points(spots: Array[Vector3]) -> void:
	for spot in spots:
		var extra := auto_free(load(SCENE).instantiate()) as SpawnPoint
		extra.position = spot
		add_child(extra)


func _player_named(player_name: String) -> Player:
	var player := auto_free(load("res://gameplay/player/player.tscn").instantiate()) as Player
	player.name = player_name
	add_child(player)
	return player


func test_two_points_picked_in_one_frame_are_two_different_points() -> void:
	_more_points([Vector3(6.0, 0.0, 0.0), Vector3(-6.0, 0.0, 0.0)])
	for _try in 10:
		var first := SpawnPoint.pick(get_tree(), &"player", _rng)
		var second := SpawnPoint.pick(get_tree(), &"player", _rng)
		var third := SpawnPoint.pick(get_tree(), &"player", _rng)
		assert_bool(first == second or first == third or second == third).is_false()
		# The marks belong to a frame: the next one starts clean.
		await get_tree().physics_frame


func test_with_every_point_taken_a_pick_repeats_one_instead_of_failing() -> void:
	assert_object(SpawnPoint.pick(get_tree(), &"player", _rng)).is_same(_point)
	assert_object(SpawnPoint.pick(get_tree(), &"player", _rng)).is_same(_point)


func test_two_characters_in_one_world_start_apart() -> void:
	_more_points([Vector3(6.0, 0.0, 0.0), Vector3(-6.0, 0.0, 0.0)])
	var a := _player_named("A")
	var b := _player_named("B")
	assert_float(a.global_position.distance_to(b.global_position)).is_greater(1.0)
	a.free()
	b.free()


func test_a_character_starts_inside_the_radius_and_not_always_at_the_centre() -> void:
	_point.radius = 3.0
	var spots: Array[Vector3] = []
	for index in 6:
		var player := _player_named("Character%d" % index)
		spots.append(player.global_position)
		player.free()
		# The point is taken for the rest of the frame; the next character may use it again.
		await get_tree().physics_frame
	var away := 0
	for spot in spots:
		assert_float(spot.distance_to(_point.global_position)).is_less_equal(3.0 + 0.001)
		if spot.distance_to(_point.global_position) > 0.1:
			away += 1
	assert_int(away).is_greater(3)


func test_the_same_character_starts_at_the_same_spot_every_run() -> void:
	_point.radius = 3.0
	var first := _player_named("Same")
	var spot := first.global_position
	first.free()
	await get_tree().physics_frame
	var again := _player_named("Same")
	assert_vector(again.global_position).is_equal(spot)
	again.free()
