# The muzzle flash: each shot flashes at the weapon's muzzle, pointing out of the barrel, following
# it while it lasts, and ending by itself. A weapon turns it off, resizes it or gives it another
# effect, and a level without an emitter still shoots.
extends GdUnitTestSuite

const WEAPON := "res://gameplay/weapon/weapon.tscn"

var _world: Node3D
var _emitter: EffectEmitter
var _weapon: Weapon
var _muzzle: Marker3D


func before_test() -> void:
	_world = auto_free(Node3D.new())
	add_child(_world)
	_emitter = load("res://gameplay/effects/effect_emitter.tscn").instantiate() as EffectEmitter
	_emitter.compact = false
	_world.add_child(_emitter)
	_muzzle = Marker3D.new()
	_world.add_child(_muzzle)
	_muzzle.look_at_from_position(Vector3(0.0, 1.5, 0.0), Vector3(4.0, 1.5, -3.0))
	_weapon = load(WEAPON).instantiate() as Weapon
	_world.add_child(_weapon)
	_weapon.muzzle = _muzzle
	await get_tree().physics_frame


func after_test() -> void:
	AudioDrain.stop_all(_world)


func _shoot() -> Projectile:
	_weapon._cooldown = 0.0
	return _weapon.fire()


func test_a_shot_flashes_at_the_muzzle_pointing_out_of_the_barrel() -> void:
	assert_object(_shoot()).is_not_null()
	assert_int(_emitter.active_count()).is_equal(1)
	var slot := _emitter.slots()[0]
	assert_object(slot.effect).is_same(_weapon.muzzle_flash)
	assert_vector(slot.global_position).is_equal_approx(_muzzle.global_position, Vector3.ONE * 1e-4)
	assert_vector(slot.global_basis.y).is_equal_approx(-_muzzle.global_basis.z, Vector3.ONE * 1e-3)
	assert_bool((slot.emitters()[0] as CPUParticles3D).emitting).is_true()
	assert_bool(slot.light_on()).is_true()


func test_the_flash_follows_the_muzzle_and_is_gone_a_moment_later() -> void:
	_shoot()
	var slot := _emitter.slots()[0]
	_muzzle.global_position = Vector3(2.0, 1.5, 0.0)
	_emitter.advance(0.01)
	assert_vector(slot.global_position).is_equal_approx(Vector3(2.0, 1.5, 0.0), Vector3.ONE * 1e-4)
	assert_float(slot.light().light_energy).is_less(_weapon.muzzle_flash.light_energy)
	_emitter.advance(0.5)
	assert_bool(slot.active).is_false()
	assert_int(_emitter.light_count()).is_equal(0)


func test_a_burst_of_shots_reuses_the_flashs_slots() -> void:
	for _shot in 12:
		_shoot()
		_emitter.advance(0.2)
	assert_int(_emitter.slot_count()).is_equal(1)
	for _shot in 12:
		_shoot()
	assert_int(_emitter.slot_count()).is_less_equal(_weapon.muzzle_flash.max_instances)


func test_the_flash_switches_off_for_a_weapon_and_back_on() -> void:
	_weapon.muzzle_flash_enabled = false
	assert_object(_shoot()).is_not_null()
	assert_int(_emitter.slot_count()).is_equal(0)
	_weapon.muzzle_flash_enabled = true
	_shoot()
	assert_int(_emitter.active_count()).is_equal(1)


func test_a_weapon_can_have_its_own_flash_effect_and_size() -> void:
	var own := EffectProbe.def(true, false, 3.0)
	own.light_range = 2.0
	_weapon.muzzle_flash = own
	_weapon.muzzle_flash_size = 2.0
	_shoot()
	var slot := _emitter.slots()[0]
	assert_object(slot.effect).is_same(own)
	assert_float(slot.light().omni_range).is_equal_approx(4.0, 0.001)
	assert_vector((slot.emitters()[0] as CPUParticles3D).scale).is_equal_approx(
		Vector3.ONE * 2.0, Vector3.ONE * 1e-4
	)
	_weapon.muzzle_flash = null
	_emitter.stop_all()
	_shoot()
	assert_int(_emitter.active_count()).is_equal(0)


func test_a_weapon_in_a_level_with_no_emitter_still_shoots() -> void:
	_emitter.remove_from_group(EffectEmitter.GROUP)
	assert_object(_shoot()).is_not_null()
	assert_int(_emitter.slot_count()).is_equal(0)


func test_the_template_flash_is_a_burst_and_a_light_that_ends_quickly() -> void:
	var flash := _weapon.muzzle_flash
	assert_object(flash).is_not_null()
	assert_str(flash.resource_path).is_equal("res://gameplay/weapon/muzzle_flash.tres")
	assert_object(flash.particles).is_not_null()
	assert_float(flash.light_energy).is_greater(0.0)
	assert_float(flash.light_time).is_less(0.15)
	_shoot()
	var slot := _emitter.slots()[0]
	for node in slot.emitters():
		assert_bool((node as CPUParticles3D).one_shot).is_true()
	_emitter.advance(0.3)
	assert_bool(slot.active).is_false()


func test_the_flash_stays_the_same_size_on_a_scaled_muzzle() -> void:
	_muzzle.scale = Vector3.ONE * 3.0
	_shoot()
	var slot := _emitter.slots()[0]
	assert_vector(slot.global_basis.get_scale()).is_equal_approx(Vector3.ONE, Vector3.ONE * 1e-4)
