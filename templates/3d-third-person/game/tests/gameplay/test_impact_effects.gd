# What a hit does on its surface: the effect bursts at the hit standing on the normal, the sound
# plays there, and the template nodes a developer edits show in the next hit. The impacts, the
# weapon and the projectile each switch it off.
extends GdUnitTestSuite

const WEAPON := "res://gameplay/weapon/weapon.tscn"
const TARGET := "res://gameplay/target/target.tscn"

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


func test_a_hit_bursts_the_effect_on_the_normal_and_plays_the_sound_at_the_point() -> void:
	var body := _body()
	body.set_meta(&"surface", &"wood")
	var point := Vector3(1.0, 2.0, 3.0)
	var normal := Vector3(0.0, 0.0, 1.0)
	var surface := _impacts.impact(body, point, normal)
	assert_object(surface).is_same(_surface(&"wood"))
	var copies := surface.effect_copies()
	assert_int(copies.size()).is_equal(1)
	var burst := copies[0] as CPUParticles3D
	assert_bool(burst.emitting).is_true()
	assert_vector(burst.global_position).is_equal_approx(point, Vector3.ONE * 0.0001)
	assert_vector(burst.global_basis.y).is_equal_approx(normal, Vector3.ONE * 0.001)
	var voices := surface.sound_copies()
	assert_int(voices.size()).is_equal(1)
	assert_bool(voices[0].playing).is_true()
	assert_vector(voices[0].global_position).is_equal_approx(point, Vector3.ONE * 0.0001)
	# The templates stay quiet.
	assert_bool(surface.effect.emitting).is_false()
	assert_bool(surface.sound.playing).is_false()


func test_each_surface_plays_its_own_sound_and_effect() -> void:
	var streams := {}
	for named: StringName in [&"default", &"wood", &"metal", &"target"]:
		var body := _body()
		body.set_meta(&"surface", named)
		var surface := _impacts.impact(body, Vector3(0.0, 1.0, 0.0), Vector3.UP)
		assert_str(surface.surface_name).is_equal(String(named))
		streams[named] = (
			surface.sound.stream.resource_path + str(surface.sound.stream.get_instance_id())
		)
	var distinct := {}
	for value in streams.values():
		distinct[value] = true
	# default, wood and metal each have their own sounds; the target shares the metal's.
	assert_int(distinct.size()).is_equal(3)


func test_a_burst_of_hits_reuses_a_pool_of_pool_size_copies() -> void:
	var surface := _surface(&"default")
	surface.pool_size = 2
	for step in 5:
		_impacts.impact(_wall, Vector3(float(step), 1.0, -4.75), Vector3.BACK)
	assert_int(surface.effect_copies().size()).is_equal(2)
	assert_int(surface.sound_copies().size()).is_equal(2)
	surface.pool_size = 1
	_impacts.impact(_wall, Vector3(9.0, 1.0, -4.75), Vector3.BACK)
	assert_int(surface.effect_copies().size()).is_equal(1)


func test_a_change_to_the_template_shows_in_the_next_hit() -> void:
	var surface := _surface(&"default")
	_impacts.impact(_wall, Vector3(0.0, 1.0, -4.75), Vector3.BACK)
	var burst := surface.effect_copies()[0] as CPUParticles3D
	var voice := surface.sound_copies()[0]
	var amount := (surface.effect as CPUParticles3D).amount
	assert_int(burst.amount).is_equal(amount)
	(surface.effect as CPUParticles3D).amount = amount + 5
	(surface.effect as CPUParticles3D).spread = 12.0
	surface.sound.volume_db = -3.0
	surface.sound.pitch_scale = 1.5
	for _hit in 4:
		_impacts.impact(_wall, Vector3(1.0, 1.0, -4.75), Vector3.BACK)
	assert_int(burst.amount).is_equal(amount + 5)
	assert_float(burst.spread).is_equal(12.0)
	assert_float(voice.volume_db).is_equal(-3.0)
	assert_float(voice.pitch_scale).is_equal(1.5)


func test_effects_and_sounds_switch_off_apart_from_marks() -> void:
	var surface := _surface(&"default")
	_impacts.effects_enabled = false
	_impacts.impact(_wall, Vector3(0.0, 1.0, -4.75), Vector3.BACK)
	assert_int(surface.effect_copies().size()).is_equal(0)
	assert_int(surface.sound_copies().size()).is_equal(1)
	assert_int(_impacts.mark_count()).is_equal(1)
	_impacts.effects_enabled = true
	_impacts.sounds_enabled = false
	_impacts.impact(_wall, Vector3(1.0, 1.0, -4.75), Vector3.BACK)
	assert_int(surface.effect_copies().size()).is_equal(1)
	assert_int(surface.sound_copies().size()).is_equal(1)


func test_a_surface_without_an_effect_or_a_sound_makes_only_what_it_has() -> void:
	var surface := _surface(&"default")
	surface.effect = null
	surface.sound = null
	assert_object(_impacts.impact(_wall, Vector3(0.0, 1.0, -4.75), Vector3.BACK)).is_same(surface)
	assert_int(surface.effect_copies().size()).is_equal(0)
	assert_int(surface.sound_copies().size()).is_equal(0)
	assert_int(_impacts.mark_count()).is_equal(1)


func test_the_target_surface_gives_effect_and_sound_but_no_mark() -> void:
	var board := auto_free(load(TARGET).instantiate()) as Target
	board.position = Vector3(0.0, 0.0, -2.0)
	_arena.add_child(board)
	await get_tree().physics_frame
	await ImpactShots.shoot(get_tree(), _arena, Vector3(0.0, 1.0, 3.0), Vector3(0.0, 1.0, -2.0))
	assert_int(_impacts.mark_count()).is_equal(0)
	assert_int(_surface(&"target").effect_copies().size()).is_equal(1)
	assert_int(_surface(&"target").sound_copies().size()).is_equal(1)


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
	weapon.impacts = false
	weapon._cooldown = 0.0
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
	assert_int(_surface(&"default").effect_copies().size()).is_equal(0)
	shot = ImpactShots.fire(_arena, Vector3(0.0, 1.5, 0.0), Vector3(0.0, 1.5, -10.0))
	await ImpactShots.land(get_tree(), shot)
	assert_int(_impacts.mark_count()).is_equal(1)


func test_a_level_with_no_impacts_still_lets_a_shot_land() -> void:
	_impacts.remove_from_group(&"impacts")
	var shot := ImpactShots.fire(_arena, Vector3(0.0, 1.5, 0.0), Vector3(0.0, 1.5, -10.0))
	await ImpactShots.land(get_tree(), shot)
	assert_bool(is_instance_valid(shot) and not shot.is_queued_for_deletion()).is_false()
	assert_int(_impacts.mark_count()).is_equal(0)
