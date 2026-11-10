# What a hit does on its surface: the effect (an `EffectDef` played by the level's emitter) bursts
# at the hit standing on the normal and its sound plays there, and a change to the effect shows in
# the next hit. The impacts, the weapon and the projectile each switch it off.
extends GdUnitTestSuite

const WEAPON := "res://gameplay/weapon/weapon.tscn"
const TARGET := "res://gameplay/target/target.tscn"

var _arena: PlayArena
var _impacts: Impacts
var _emitter: EffectEmitter
var _wall: StaticBody3D


func before_test() -> void:
	_arena = auto_free(ImpactShots.world(self))
	_impacts = ImpactShots.impacts_of(_arena)
	_emitter = ImpactShots.emitter_of(_arena)
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


func _slots_of(surface: ImpactSurface) -> Array[EffectSlot]:
	var found: Array[EffectSlot] = []
	for slot in _emitter.slots():
		if slot.effect == surface.effect:
			found.append(slot)
	return found


func test_a_hit_bursts_the_effect_on_the_normal_and_plays_the_sound_at_the_point() -> void:
	var body := _body()
	body.set_meta(&"surface", &"wood")
	var point := Vector3(1.0, 2.0, 3.0)
	var normal := Vector3(0.0, 0.0, 1.0)
	var surface := _impacts.impact(body, point, normal)
	assert_object(surface).is_same(_surface(&"wood"))
	var slots := _slots_of(surface)
	assert_int(slots.size()).is_equal(1)
	var burst := slots[0].emitters()[0] as CPUParticles3D
	assert_bool(burst.emitting).is_true()
	assert_vector(burst.global_position).is_equal_approx(point, Vector3.ONE * 0.0001)
	assert_vector(burst.global_basis.y).is_equal_approx(normal, Vector3.ONE * 0.001)
	var voice := slots[0].sound_player()
	assert_bool(voice.playing).is_true()
	assert_vector(voice.global_position).is_equal_approx(point, Vector3.ONE * 0.0001)
	assert_bool(voice.bus == &"SFX").is_true()


func test_each_surface_plays_its_own_sound_and_effect() -> void:
	var streams := {}
	for named: StringName in [&"default", &"wood", &"metal", &"target"]:
		var body := _body()
		body.set_meta(&"surface", named)
		var surface := _impacts.impact(body, Vector3(0.0, 1.0, 0.0), Vector3.UP)
		assert_str(surface.surface_name).is_equal(String(named))
		var voice := _slots_of(surface)[0].sound_player()
		streams[named] = voice.stream.get_instance_id()
	var distinct := {}
	for value in streams.values():
		distinct[value] = true
	# default, wood and metal each have their own sounds; the target shares the metal's.
	assert_int(distinct.size()).is_equal(3)


func test_a_burst_of_hits_reuses_the_surface_effects_slots_up_to_its_max_instances() -> void:
	var surface := _surface(&"default")
	surface.effect.max_instances = 2
	for step in 5:
		_impacts.impact(_wall, Vector3(float(step), 1.0, -4.75), Vector3.BACK)
	assert_int(_slots_of(surface).size()).is_equal(2)
	assert_int(_emitter.active_count()).is_equal(2)


func test_a_change_to_the_effect_shows_in_the_next_hit() -> void:
	var surface := _surface(&"default")
	_impacts.impact(_wall, Vector3(0.0, 1.0, -4.75), Vector3.BACK)
	var voice := _slots_of(surface)[0].sound_player()
	surface.effect.sound_volume_db = -3.0
	surface.effect.sound_max_distance = 25.0
	surface.effect.max_instances = 1
	_impacts.impact(_wall, Vector3(1.0, 1.0, -4.75), Vector3.BACK)
	assert_float(voice.volume_db).is_equal(-3.0)
	assert_float(voice.max_distance).is_equal(25.0)
	assert_int(_slots_of(surface).size()).is_equal(1)


func test_effects_and_sounds_switch_off_apart_from_marks() -> void:
	var surface := _surface(&"default")
	_impacts.effects_enabled = false
	_impacts.impact(_wall, Vector3(0.0, 1.0, -4.75), Vector3.BACK)
	var slot := _slots_of(surface)[0]
	assert_int(slot.emitters().size()).is_equal(0)
	assert_object(slot.sound_player()).is_not_null()
	assert_int(_impacts.mark_count()).is_equal(1)
	_emitter.stop_all()
	_impacts.effects_enabled = true
	_impacts.sounds_enabled = false
	_impacts.impact(_wall, Vector3(1.0, 1.0, -4.75), Vector3.BACK)
	assert_int(slot.emitters().size()).is_equal(1)
	assert_bool(slot.sound_player().playing).is_false()


func test_a_surface_without_an_effect_makes_only_its_mark() -> void:
	var surface := _surface(&"default")
	surface.effect = null
	assert_object(_impacts.impact(_wall, Vector3(0.0, 1.0, -4.75), Vector3.BACK)).is_same(surface)
	assert_int(_emitter.slot_count()).is_equal(0)
	assert_int(_impacts.mark_count()).is_equal(1)


func test_a_level_without_an_emitter_still_leaves_marks() -> void:
	_emitter.remove_from_group(EffectEmitter.GROUP)
	_impacts.impact(_wall, Vector3(0.0, 1.0, -4.75), Vector3.BACK)
	assert_int(_emitter.slot_count()).is_equal(0)
	assert_int(_impacts.mark_count()).is_equal(1)


func test_the_target_surface_gives_effect_and_sound_but_no_mark() -> void:
	var board := auto_free(load(TARGET).instantiate()) as Target
	board.position = Vector3(0.0, 0.0, -2.0)
	_arena.add_child(board)
	await get_tree().physics_frame
	await ImpactShots.shoot(get_tree(), _arena, Vector3(0.0, 1.0, 3.0), Vector3(0.0, 1.0, -2.0))
	assert_int(_impacts.mark_count()).is_equal(0)
	assert_int(_slots_of(_surface(&"target")).size()).is_equal(1)
	assert_bool(_slots_of(_surface(&"target"))[0].sound_player().playing).is_true()


func test_a_hit_with_no_surface_node_at_all_does_nothing() -> void:
	var bare := auto_free(Impacts.new()) as Impacts
	_arena.add_child(bare)
	assert_object(bare.impact(_wall, Vector3.ZERO, Vector3.UP)).is_null()
	assert_int(bare.mark_count()).is_equal(0)


func test_a_weapon_with_impacts_off_makes_shots_that_leave_nothing() -> void:
	var muzzle := Marker3D.new()
	muzzle.position = Vector3(0.0, 1.5, 0.0)
	_arena.add_child(muzzle)
	var weapon := auto_free(load(WEAPON).instantiate()) as Weapon
	_arena.add_child(weapon)
	weapon.muzzle = muzzle
	await get_tree().physics_frame
	var shot := weapon.fire()
	assert_bool(shot.impact_effects).is_true()
	await ImpactShots.land(get_tree(), shot)
	assert_int(_impacts.mark_count()).is_equal(1)
	_impacts.clear_marks()
	# Its own copy: the pistol's definition is shared by every weapon that holds it.
	weapon.definition = weapon.definition.duplicate()
	weapon.definition.impacts = false
	weapon.make_ready()
	shot = weapon.fire()
	assert_bool(shot.impact_effects).is_false()
	await ImpactShots.land(get_tree(), shot)
	assert_int(_impacts.mark_count()).is_equal(0)


func test_a_projectile_with_impact_effects_off_leaves_nothing_even_from_a_weapon_that_has_them(
) -> void:
	var shot := ImpactShots.fire(_arena, Vector3(0.0, 1.5, 0.0), Vector3(0.0, 1.5, -10.0))
	shot.impact_effects = false
	await ImpactShots.land(get_tree(), shot)
	assert_int(_impacts.mark_count()).is_equal(0)
	assert_int(_emitter.slot_count()).is_equal(0)
	shot = ImpactShots.fire(_arena, Vector3(0.0, 1.5, 0.0), Vector3(0.0, 1.5, -10.0))
	await ImpactShots.land(get_tree(), shot)
	assert_int(_impacts.mark_count()).is_equal(1)


func test_a_level_with_no_impacts_still_lets_a_shot_land() -> void:
	_impacts.remove_from_group(&"impacts")
	var shot := ImpactShots.fire(_arena, Vector3(0.0, 1.5, 0.0), Vector3(0.0, 1.5, -10.0))
	await ImpactShots.land(get_tree(), shot)
	assert_bool(is_instance_valid(shot) and not shot.is_queued_for_deletion()).is_false()
	assert_int(_impacts.mark_count()).is_equal(0)
