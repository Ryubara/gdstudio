# The effect emitter's pool: it is capped, it reuses its slots, an effect has its own limit, a full
# pool cuts the oldest, lights are limited, each part switches off, and nothing is left behind.
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


func test_the_pool_never_grows_past_its_cap() -> void:
	_emitter.max_effects = 3
	for step in 12:
		_emitter.play_at(EffectProbe.def(), Vector3(float(step), 0.0, 0.0))
	assert_int(_emitter.slot_count()).is_equal(3)
	assert_int(_emitter.active_count()).is_equal(3)


func test_a_full_pool_cuts_the_oldest_effect_for_the_new_one() -> void:
	_emitter.max_effects = 2
	var first := _emitter.play_at(EffectProbe.def(), Vector3.ZERO)
	_emitter.advance(0.1)
	var second := _emitter.play_at(EffectProbe.def(), Vector3.ZERO)
	_emitter.advance(0.1)
	var third := _emitter.play_at(EffectProbe.def(), Vector3(9.0, 0.0, 0.0))
	assert_object(third).is_same(first)
	assert_float(third.age).is_equal(0.0)
	assert_float(second.age).is_greater(0.0)


func test_an_effect_has_its_own_limit_of_instances() -> void:
	var effect := EffectProbe.def()
	effect.max_instances = 2
	var other := EffectProbe.def()
	for step in 6:
		_emitter.play_at(effect, Vector3(float(step), 0.0, 0.0))
	_emitter.play_at(other, Vector3.ZERO)
	assert_int(_emitter.slot_count()).is_equal(3)
	var mine := 0
	for slot in _emitter.slots():
		mine += 1 if slot.effect == effect else 0
	assert_int(mine).is_equal(2)


func test_the_web_build_uses_the_smaller_pool() -> void:
	_emitter.max_effects = 8
	_emitter.web_max_effects = 2
	assert_int(_emitter.pool_cap()).is_equal(8)
	_emitter.compact = true
	assert_int(_emitter.pool_cap()).is_equal(2)
	for step in 6:
		_emitter.play_at(EffectProbe.def(), Vector3(float(step), 0.0, 0.0))
	assert_int(_emitter.slot_count()).is_equal(2)


func test_lowering_the_cap_takes_slots_away_at_once() -> void:
	for step in 6:
		_emitter.play_at(EffectProbe.def(), Vector3(float(step), 0.0, 0.0))
	assert_int(_emitter.slot_count()).is_equal(6)
	_emitter.advance(2.0)
	_emitter.max_effects = 2
	assert_int(_emitter.slot_count()).is_equal(2)
	_emitter.max_effects = 0
	assert_int(_emitter.slot_count()).is_equal(0)
	assert_object(_emitter.play_at(EffectProbe.def(), Vector3.ZERO)).is_null()


func test_only_max_lights_flash_at_once() -> void:
	_emitter.max_lights = 2
	for step in 5:
		_emitter.play_at(EffectProbe.def(true, false, 2.0), Vector3(float(step), 0.0, 0.0))
	assert_int(_emitter.active_count()).is_equal(5)
	assert_int(_emitter.light_count()).is_equal(2)
	_emitter.advance(0.1)
	assert_int(_emitter.light_count()).is_equal(0)
	_emitter.max_lights = 0
	_emitter.play_at(EffectProbe.def(true, false, 2.0), Vector3.ZERO)
	assert_int(_emitter.light_count()).is_equal(0)


func test_each_part_and_the_whole_switch_off() -> void:
	var effect := EffectProbe.def(true, true, 2.0)
	_emitter.particles_enabled = false
	var slot := _emitter.play_at(effect, Vector3.ZERO)
	assert_int(slot.emitters().size()).is_equal(0)
	assert_bool(slot.sound_player().playing).is_true()
	assert_bool(slot.light_on()).is_true()
	_emitter.stop_all()
	_emitter.particles_enabled = true
	_emitter.sounds_enabled = false
	_emitter.lights_enabled = false
	slot = _emitter.play_at(effect, Vector3.ZERO)
	assert_bool((slot.emitters()[0] as CPUParticles3D).emitting).is_true()
	assert_bool(slot.sound_player().playing).is_false()
	assert_bool(slot.light_on()).is_false()
	_emitter.enabled = false
	assert_object(_emitter.play_at(effect, Vector3.ZERO)).is_null()


func test_a_play_can_leave_out_its_particles_or_its_sound() -> void:
	var effect := EffectProbe.def(true, true)
	var slot := _emitter.play_at(effect, Vector3.ZERO, Vector3.UP, false, true)
	assert_int(slot.emitters().size()).is_equal(0)
	assert_bool(slot.sound_player().playing).is_true()
	_emitter.stop_all()
	slot = _emitter.play_at(effect, Vector3.ZERO, Vector3.UP, true, false)
	assert_bool((slot.emitters()[0] as CPUParticles3D).emitting).is_true()
	assert_bool(slot.sound_player().playing).is_false()


func test_a_slot_taken_over_with_fewer_parts_hides_what_it_does_not_play() -> void:
	_emitter.max_effects = 1
	var slot := _emitter.play_at(EffectProbe.def(true, true, 2.0), Vector3.ZERO)
	var swept := _emitter.play_at(EffectProbe.def(false, false), Vector3.ZERO)
	assert_object(swept).is_same(slot)
	assert_bool(slot.light_on()).is_false()
	assert_bool(slot.sound_player().playing).is_false()
	assert_bool((slot.emitters()[0] as CPUParticles3D).visible).is_false()


func _play_many(effect: EffectDef) -> void:
	for step in 100:
		_emitter.play_at(effect, Vector3(float(step % 7), 0.0, 0.0))
		_emitter.advance(0.2)
		if step % 3 == 0:
			_emitter.stop_all()
	_emitter.stop_all()


func test_many_plays_leave_the_same_nodes_behind_once_the_pool_is_warm() -> void:
	var effect := EffectProbe.def(true, true, 2.0)
	_play_many(effect)
	var slots_before := _emitter.slot_count()
	var nodes_before := EffectProbe.nodes_under(_emitter)
	_play_many(effect)
	assert_int(_emitter.slot_count()).is_equal(slots_before)
	assert_int(slots_before).is_less_equal(effect.max_instances)
	assert_int(EffectProbe.nodes_under(_emitter)).is_equal(nodes_before)
	assert_int(_emitter.light_count()).is_equal(0)


func test_stop_all_ends_every_effect() -> void:
	for step in 4:
		_emitter.play_at(EffectProbe.def(true, true, 2.0), Vector3(float(step), 0.0, 0.0))
	_emitter.stop_all()
	assert_int(_emitter.active_count()).is_equal(0)
	assert_int(_emitter.light_count()).is_equal(0)
	for slot in _emitter.slots():
		assert_bool(slot.visible).is_false()


func _warm_emitter(effect: EffectDef) -> EffectEmitter:
	var fresh := auto_free(EffectEmitter.new()) as EffectEmitter
	fresh.warm_up = [effect]
	_world.add_child(fresh)
	return fresh


func test_warm_up_builds_the_slots_of_the_listed_effects_without_playing_them() -> void:
	var effect := EffectProbe.def(true, true)
	var fresh := _warm_emitter(effect)
	assert_bool(fresh.is_warming()).is_true()
	await fresh.warmed
	assert_int(fresh.slot_count()).is_equal(1)
	assert_int(fresh.active_count()).is_equal(0)
	assert_int(fresh.slots()[0].emitters().size()).is_equal(1)
	var slot := fresh.play_at(effect, Vector3.ZERO)
	assert_object(slot).is_same(fresh.slots()[0])
	assert_int(fresh.slot_count()).is_equal(1)


func test_the_warm_up_draws_the_effect_unseen_in_front_of_the_camera_and_ends() -> void:
	var camera := auto_free(Camera3D.new()) as Camera3D
	_world.add_child(camera)
	camera.make_current()
	var effect := EffectProbe.def(true, true, 4.0)
	effect.light_time = 1.0
	var fresh := _warm_emitter(effect)
	var seen_without_light := false
	while fresh.light_count() == 0 and fresh.is_warming():
		seen_without_light = seen_without_light or fresh.active_count() == 1
		await get_tree().process_frame
	# Drawn first without its light and then with it: a surface an omni light reaches takes another
	# program.
	assert_bool(seen_without_light).is_true()
	assert_int(fresh.active_count()).is_equal(1)
	var slot := fresh.slots()[0]
	assert_vector(slot.global_position).is_equal_approx(Vector3(0.0, 0.0, -2.0), Vector3.ONE * 1e-3)
	assert_float(slot.light().light_energy).is_less(0.05)
	assert_vector((slot.emitters()[0] as CPUParticles3D).scale).is_equal_approx(
		Vector3.ONE * 0.01, Vector3.ONE * 1e-4
	)
	assert_bool(slot.sound_player() == null or not slot.sound_player().playing).is_true()
	await fresh.warmed
	assert_int(fresh.active_count()).is_equal(0)
	assert_int(fresh.light_count()).is_equal(0)
	assert_bool(fresh.is_warming()).is_false()


func test_a_level_can_turn_the_warm_up_off_and_the_slots_are_still_built() -> void:
	var camera := auto_free(Camera3D.new()) as Camera3D
	_world.add_child(camera)
	camera.make_current()
	var fresh := auto_free(EffectEmitter.new()) as EffectEmitter
	fresh.warm_up_on_start = false
	fresh.warm_up = [EffectProbe.def(true, false, 2.0)]
	_world.add_child(fresh)
	var drawn := false
	while fresh.is_warming():
		drawn = drawn or fresh.active_count() > 0
		await get_tree().process_frame
	assert_bool(drawn).is_false()
	assert_int(fresh.slot_count()).is_equal(1)


func test_a_weapon_and_the_impact_surfaces_register_their_effects_for_the_warm_up() -> void:
	var weapon := auto_free(load("res://gameplay/weapon/weapon.tscn").instantiate()) as Weapon
	var impacts := auto_free(load("res://gameplay/impacts/impacts.tscn").instantiate()) as Impacts
	_world.add_child(weapon)
	_world.add_child(impacts)
	await _emitter.warmed
	var held: Array[EffectDef] = []
	for slot in _emitter.slots():
		held.append(slot.effect)
	assert_bool(held.has(weapon.muzzle_flash)).is_true()
	for surface: ImpactSurface in impacts.surfaces_by_name().values():
		assert_bool(held.has(surface.effect)).is_true()
	assert_int(_emitter.active_count()).is_equal(0)
