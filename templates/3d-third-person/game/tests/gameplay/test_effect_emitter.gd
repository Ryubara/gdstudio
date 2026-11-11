# The effect emitter plays an effect at a point or on a node: where it stands, which way it
# points, what it follows, and how it ends and gives its slot back.
extends GdUnitTestSuite

var _world: Node3D
var _emitter: EffectEmitter


func before_test() -> void:
	_world = auto_free(Node3D.new())
	add_child(_world)
	_emitter = load("res://gameplay/effects/effect_emitter.tscn").instantiate() as EffectEmitter
	_emitter.compact = false
	_world.add_child(_emitter)


func after_test() -> void:
	AudioDrain.stop_all(_world)


func test_the_emitter_joins_a_group_and_is_found_from_anywhere_in_the_level() -> void:
	var elsewhere := Node.new()
	_world.add_child(elsewhere)
	assert_object(EffectEmitter.find(elsewhere)).is_same(_emitter)
	assert_object(EffectEmitter.find(auto_free(Node.new()))).is_null()
	assert_object(EffectEmitter.find(null)).is_null()


func test_play_at_stands_the_particles_on_the_point_with_y_along_the_direction() -> void:
	var direction := Vector3(1.0, 1.0, 0.0).normalized()
	var slot := _emitter.play_at(EffectProbe.def(), Vector3(1.0, 2.0, 3.0), direction)
	assert_object(slot).is_not_null()
	assert_bool(slot.active).is_true()
	assert_bool(slot.visible).is_true()
	var burst := slot.emitters()[0] as CPUParticles3D
	assert_bool(burst.emitting).is_true()
	assert_vector(slot.global_position).is_equal_approx(Vector3(1.0, 2.0, 3.0), Vector3.ONE * 1e-4)
	assert_vector(slot.global_basis.y).is_equal_approx(direction, Vector3.ONE * 1e-3)


func test_play_on_points_out_of_the_nodes_minus_z_and_follows_it() -> void:
	var marker := Marker3D.new()
	_world.add_child(marker)
	marker.look_at_from_position(Vector3(0.0, 1.0, 0.0), Vector3(5.0, 1.0, 0.0))
	var slot := _emitter.play_on(EffectProbe.def(), marker)
	assert_vector(slot.global_basis.y).is_equal_approx(-marker.global_basis.z, Vector3.ONE * 1e-3)
	marker.global_position = Vector3(0.0, 1.0, 4.0)
	_emitter.advance(0.02)
	assert_vector(slot.global_position).is_equal_approx(Vector3(0.0, 1.0, 4.0), Vector3.ONE * 1e-4)
	marker.free()
	_emitter.advance(0.02)
	assert_bool(slot.active).is_true()


func test_a_scaled_node_does_not_scale_the_effect() -> void:
	var marker := Marker3D.new()
	marker.scale = Vector3.ONE * 3.0
	_world.add_child(marker)
	var slot := _emitter.play_on(EffectProbe.def(), marker)
	assert_vector(slot.global_basis.get_scale()).is_equal_approx(Vector3.ONE, Vector3.ONE * 1e-4)


func test_an_effect_ends_by_itself_and_frees_its_slot() -> void:
	var effect := EffectProbe.def(true, false, 2.0)
	var slot := _emitter.play_at(effect, Vector3.ZERO)
	var ended: Array[bool] = [false]
	slot.finished.connect(func(_slot: EffectSlot) -> void: ended[0] = true)
	assert_bool(slot.light_on()).is_true()
	_emitter.advance(0.3)
	assert_bool(slot.active).is_true()
	assert_bool(slot.light_on()).is_false()
	_emitter.advance(0.3)
	assert_bool(slot.active).is_false()
	assert_bool(slot.visible).is_false()
	assert_bool((slot.emitters()[0] as CPUParticles3D).emitting).is_false()
	assert_bool(ended[0]).is_true()
	assert_int(_emitter.active_count()).is_equal(0)
	assert_bool(_emitter.is_processing()).is_false()


func test_a_slot_that_ended_is_reused_for_the_same_effect() -> void:
	var effect := EffectProbe.def()
	var first := _emitter.play_at(effect, Vector3.ZERO)
	_emitter.advance(2.0)
	var second := _emitter.play_at(effect, Vector3(4.0, 0.0, 0.0))
	assert_object(second).is_same(first)
	assert_int(_emitter.slot_count()).is_equal(1)
	assert_vector(second.global_position).is_equal_approx(
		Vector3(4.0, 0.0, 0.0), Vector3.ONE * 1e-4
	)


func test_a_slot_that_ended_serves_another_effect_when_the_pool_is_full() -> void:
	_emitter.max_effects = 1
	var first := _emitter.play_at(EffectProbe.def(), Vector3.ZERO)
	_emitter.advance(2.0)
	var second := _emitter.play_at(EffectProbe.def(true, true), Vector3.ZERO)
	assert_object(second).is_same(first)
	assert_object(second.sound_player()).is_not_null()
	assert_int(_emitter.slot_count()).is_equal(1)


func test_a_sound_keeps_the_slot_until_it_has_finished() -> void:
	var slot := _emitter.play_at(EffectProbe.def(false, true), Vector3.ZERO)
	var voice := slot.sound_player()
	assert_bool(voice.playing).is_true()
	assert_bool(voice.bus == &"SFX").is_true()
	_emitter.advance(0.3)
	assert_bool(slot.active).is_true()
	voice.stop()
	_emitter.advance(0.01)
	assert_bool(slot.active).is_false()


func test_a_duration_cuts_the_effect_and_its_sound() -> void:
	var effect := EffectProbe.def(true, true)
	effect.duration = 0.1
	var slot := _emitter.play_at(effect, Vector3.ZERO)
	_emitter.advance(0.05)
	assert_bool(slot.active).is_true()
	_emitter.advance(0.06)
	assert_bool(slot.active).is_false()
	assert_bool(slot.sound_player().playing).is_false()


func test_an_effect_with_only_a_sound_or_only_a_light_plays() -> void:
	var sound_only := _emitter.play_at(EffectProbe.def(false, true), Vector3.ZERO)
	assert_int(sound_only.emitters().size()).is_equal(0)
	assert_bool(sound_only.sound_player().playing).is_true()
	var light_only := _emitter.play_at(EffectProbe.def(false, false, 3.0), Vector3.ZERO)
	assert_bool(light_only.light_on()).is_true()
	_emitter.advance(0.1)
	assert_bool(light_only.active).is_false()


func test_the_light_fades_out_over_its_time() -> void:
	var effect := EffectProbe.def(false, false, 4.0)
	effect.light_time = 0.2
	var slot := _emitter.play_at(effect, Vector3.ZERO)
	assert_float(slot.light().light_energy).is_equal(4.0)
	_emitter.advance(0.1)
	assert_float(slot.light().light_energy).is_equal_approx(2.0, 0.001)
	assert_bool(slot.light().shadow_enabled).is_false()


func test_a_null_effect_plays_nothing() -> void:
	assert_object(_emitter.play_at(null, Vector3.ZERO)).is_null()
	assert_object(_emitter.play_on(EffectProbe.def(), null)).is_null()
	assert_int(_emitter.slot_count()).is_equal(0)
