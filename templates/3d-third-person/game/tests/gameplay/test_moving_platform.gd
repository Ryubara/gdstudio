# The moving platform's inspector contract: every export has its default pinned, and each one that
# has an effect is changed on a running platform and its effect read.
extends GdUnitTestSuite

const SCENE := "res://gameplay/moving_platform/moving_platform.tscn"

var _platform: MovingPlatform


func before_test() -> void:
	_platform = load(SCENE).instantiate() as MovingPlatform
	_platform.autostart = false
	add_child(_platform)
	await get_tree().physics_frame


func after_test() -> void:
	_platform.free()


func _ticks(count: int) -> void:
	for _tick in count:
		await get_tree().physics_frame


func test_every_export_has_its_default_pinned() -> void:
	var fresh := load(SCENE).instantiate() as MovingPlatform
	var pins := {
		&"size": Vector3(4.0, 1.0, 4.0),
		&"material": null,
		&"travel": Vector3(0.0, 0.0, 4.0),
		&"speed": 2.0,
		&"wait_time": 1.0,
		&"mode": MovingPlatform.Mode.PING_PONG,
		&"autostart": true,
	}
	assert_array(ExportPins.differences(fresh, pins)).is_empty()
	assert_array(ExportPins.wrong_values(fresh, pins)).is_empty()
	fresh.free()


func test_the_scene_holds_its_parts_and_has_no_warning() -> void:
	for part_name in ["Mesh", "Shape", "EndPreview"]:
		assert_object(_platform.find_child(part_name, true, false)).is_not_null()
	assert_array(_platform._get_configuration_warnings()).is_empty()


func test_the_size_resizes_the_slab_its_collision_and_the_end_ghost() -> void:
	_platform.size = Vector3(6.0, 0.5, 3.0)
	var slab := (_platform.get_node("%Mesh") as MeshInstance3D).mesh as BoxMesh
	var collider := (_platform.get_node("%Shape") as CollisionShape3D).shape as BoxShape3D
	var ghost := (_platform.get_node("%EndPreview") as MeshInstance3D).mesh as BoxMesh
	assert_vector(slab.size).is_equal(Vector3(6.0, 0.5, 3.0))
	assert_vector(collider.size).is_equal(Vector3(6.0, 0.5, 3.0))
	assert_vector(ghost.size).is_equal(Vector3(6.0, 0.5, 3.0))


func test_the_material_paints_the_slab() -> void:
	var paint := StandardMaterial3D.new()
	_platform.material = paint
	assert_object((_platform.get_node("%Mesh") as MeshInstance3D).material_override).is_same(paint)


func test_the_end_ghost_sits_at_the_travel_and_is_hidden_in_the_game() -> void:
	var ghost := _platform.get_node("%EndPreview") as MeshInstance3D
	assert_vector(ghost.position).is_equal(Vector3(0.0, 0.0, 4.0))
	_platform.travel = Vector3(3.0, 1.0, 0.0)
	assert_vector(ghost.position).is_equal(Vector3(3.0, 1.0, 0.0))
	assert_bool(ghost.visible).is_false()


func test_the_speed_sets_how_far_it_goes_each_tick_and_follows_a_change() -> void:
	_platform.travel = Vector3(0.0, 0.0, 100.0)
	_platform.mode = MovingPlatform.Mode.ONCE
	_platform.speed = 6.0
	_platform.start()
	var from := _platform.progress()
	await _ticks(30)
	var slow := _platform.progress() - from
	_platform.speed = 30.0
	from = _platform.progress()
	await _ticks(30)
	var fast := _platform.progress() - from
	assert_float(fast / slow).is_equal_approx(5.0, 0.3)


func test_the_travel_sets_where_the_far_end_is() -> void:
	_platform.travel = Vector3(2.0, 0.0, 0.0)
	_platform.speed = 20.0
	_platform.mode = MovingPlatform.Mode.ONCE
	_platform.start()
	await _ticks(20)
	assert_vector(_platform.position).is_equal_approx(Vector3(2.0, 0.0, 0.0), Vector3.ONE * 0.01)


func test_the_wait_time_holds_it_at_each_end() -> void:
	_platform.travel = Vector3(0.0, 0.0, 1.0)
	_platform.speed = 20.0
	_platform.wait_time = 5.0
	_platform.start()
	await _ticks(10)
	var waited := _platform.position.z
	await _ticks(20)
	assert_float(_platform.position.z).is_equal(waited)
	_platform.wait_time = 0.0
	_platform.send_to_start()
	await _ticks(10)
	assert_float(_platform.position.z).is_less(0.5)


func test_the_mode_decides_what_it_does_at_the_end() -> void:
	_platform.travel = Vector3(0.0, 0.0, 1.0)
	_platform.speed = 20.0
	_platform.wait_time = 0.0
	_platform.mode = MovingPlatform.Mode.ONCE
	_platform.start()
	await _ticks(30)
	assert_float(_platform.progress()).is_equal(1.0)
	await _ticks(10)
	assert_float(_platform.progress()).is_equal(1.0)
	var turns := {"start": 0, "end": 0}
	_platform.reached_start.connect(func() -> void: turns["start"] += 1)
	_platform.reached_end.connect(func() -> void: turns["end"] += 1)
	_platform.mode = MovingPlatform.Mode.PING_PONG
	_platform.send_to_start()
	await _ticks(30)
	assert_int(turns["start"]).is_greater(0)
	assert_int(turns["end"]).is_greater(0)


func test_autostart_decides_whether_a_new_platform_moves_at_once() -> void:
	var moving := load(SCENE).instantiate() as MovingPlatform
	moving.speed = 20.0
	moving.wait_time = 0.0
	add_child(moving)
	await _ticks(5)
	assert_float(moving.progress()).is_greater(0.0)
	moving.free()
	assert_float(_platform.progress()).is_equal(0.0)
