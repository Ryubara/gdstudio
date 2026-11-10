# What a hit does by the kind of surface: the surface comes from a body's metadata or group (or a
# parent's) with a default for the rest, the effect bursts at the hit standing on the normal, the
# sound plays there, and the template nodes a developer edits show in the next hit. The weapon and
# the projectile switch it off.
extends GdUnitTestSuite

const WEAPON := "res://gameplay/weapon/weapon.tscn"
const TARGET := "res://gameplay/target/target.tscn"
const PROP := "res://gameplay/physics_prop/physics_prop.tscn"

var _arena: PlayArena
var _impacts: Impacts
var _wall: StaticBody3D


func before_test() -> void:
	_arena = auto_free(ImpactShots.world(self))
	_impacts = ImpactShots.impacts_of(_arena)
	_wall = _arena.add_block(Vector2(0.0, -5.0), Vector3(10.0, 4.0, 0.5), 4.0)
	await get_tree().physics_frame


func after_test() -> void:
	AudioDrain.stop_all(_arena)


func _surface(named: StringName) -> ImpactSurface:
	return _impacts.surfaces_by_name()[named]


func _body() -> StaticBody3D:
	var body := auto_free(StaticBody3D.new()) as StaticBody3D
	_arena.add_child(body)
	return body


func test_the_template_has_a_default_and_a_surface_each_for_wood_metal_and_the_target() -> void:
	var names: Array[String] = []
	for surface_name: StringName in _impacts.surfaces_by_name():
		names.append(String(surface_name))
	names.sort()
	assert_array(names).is_equal(["default", "metal", "target", "wood"])
	assert_object(_impacts.default_surface).is_same(_surface(&"default"))
	assert_bool(_surface(&"target").leaves_mark).is_false()
	for surface: ImpactSurface in _impacts.surfaces_by_name().values():
		assert_object(surface.effect).is_not_null()
		assert_object(surface.sound).is_not_null()
		assert_object(surface.sound.stream).is_not_null()
		assert_bool(surface.sound.bus == &"SFX").is_true()


func test_a_body_with_no_surface_gets_the_default() -> void:
	assert_object(_impacts.surface_for(_wall)).is_same(_surface(&"default"))
	assert_object(_impacts.surface_for(null)).is_same(_surface(&"default"))


func test_a_body_names_its_surface_by_metadata() -> void:
	var body := _body()
	body.set_meta(&"surface", &"metal")
	assert_object(_impacts.surface_for(body)).is_same(_surface(&"metal"))
	body.set_meta(&"surface", "wood")
	assert_object(_impacts.surface_for(body)).is_same(_surface(&"wood"))


func test_a_body_names_its_surface_by_group() -> void:
	var body := _body()
	body.add_to_group(&"wood")
	assert_object(_impacts.surface_for(body)).is_same(_surface(&"wood"))


func test_a_body_takes_its_surface_from_the_nearest_parent_that_has_one() -> void:
	var crates := auto_free(Node3D.new()) as Node3D
	crates.set_meta(&"surface", &"wood")
	_arena.add_child(crates)
	var body := StaticBody3D.new()
	crates.add_child(body)
	assert_object(_impacts.surface_for(body)).is_same(_surface(&"wood"))
	body.set_meta(&"surface", &"metal")
	assert_object(_impacts.surface_for(body)).is_same(_surface(&"metal"))


func test_an_unknown_surface_name_falls_back_to_the_default() -> void:
	var body := _body()
	body.set_meta(&"surface", &"glass")
	assert_object(_impacts.surface_for(body)).is_same(_surface(&"default"))


func test_a_surface_renamed_while_the_game_runs_is_found_by_its_new_name() -> void:
	var body := _body()
	body.set_meta(&"surface", &"rubber")
	var wood := _surface(&"wood")
	wood.surface_name = &"rubber"
	assert_object(_impacts.surface_for(body)).is_same(wood)


func test_the_maps_props_platforms_and_targets_say_what_they_are_made_of() -> void:
	var crate := auto_free(load(PROP).instantiate()) as PhysicsProp
	var board := auto_free(load(TARGET).instantiate()) as Target
	_arena.add_child(crate)
	_arena.add_child(board)
	assert_object(_impacts.surface_for(crate)).is_same(_surface(&"wood"))
	assert_object(_impacts.surface_for(board)).is_same(_surface(&"target"))
