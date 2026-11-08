# The pickup's inspector contract: every export has its default pinned, and each one that has an
# effect is changed on a running pickup and its effect read.
extends GdUnitTestSuite

const SCENE := "res://gameplay/pickup/pickup.tscn"

var _pickup: Pickup


func before_test() -> void:
	_pickup = load(SCENE).instantiate() as Pickup
	add_child(_pickup)
	await get_tree().process_frame


func after_test() -> void:
	if is_instance_valid(_pickup):
		AudioDrain.stop_all(_pickup)
		_pickup.free()


func _visual() -> MeshInstance3D:
	return _pickup.get_node("%Visual") as MeshInstance3D


func test_every_export_has_its_default_pinned() -> void:
	var pins := {
		&"item_id": &"coin",
		&"amount": 1,
		&"characters_only": true,
		&"tint": Color(1.0, 0.78, 0.2),
		&"item_size": 0.5,
		&"spin_speed": 120.0,
		&"bob_height": 0.12,
		&"bob_period": 1.6,
		&"sounds": _pickup.sounds,
		&"pitch_variation": 0.04,
		&"respawn_time": 0.0,
	}
	assert_array(ExportPins.differences(_pickup, pins)).is_empty()
	assert_array(ExportPins.wrong_values(_pickup, pins)).is_empty()


func test_the_scene_holds_its_parts_and_has_no_warning() -> void:
	assert_object(_visual()).is_not_null()
	assert_object(_pickup.get_node("%Shape")).is_not_null()
	assert_array(_pickup._get_configuration_warnings()).is_empty()


func test_the_tint_colours_the_gem_and_its_glow() -> void:
	_pickup.tint = Color(0.2, 0.4, 0.9)
	var paint := _visual().material_override as StandardMaterial3D
	assert_object(paint.albedo_color).is_equal(Color(0.2, 0.4, 0.9))
	assert_object(paint.emission).is_equal(Color(0.2, 0.4, 0.9))


func test_the_size_resizes_the_gem_and_the_touch_shape() -> void:
	_pickup.item_size = 1.2
	assert_float((_visual().mesh as SphereMesh).radius).is_equal_approx(0.6, 0.0001)
	var shape := (_pickup.get_node("%Shape") as CollisionShape3D).shape as SphereShape3D
	assert_float(shape.radius).is_equal_approx(1.2 * 0.75, 0.001)


func test_two_pickups_do_not_share_a_tint() -> void:
	var other := load(SCENE).instantiate() as Pickup
	add_child(other)
	other.tint = Color(0.0, 1.0, 0.0)
	var paint := _visual().material_override as StandardMaterial3D
	assert_object(paint.albedo_color).is_equal(Color(1.0, 0.78, 0.2))
	other.free()


func test_the_spin_follows_its_speed() -> void:
	_pickup.spin_speed = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(_visual().rotation.y).is_equal(0.0)
	_pickup.spin_speed = 360.0
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(_visual().rotation.y).is_not_equal(0.0)


func test_the_bob_follows_its_height_and_period() -> void:
	_pickup.bob_height = 0.0
	await get_tree().process_frame
	assert_float(_visual().position.y).is_equal(0.0)
	_pickup.bob_height = 0.5
	_pickup.bob_period = 1.0
	_pickup._phase = 0.25
	await get_tree().process_frame
	assert_float(_visual().position.y).is_greater(0.4)


func test_the_item_and_the_amount_are_what_collected_says() -> void:
	var got := []
	_pickup.collected.connect(
		func(_who: Node3D, id: StringName, n: int) -> void: got.append([id, n])
	)
	_pickup.item_id = &"gem"
	_pickup.amount = 7
	var taker := CharacterBody3D.new()
	_pickup._on_body_entered(taker)
	assert_array(got).is_equal([[&"gem", 7]])
	taker.free()


func test_a_respawn_time_brings_it_back_and_zero_removes_it() -> void:
	var taker := CharacterBody3D.new()
	_pickup.respawn_time = 0.3
	_pickup._on_body_entered(taker)
	assert_bool(_pickup.is_available()).is_false()
	await get_tree().create_timer(0.5).timeout
	assert_bool(_pickup.is_available()).is_true()
	_pickup.respawn_time = 0.0
	_pickup.sounds = []
	_pickup._on_body_entered(taker)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(is_instance_valid(_pickup)).is_false()
	taker.free()


func test_collecting_plays_one_of_the_coin_sounds_on_the_sfx_bus_and_it_finishes_first() -> void:
	var sound := _pickup.get_node("%Sound") as AudioStreamPlayer3D
	assert_str(String(sound.bus)).is_equal("SFX")
	assert_int(_pickup.sounds.size()).is_equal(4)
	var taker := CharacterBody3D.new()
	_pickup.respawn_time = 0.0
	_pickup._on_body_entered(taker)
	assert_bool(sound.playing).is_true()
	assert_bool(_pickup.sounds.has(sound.stream)).is_true()
	# It hides at once but stays until the sound has played (about 0.4 s), then goes.
	await get_tree().process_frame
	assert_bool(is_instance_valid(_pickup)).is_true()
	assert_bool(_pickup.is_available()).is_false()
	await get_tree().create_timer(0.7).timeout
	assert_bool(is_instance_valid(_pickup)).is_false()
	taker.free()


func test_two_pickups_in_a_row_do_not_play_the_same_file_and_the_pitch_varies() -> void:
	var sound := _pickup.get_node("%Sound") as AudioStreamPlayer3D
	var taker := CharacterBody3D.new()
	_pickup.respawn_time = 0.2
	var seen := {}
	var last: AudioStream = null
	for _round in 8:
		_pickup._on_body_entered(taker)
		assert_object(sound.stream).is_not_same(last)
		last = sound.stream
		seen[sound.pitch_scale] = true
		_pickup._show_again()
	assert_int(seen.size()).is_greater(3)
	taker.free()


func test_a_pickup_with_no_sounds_plays_nothing_and_goes_at_once() -> void:
	_pickup.sounds = []
	var taker := CharacterBody3D.new()
	_pickup._on_body_entered(taker)
	assert_bool((_pickup.get_node("%Sound") as AudioStreamPlayer3D).playing).is_false()
	taker.free()


func test_the_pitch_variation_is_live() -> void:
	var sound := _pickup.get_node("%Sound") as AudioStreamPlayer3D
	var taker := CharacterBody3D.new()
	_pickup.respawn_time = 0.2
	_pickup.pitch_variation = 0.0
	_pickup._on_body_entered(taker)
	assert_float(sound.pitch_scale).is_equal(1.0)
	taker.free()


func test_characters_only_decides_whether_a_plain_body_can_take_it() -> void:
	var got := []
	_pickup.collected.connect(func(who: Node3D, _id: StringName, _n: int) -> void: got.append(who))
	var block := StaticBody3D.new()
	_pickup._on_body_entered(block)
	assert_array(got).is_empty()
	assert_bool(_pickup.is_available()).is_true()
	_pickup.characters_only = false
	_pickup._on_body_entered(block)
	assert_array(got).is_equal([block])
	block.free()
