# The impacts in the game itself: the main scene holds an `Impacts`, and a shot at the level's own
# floor, wall, pushed cube and moving platform leaves a mark of the right surface on it.
extends GdUnitTestSuite

var _main: Node
var _impacts: Impacts


func before_test() -> void:
	_main = auto_free(load("res://main.tscn").instantiate())
	add_child(_main)
	_impacts = _main.get_node("World/Impacts") as Impacts
	await get_tree().physics_frame
	await get_tree().physics_frame


func after_test() -> void:
	AudioDrain.stop_all(_main)


func _shoot(from: Vector3, toward: Vector3) -> void:
	await ImpactShots.shoot(get_tree(), _main, from, toward)


func test_the_main_scene_holds_the_impacts_and_it_is_found_by_the_projectiles() -> void:
	assert_object(_impacts).is_not_null()
	assert_bool(_impacts.is_in_group(&"impacts")).is_true()
	assert_int(_impacts.surfaces_by_name().size()).is_equal(4)


func test_a_shot_at_the_top_of_the_levels_north_wall_marks_it_with_the_default_surface() -> void:
	var wall := _main.get_node("World/Level/Boundary/WallNorth") as ProtoBlock
	var body := wall.get_node("Body") as StaticBody3D
	var top := wall.global_position + Vector3(0.0, wall.size.y / 2.0, 0.0)
	await _shoot(top + Vector3(0.0, 3.0, 0.0), top)
	assert_int(_impacts.mark_count()).is_equal(1)
	var mark := _impacts.marks()[0]
	assert_object(mark.get_parent()).is_same(body)
	assert_str(mark.surface_name).is_equal("default")
	assert_float(mark.global_basis.z.normalized().dot(Vector3.UP)).is_greater(0.99)


func test_a_shot_at_a_push_cube_marks_it_as_wood_and_the_mark_goes_with_it() -> void:
	var cube := _main.get_node("World/Level/PushCubes/PushCube1") as PhysicsProp
	var top := cube.global_position + Vector3(0.0, cube.size.y / 2.0, 0.0)
	await _shoot(top + Vector3(0.0, 3.0, 0.0), top)
	assert_int(_impacts.mark_count()).is_equal(1)
	var mark := _impacts.marks()[0]
	assert_str(mark.surface_name).is_equal("wood")
	assert_object(mark.get_parent()).is_same(cube)


func test_a_shot_at_the_shuttle_marks_it_as_metal() -> void:
	var shuttle := _main.get_node("World/Level/Platforms/Shuttle") as MovingPlatform
	var top := shuttle.global_position + Vector3(0.0, 3.0, 0.0)
	await _shoot(top, top - Vector3(0.0, 6.0, 0.0))
	assert_int(_impacts.mark_count()).is_equal(1)
	assert_str(_impacts.marks()[0].surface_name).is_equal("metal")
	assert_object(_impacts.marks()[0].get_parent()).is_same(shuttle)
