# The inspector contract of the effect emitter and of `EffectDef`: each export has its default
# pinned, and each live one is changed on an effect that already played and shows in the next play.
extends GdUnitTestSuite

const EMITTER := "res://gameplay/effects/effect_emitter.tscn"

var _world: Node3D
var _emitter: EffectEmitter


func before_test() -> void:
	_world = auto_free(Node3D.new())
	add_child(_world)
	_emitter = load(EMITTER).instantiate() as EffectEmitter
	_emitter.compact = false
	_world.add_child(_emitter)


func after_test() -> void:
	AudioDrain.stop_all(_world)


func test_every_emitter_export_has_its_default_pinned() -> void:
	var pins := {
		&"enabled": true,
		&"particles_enabled": true,
		&"sounds_enabled": true,
		&"lights_enabled": true,
		&"max_effects": 24,
		&"web_max_effects": 12,
		&"max_lights": 2,
		&"warm_up_on_start": true,
		&"warm_up": [],
		&"warm_up_materials": [],
		&"warm_up_every_probe": true,
		&"warm_up_groups": [],
	}
	assert_array(ExportPins.differences(_emitter, pins)).is_empty()
	assert_array(ExportPins.wrong_values(_emitter, pins)).is_empty()
	assert_bool(_emitter.is_in_group(EffectEmitter.GROUP)).is_true()


func test_every_effect_export_has_its_default_pinned() -> void:
	var pins := {
		&"particles": null,
		&"sound": null,
		&"sound_volume_db": -12.0,
		&"sound_bus": &"SFX",
		&"sound_max_distance": 60.0,
		&"light_energy": 0.0,
		&"light_color": Color(1.0, 0.72, 0.38),
		&"light_range": 4.0,
		&"light_time": 0.06,
		&"light_attenuation": 1.0,
		&"light_alone": false,
		&"duration": 0.0,
		&"max_instances": 4,
		&"offset": Vector3.ZERO,
		&"rotation_degrees": Vector3.ZERO,
		&"size": 1.0,
	}
	var fresh := EffectDef.new()
	assert_array(ExportPins.differences(fresh, pins)).is_empty()
	assert_array(ExportPins.wrong_values(fresh, pins)).is_empty()


func test_the_emitter_scene_opens_idle() -> void:
	assert_int(_emitter.slot_count()).is_equal(0)
	assert_bool(_emitter.is_processing()).is_false()


func test_a_sound_and_light_change_shows_in_the_next_play() -> void:
	var effect := EffectProbe.def(true, true, 2.0)
	_emitter.play_at(effect, Vector3.ZERO)
	var slot := _emitter.slots()[0]
	_emitter.stop_all()
	effect.sound_volume_db = -3.0
	effect.sound_bus = &"Ambient"
	effect.sound_max_distance = 12.0
	effect.light_color = Color(0.1, 0.2, 0.9)
	effect.light_energy = 5.0
	effect.light_range = 7.0
	effect.light_attenuation = 0.5
	_emitter.play_at(effect, Vector3.ZERO)
	var voice := slot.sound_player()
	assert_float(voice.volume_db).is_equal(-3.0)
	assert_bool(voice.bus == &"Ambient").is_true()
	assert_float(voice.max_distance).is_equal(12.0)
	assert_object(slot.light().light_color).is_equal(Color(0.1, 0.2, 0.9))
	assert_float(slot.light().light_energy).is_equal(5.0)
	assert_float(slot.light().omni_range).is_equal(7.0)
	assert_float(slot.light().omni_attenuation).is_equal(0.5)


func test_a_timing_and_placement_change_shows_in_the_next_play() -> void:
	var effect := EffectProbe.def(true, false, 2.0)
	var slot := _emitter.play_at(effect, Vector3(1.0, 0.0, 0.0))
	_emitter.stop_all()
	effect.offset = Vector3(0.0, 0.5, 0.0)
	effect.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	effect.size = 3.0
	effect.light_time = 0.5
	effect.duration = 0.9
	slot = _emitter.play_at(effect, Vector3(1.0, 0.0, 0.0))
	assert_vector(slot.global_position).is_equal_approx(Vector3(1.0, 0.5, 0.0), Vector3.ONE * 1e-4)
	assert_vector(slot.global_basis.y).is_equal_approx(Vector3.BACK, Vector3.ONE * 1e-3)
	assert_vector((slot.emitters()[0] as CPUParticles3D).scale).is_equal_approx(
		Vector3.ONE * 3.0, Vector3.ONE * 1e-4
	)
	assert_float(slot.light().omni_range).is_equal_approx(12.0, 0.001)
	_emitter.advance(0.8)
	assert_bool(slot.active).is_true()
	assert_bool(slot.light_on()).is_false()
	_emitter.advance(0.2)
	assert_bool(slot.active).is_false()


func test_a_new_particles_scene_is_built_in_the_slot_at_the_next_play() -> void:
	var effect := EffectProbe.def()
	var slot := _emitter.play_at(effect, Vector3.ZERO)
	var first := slot.emitters()[0]
	_emitter.stop_all()
	effect.particles = load("res://gameplay/impacts/effects/impact_sparks.tscn")
	_emitter.play_at(effect, Vector3.ZERO)
	assert_bool(is_instance_valid(first) and not first.is_queued_for_deletion()).is_false()
	assert_str(slot.emitters()[0].scene_file_path).ends_with("impact_sparks.tscn")
	assert_int(slot.emitters().size()).is_equal(1)


func test_a_pool_and_switch_change_shows_in_the_next_play() -> void:
	_emitter.max_lights = 1
	var effect := EffectProbe.def(true, false, 2.0)
	_emitter.play_at(effect, Vector3.ZERO)
	_emitter.play_at(effect, Vector3.ZERO)
	assert_int(_emitter.light_count()).is_equal(1)
	_emitter.stop_all()
	_emitter.max_lights = 2
	_emitter.play_at(effect, Vector3.ZERO)
	_emitter.play_at(effect, Vector3.ZERO)
	assert_int(_emitter.light_count()).is_equal(2)
