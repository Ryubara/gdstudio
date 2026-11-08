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
