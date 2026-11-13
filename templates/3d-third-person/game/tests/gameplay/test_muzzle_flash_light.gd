# The muzzle flash's light lights its surroundings briefly and modestly at every fire rate (kit
# #1341: walls 1 m from the rifle turned solid orange). Its peak energy, reach, colour and on time
# per shot are held to a budget, the light a wall gets at 1 m and with the muzzle almost against it
# is computed with the renderer's own falloff, and a sustained burst never stacks two flash lights
# or keeps one on most of the time. What it does on the screen is measured by
# `tools/capture/muzzle_light_tour.tscn` (kit docs/engines/godot/shot-feedback.md#flash-light).
extends GdUnitTestSuite

const WEAPON := "res://gameplay/weapon/weapon.tscn"
const RIFLE := "res://gameplay/weapon/rifle.tres"
## The budget. Energy and the light a surface gets are in the light's own units (1 is a surface
## facing a light of energy 1 at 1 m with no falloff).
const MAX_ENERGY := 0.5
const MAX_REACH := 3.0
const MAX_ON_TIME := 0.05
const MAX_SATURATION := 0.15
const MAX_AT_ONE_METRE := 0.35
const MAX_AT_QUARTER_METRE := 0.7
## The longest share of a burst that a flash light may be on.
const MAX_ON_SHARE := 0.5
const STEP := 1.0 / 120.0

var _world: Node3D
var _emitter: EffectEmitter
var _weapon: Weapon
var _flash: EffectDef
var _rifle: WeaponDef


func before_test() -> void:
	_world = auto_free(Node3D.new())
	add_child(_world)
	_emitter = load("res://gameplay/effects/effect_emitter.tscn").instantiate() as EffectEmitter
	_emitter.compact = false
	_world.add_child(_emitter)
	var muzzle := Marker3D.new()
	_world.add_child(muzzle)
	muzzle.position = Vector3(0.0, 1.4, 0.0)
	_weapon = load(WEAPON).instantiate() as Weapon
	_world.add_child(_weapon)
	_weapon.muzzle = muzzle
	_rifle = load(RIFLE) as WeaponDef
	_flash = _rifle.muzzle_flash
	await get_tree().physics_frame


func after_test() -> void:
	AudioDrain.stop_all(_world)


# The light a surface facing it gets at `distance`, by the renderer's omni falloff (Godot's
# `get_omni_attenuation`, the same in Forward+ and Compatibility).
static func _light_at(energy: float, reach: float, attenuation: float, distance: float) -> float:
	var window := pow(maxf(1.0 - pow(distance / reach, 4.0), 0.0), 2.0)
	return energy * window * pow(maxf(distance, 0.0001), -attenuation)


func test_the_rifle_and_the_pistol_share_the_flash() -> void:
	assert_object(_flash).is_same(_weapon.definition.muzzle_flash)
	assert_bool(_flash.light_alone).is_true()


func test_the_flash_light_is_modest_short_and_close_to_white() -> void:
	assert_float(_flash.light_energy).is_greater(0.0)
	assert_float(_flash.light_energy).is_less_equal(MAX_ENERGY)
	assert_float(_flash.light_time).is_less_equal(MAX_ON_TIME)
	assert_float(_flash.light_color.s).is_less_equal(MAX_SATURATION)
	var reach := _flash.light_range * _flash.size * maxf(_rifle.muzzle_flash_size, 1.0)
	assert_float(reach).is_less_equal(MAX_REACH)


func test_a_wall_at_one_metre_and_against_the_muzzle_gets_little_light() -> void:
	var reach := _flash.light_range * _flash.size * maxf(_rifle.muzzle_flash_size, 1.0)
	var energy := _flash.light_energy
	var falloff := _flash.light_attenuation
	assert_float(_light_at(energy, reach, falloff, 1.0)).is_less_equal(MAX_AT_ONE_METRE)
	assert_float(_light_at(energy, reach, falloff, 0.25)).is_less_equal(MAX_AT_QUARTER_METRE)


func test_one_shot_lights_at_most_its_peak_for_its_time_and_then_is_dark() -> void:
	_weapon.make_ready()
	_weapon.fire()
	var slot := _emitter.slots()[0]
	assert_bool(slot.light_on()).is_true()
	assert_float(slot.light().light_energy).is_less_equal(MAX_ENERGY)
	assert_float(slot.light().omni_attenuation).is_equal_approx(_flash.light_attenuation, 1e-4)
	var lit := 0.0
	var peak := 0.0
	for _step in 60:
		if slot.light_on():
			lit += STEP
			peak = maxf(peak, slot.light().light_energy)
		_emitter.advance(STEP)
	assert_float(lit).is_less_equal(MAX_ON_TIME + STEP)
	assert_float(peak).is_less_equal(MAX_ENERGY)
	assert_int(_emitter.light_count()).is_equal(0)


func test_a_sustained_burst_never_stacks_lights_or_stays_lit() -> void:
	for rate: float in [_rifle.fire_rate, 30.0]:
		_emitter.stop_all()
		var interval := 1.0 / rate
		var clock := 0.0
		var next_shot := 0.0
		var lit_steps := 0
		var steps := 0
		var most := 0
		while clock < 2.0:
			if clock >= next_shot:
				_weapon.make_ready()
				_weapon.fire()
				next_shot += interval
			most = maxi(most, _emitter.light_count())
			if _emitter.light_count() > 0:
				lit_steps += 1
			steps += 1
			_emitter.advance(STEP)
			clock += STEP
		var share := float(lit_steps) / steps
		assert_int(most).is_equal(1)
		if rate <= _rifle.fire_rate:
			assert_float(share).is_less_equal(MAX_ON_SHARE)
		# Each shot still flashes: the newest takes the light over instead of going dark.
		assert_float(share).is_greater(0.0)


func test_a_newer_flash_takes_the_light_over() -> void:
	_weapon.make_ready()
	_weapon.fire()
	_emitter.advance(0.01)
	_weapon.make_ready()
	_weapon.fire()
	assert_int(_emitter.light_count()).is_equal(1)
	var lit: Array[EffectSlot] = []
	for slot in _emitter.slots():
		if slot.light_on():
			lit.append(slot)
	assert_float(lit[0].age).is_equal_approx(0.0, 1e-4)
