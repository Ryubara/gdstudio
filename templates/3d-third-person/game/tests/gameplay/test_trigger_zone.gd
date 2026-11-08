# The trigger zone's inspector contract: every export has its default pinned, and each one that has
# an effect is changed on a running zone and its effect read.
extends GdUnitTestSuite

const SCENE := "res://gameplay/trigger_zone/trigger_zone.tscn"

var _zone: TriggerZone


func before_test() -> void:
	_zone = load(SCENE).instantiate() as TriggerZone
	add_child(_zone)
	await get_tree().process_frame


func after_test() -> void:
	_zone.free()


func _plate() -> MeshInstance3D:
	return _zone.get_node("%Plate") as MeshInstance3D


func _paint() -> Color:
	return (_plate().material_override as StandardMaterial3D).albedo_color


func test_every_export_has_its_default_pinned() -> void:
	var pins := {
		&"size": Vector3(3.0, 1.0, 3.0),
		&"counts": TriggerZone.Counts.CHARACTERS_AND_PROPS,
		&"required_group": &"",
		&"fire_once": false,
		&"show_plate": false,
		&"plate_idle_color": Color(0.75, 0.2, 0.15),
		&"plate_active_color": Color(0.3, 0.75, 0.3),
	}
	assert_array(ExportPins.differences(_zone, pins)).is_empty()
	assert_array(ExportPins.wrong_values(_zone, pins)).is_empty()


func test_the_scene_holds_its_parts_and_has_no_warning() -> void:
	assert_object(_zone.get_node("%Shape")).is_not_null()
	assert_object(_plate()).is_not_null()
	assert_array(_zone._get_configuration_warnings()).is_empty()


func test_the_size_resizes_the_box_and_the_plate() -> void:
	_zone.size = Vector3(5.0, 2.0, 4.0)
	var box := (_zone.get_node("%Shape") as CollisionShape3D).shape as BoxShape3D
	assert_vector(box.size).is_equal(Vector3(5.0, 2.0, 4.0))
	assert_vector((_plate().mesh as BoxMesh).size).is_equal(Vector3(5.0, 0.1, 4.0))
	assert_float(_plate().position.y).is_equal_approx(-0.95, 0.001)


func test_two_zones_do_not_share_a_size() -> void:
	var other := load(SCENE).instantiate() as TriggerZone
	add_child(other)
	other.size = Vector3(9.0, 9.0, 9.0)
	var box := (_zone.get_node("%Shape") as CollisionShape3D).shape as BoxShape3D
	assert_vector(box.size).is_equal(Vector3(3.0, 1.0, 3.0))
	other.free()


func test_the_plate_shows_only_when_asked() -> void:
	assert_bool(_plate().visible).is_false()
	_zone.show_plate = true
	assert_bool(_plate().visible).is_true()
	_zone.show_plate = false
	assert_bool(_plate().visible).is_false()


func test_the_plate_colours_follow_who_stands_on_it() -> void:
	_zone.show_plate = true
	_zone.plate_idle_color = Color(0.1, 0.1, 0.9)
	_zone.plate_active_color = Color(0.9, 0.9, 0.1)
	assert_object(_paint()).is_equal(Color(0.1, 0.1, 0.9))
	var body := CharacterBody3D.new()
	_zone._on_body_entered(body)
	assert_object(_paint()).is_equal(Color(0.9, 0.9, 0.1))
	_zone.plate_active_color = Color(0.5, 0.5, 0.5)
	assert_object(_paint()).is_equal(Color(0.5, 0.5, 0.5))
	_zone._on_body_exited(body)
	assert_object(_paint()).is_equal(Color(0.1, 0.1, 0.9))
	body.free()


func test_the_required_group_decides_which_bodies_count() -> void:
	var player := CharacterBody3D.new()
	player.add_to_group(&"player")
	var crate := CharacterBody3D.new()
	_zone.required_group = &"player"
	_zone._on_body_entered(crate)
	assert_bool(_zone.is_active()).is_false()
	_zone._on_body_entered(player)
	assert_bool(_zone.is_active()).is_true()
	_zone.required_group = &""
	_zone._on_body_entered(crate)
	assert_int(_zone.occupant_count()).is_equal(2)
	player.free()
	crate.free()


func test_fire_once_ignores_everything_after_the_first_time() -> void:
	var times := []
	_zone.activated.connect(func(_body: Node3D) -> void: times.append(true))
	_zone.fire_once = true
	var one := CharacterBody3D.new()
	var two := CharacterBody3D.new()
	_zone._on_body_entered(one)
	_zone._on_body_exited(one)
	_zone._on_body_entered(two)
	assert_array(times).has_size(1)
	one.free()
	two.free()


func test_counts_decides_which_kinds_of_body_count() -> void:
	var walker := CharacterBody3D.new()
	var crate := RigidBody3D.new()
	var wall := StaticBody3D.new()
	var lift := AnimatableBody3D.new()
	_zone.counts = TriggerZone.Counts.CHARACTERS
	for body in [crate, wall, lift]:
		_zone._on_body_entered(body)
	assert_bool(_zone.is_active()).is_false()
	_zone._on_body_entered(walker)
	assert_int(_zone.occupant_count()).is_equal(1)
	_zone.counts = TriggerZone.Counts.CHARACTERS_AND_PROPS
	for body in [crate, wall, lift]:
		_zone._on_body_entered(body)
	assert_int(_zone.occupant_count()).is_equal(2)
	_zone.counts = TriggerZone.Counts.ANY
	for body in [wall, lift]:
		_zone._on_body_entered(body)
	assert_int(_zone.occupant_count()).is_equal(4)
	for body in [walker, crate, wall, lift]:
		body.free()
