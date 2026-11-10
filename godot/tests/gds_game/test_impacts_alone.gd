# `Impacts`, `ImpactSurface` and `ImpactMark` of `gds_game` on their own: a hit picks its surface,
# leaves a mark at the point facing the normal on the body it hit, the cap takes the oldest and
# the lifetime fades a mark out. The hits are handed to `impact()`, so no shot or physics step is
# waited on; a game's suites shoot real shots in a level (3D Third Person's `test_impacts.gd`).
extends GdUnitTestSuite

const NEAR := Vector3.ONE * 0.001

var _impacts: Impacts
var _wall: StaticBody3D
var _made: Array[ImpactSurface] = []


func before_test() -> void:
	_made.clear()
	_impacts = auto_free(Impacts.new())
	_impacts.mark_material = StandardMaterial3D.new()
	_impacts.impact_made.connect(_on_impact_made)
	_impacts.add_child(_surface(&"default"))
	_impacts.add_child(_surface(&"wood"))
	add_child(_impacts)
	_wall = auto_free(StaticBody3D.new())
	add_child(_wall)


func _on_impact_made(surface: ImpactSurface, _collider: Object, _at: Vector3, _n: Vector3) -> void:
	_made.append(surface)


func _surface(surface_name: StringName) -> ImpactSurface:
	var surface := ImpactSurface.new()
	surface.name = String(surface_name)
	surface.surface_name = surface_name
	return surface


func _name_of(body: Object) -> String:
	return String(_impacts.surface_for(body).surface_name)


func test_a_hit_leaves_a_mark_on_the_body_at_the_point_facing_the_normal() -> void:
	var point := Vector3(1.0, 1.5, 0.0)
	assert_object(_impacts.impact(_wall, point, Vector3.BACK)).is_not_null()
	assert_int(_impacts.mark_count()).is_equal(1)
	var mark := _impacts.marks()[0]
	assert_object(mark.get_parent()).is_same(_wall)
	var lifted := point + Vector3.BACK * _impacts.surface_offset
	assert_vector(mark.global_position).is_equal_approx(lifted, NEAR)
	assert_vector(mark.global_basis.z.normalized()).is_equal_approx(Vector3.BACK, NEAR)
	assert_array(_made).has_size(1)


func test_a_body_names_its_surface_by_metadata_or_group_or_gets_the_default() -> void:
	assert_str(_name_of(_wall)).is_equal("default")
	_wall.set_meta(&"surface", &"wood")
	assert_str(_name_of(_wall)).is_equal("wood")
	_wall.remove_meta(&"surface")
	_wall.add_to_group(&"wood")
	assert_str(_name_of(_wall)).is_equal("wood")
	_wall.remove_from_group(&"wood")
	_wall.set_meta(&"surface", &"glass")
	assert_str(_name_of(_wall)).is_equal("default")


func test_a_character_takes_no_mark_but_the_hit_is_still_reported() -> void:
	var body: CharacterBody3D = auto_free(CharacterBody3D.new())
	add_child(body)
	_impacts.impact(body, Vector3.ZERO, Vector3.UP)
	assert_int(_impacts.mark_count()).is_equal(0)
	assert_array(_made).has_size(1)


func test_a_ragdoll_bone_takes_a_mark_and_clearing_it_takes_only_its_marks() -> void:
	var bone: PhysicalBone3D = auto_free(PhysicalBone3D.new())
	add_child(bone)
	_impacts.impact(bone, Vector3(0.0, 1.0, 0.1), Vector3.BACK)
	_impacts.impact(_wall, Vector3(0.0, 1.0, 0.0), Vector3.BACK)
	assert_int(_impacts.mark_count()).is_equal(2)
	assert_object(_impacts.marks()[0].get_parent()).is_same(bone)
	_impacts.clear_marks_on(bone)
	await get_tree().process_frame
	assert_int(_impacts.mark_count()).is_equal(1)
	assert_object(_impacts.marks()[0].get_parent()).is_same(_wall)


func test_the_cap_takes_the_oldest_mark_first() -> void:
	_impacts.max_marks = 2
	for x in 3:
		_impacts.impact(_wall, Vector3(x, 1.0, 0.0), Vector3.BACK)
	assert_int(_impacts.mark_count()).is_equal(2)
	assert_float(_impacts.marks()[0].global_position.x).is_equal_approx(1.0, 0.001)
	_impacts.max_marks = 0
	assert_int(_impacts.mark_count()).is_equal(0)


func test_a_mark_fades_at_the_end_of_its_life_and_then_goes() -> void:
	_impacts.mark_lifetime = 1.0
	_impacts.mark_fade_time = 0.5
	_impacts.impact(_wall, Vector3.ZERO, Vector3.BACK)
	var mark := _impacts.marks()[0]
	_impacts._physics_process(0.75)
	assert_float(mark.fade()).is_equal_approx(0.5, 0.001)
	_impacts._physics_process(0.5)
	assert_int(_impacts.mark_count()).is_equal(0)


func test_a_surface_without_marks_and_marks_off_leave_none() -> void:
	_impacts.surface_for(_wall).leaves_mark = false
	_impacts.impact(_wall, Vector3.ZERO, Vector3.BACK)
	assert_int(_impacts.mark_count()).is_equal(0)
	_impacts.surface_for(_wall).leaves_mark = true
	_impacts.marks_enabled = false
	_impacts.impact(_wall, Vector3.ZERO, Vector3.BACK)
	assert_int(_impacts.mark_count()).is_equal(0)


func test_without_a_surface_a_hit_shows_nothing_and_says_so() -> void:
	var bare: Impacts = auto_free(Impacts.new())
	add_child(bare)
	assert_object(bare.impact(_wall, Vector3.ZERO, Vector3.UP)).is_null()
	assert_array(Array(bare._get_configuration_warnings())).has_size(1)
