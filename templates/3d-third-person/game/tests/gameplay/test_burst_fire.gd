# The burst fire mode (gdstudio #1352). A `Weapon` on its own, ticked by hand: a pull starts a
# burst of `burst_size` shots `burst_interval()` apart, the next burst waits one `shot_interval()`
# after its last shot, a magazine that runs out ends it with no click, a reload, a switch or a blow
# ends it, and the step state carries a burst under way. On the player, with simulated mouse
# presses: a press during a burst fires the next burst once it may, and a tap from the hip brings
# the arm up for the whole burst and lets it down after. With `full_burst_per_press` off the burst
# lasts only while the button is held: a one-tick tap fires one shot, a short hold what the spacing
# allows, a long hold the whole burst, and the next press still waits one shot interval.
extends GdUnitTestSuite

const WEAPON := "res://gameplay/weapon/weapon.tscn"
const RIFLE := "res://gameplay/weapon/rifle.tres"
const TICK := 1.0 / 60.0
const SETTLE_TICKS := 60

var _world: Node3D
var _weapon: Weapon
var _muzzle: Marker3D


func before_test() -> void:
	InputSim.release_all()
	_world = auto_free(Node3D.new())
	add_child(_world)
	_weapon = load(WEAPON).instantiate() as Weapon
	_weapon.self_ticking = false
	_world.add_child(_weapon)
	_muzzle = Marker3D.new()
	_muzzle.position = Vector3(0.0, 1.0, 0.0)
	_world.add_child(_muzzle)
	_weapon.muzzle = _muzzle
	_weapon.definition = _burst_rifle()
	_weapon.make_ready()
	await get_tree().physics_frame


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_world)


# A copy of the rifle on burst: 3 shots at 15 a second, 10 a second between bursts.
func _burst_rifle() -> WeaponDef:
	var definition := (load(RIFLE) as WeaponDef).duplicate() as WeaponDef
	definition.fire_mode = WeaponDef.FireMode.BURST
	definition.burst_size = 3
	definition.burst_rate = 15.0
	definition.fire_rate = 10.0
	definition.auto_reload = false
	return definition


# Pulls on every tick for `count` ticks, as a character does while a burst is under way, from tick
# `start` (each tick after the first, or every tick from a `start` past 0, steps the weapon first);
# returns the ticks a shot left on.
func _pull_ticks(count: int, start := 0) -> Array[int]:
	var fired: Array[int] = []
	for tick in count:
		if tick > 0 or start > 0:
			_weapon.tick(TICK)
		if _weapon.bursting or tick == 0:
			if _weapon.pull() == Weapon.Pull.FIRED:
				fired.append(start + tick)
	return fired


func test_a_pull_fires_one_burst_spaced_by_its_rate_then_waits_one_shot_interval() -> void:
	var fired := _pull_ticks(30)
	# 15 a second at 60 ticks: 4 ticks apart.
	assert_array(fired).is_equal([0, 4, 8])
	assert_bool(_weapon.bursting).is_false()
	# The next burst may start one shot interval (6 ticks) after the last shot, not before.
	_weapon.make_ready()
	var shots := _pull_ticks(9)
	assert_array(shots).is_equal([0, 4, 8])
	var refused := 0
	for tick in 5:
		_weapon.tick(TICK)
		if _weapon.pull() == Weapon.Pull.BUSY:
			refused += 1
	assert_int(refused).is_equal(5)
	_weapon.tick(TICK)
	assert_int(_weapon.pull()).is_equal(Weapon.Pull.FIRED)
	assert_bool(_weapon.bursting).is_true()


# Presses the button for `held` ticks and lets go, ending the burst on a tick the button is up
# before the pull, as a character does (`Character._release_burst`); returns the shot ticks.
func _press_ticks(held: int, count: int) -> Array[int]:
	var fired: Array[int] = []
	for tick in count:
		if tick > 0:
			_weapon.tick(TICK)
		if tick >= held and not _weapon.definition.full_burst_per_press:
			_weapon.bursting = false
		if _weapon.bursting or tick == 0:
			if _weapon.pull() == Weapon.Pull.FIRED:
				fired.append(tick)
	return fired


func test_with_the_full_burst_off_letting_go_ends_the_burst() -> void:
	_weapon.definition.full_burst_per_press = false
	# 4 ticks between the shots of a burst: a hold of 1 or 2 ticks fires one shot, 5 ticks two, a
	# long hold the whole burst.
	var cases := {1: [0], 2: [0], 5: [0, 4], 30: [0, 4, 8]}
	for held: int in cases:
		_weapon.make_ready()
		var fired := _press_ticks(held, 30)
		assert_array(fired).override_failure_message("held %d: %s" % [held, fired]).is_equal(
			cases[held]
		)
		assert_bool(_weapon.bursting).is_false()
	# A burst cut short still waits one shot interval (6 ticks) from its last shot.
	_weapon.make_ready()
	# Down on tick 0, up on tick 1 (the burst ends), then pressed again on ticks 2 to 5: refused.
	assert_array(_press_ticks(1, 2)).is_equal([0])
	var refused := 0
	for tick in 4:
		_weapon.tick(TICK)
		if _weapon.pull() == Weapon.Pull.BUSY:
			refused += 1
	assert_int(refused).is_equal(4)
	_weapon.tick(TICK)
	assert_int(_weapon.pull()).is_equal(Weapon.Pull.FIRED)


func test_with_the_full_burst_on_letting_go_changes_nothing() -> void:
	assert_bool(_weapon.definition.full_burst_per_press).is_true()
	for held: int in [1, 2, 5, 30]:
		_weapon.make_ready()
		assert_array(_press_ticks(held, 30)).is_equal([0, 4, 8])


func test_a_burst_ends_with_the_magazine_and_never_clicks() -> void:
	var clicks := [0]
	_weapon.dry_fired.connect(func() -> void: clicks[0] += 1)
	_weapon.set_ammo(2, 0)
	var fired := _pull_ticks(30)
	assert_array(fired).is_equal([0, 4])
	assert_bool(_weapon.bursting).is_false()
	assert_int(clicks[0]).is_equal(0)


func test_a_reload_a_switch_and_a_blow_end_the_burst() -> void:
	for cut: String in ["reload", "lowered", "blow"]:
		_weapon.lowered = false
		_weapon.make_ready()
		_weapon.set_ammo(10, 60)
		assert_int(_weapon.pull()).is_equal(Weapon.Pull.FIRED)
		assert_bool(_weapon.bursting).override_failure_message(cut).is_true()
		match cut:
			"reload":
				assert_bool(_weapon.reload()).is_true()
			"lowered":
				_weapon.lowered = true
			"blow":
				_weapon.melee()
		_weapon.tick(TICK)
		assert_bool(_weapon.bursting).override_failure_message(cut).is_false()
	_weapon.lowered = false


func test_the_step_state_carries_a_burst_under_way() -> void:
	assert_int(_weapon.pull()).is_equal(Weapon.Pull.FIRED)
	var kept: Array = []
	_weapon.save_step_state(kept)
	var first := _pull_ticks(20, 1)
	_weapon.load_step_state(kept)
	assert_bool(_weapon.bursting).is_true()
	var again := _pull_ticks(20, 1)
	assert_array(first).is_equal([4, 8])
	assert_array(again).is_equal(first)
	# A state saved before the burst had none under way.
	_weapon.make_ready()
	var idle: Array = []
	_weapon.save_step_state(idle)
	_weapon.pull()
	_weapon.load_step_state(idle)
	assert_bool(_weapon.bursting).is_false()


func test_the_burst_numbers_show_only_for_a_burst_weapon() -> void:
	var definition := _burst_rifle()
	assert_int(definition.shots_a_press()).is_equal(3)
	assert_float(definition.burst_interval()).is_equal_approx(1.0 / 15.0, 1e-6)
	assert_int(_usage(definition, &"burst_size") & PROPERTY_USAGE_READ_ONLY).is_equal(0)
	assert_int(_usage(definition, &"full_burst_per_press") & PROPERTY_USAGE_READ_ONLY).is_equal(0)
	definition.fire_mode = WeaponDef.FireMode.AUTOMATIC
	assert_bool(definition.automatic).is_true()
	assert_int(definition.shots_a_press()).is_equal(1)
	assert_int(_usage(definition, &"burst_size") & PROPERTY_USAGE_READ_ONLY).is_not_equal(0)
	assert_int(_usage(definition, &"burst_rate") & PROPERTY_USAGE_READ_ONLY).is_not_equal(0)
	var full := _usage(definition, &"full_burst_per_press")
	assert_int(full & PROPERTY_USAGE_READ_ONLY).is_not_equal(0)
	definition.automatic = false
	assert_int(definition.fire_mode).is_equal(WeaponDef.FireMode.SINGLE)


func test_a_press_during_a_burst_fires_the_next_burst_after_it() -> void:
	var arena := auto_free(PlayArena.new()) as PlayArena
	add_child(arena)
	var player := arena.add_player(Vector3.ZERO)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.3, 3.0)
	arena.add_child(camera)
	camera.make_current()
	await InputSim.ticks(get_tree(), 4)
	var definition := _burst_rifle()
	definition.magazine_size = 200
	player.weapon.definition = definition
	player.weapon.make_ready()
	var ticks: Array[int] = []
	player.weapon.fired.connect(
		func(_shot: Projectile) -> void: ticks.append(Engine.get_physics_frames())
	)
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	await InputSim.ticks(get_tree(), 40)
	# A tap, and a second tap while the first burst is still firing.
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await InputSim.ticks(get_tree(), 1)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
	await InputSim.ticks(get_tree(), 3)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await InputSim.ticks(get_tree(), 1)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
	await InputSim.ticks(get_tree(), SETTLE_TICKS)
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, false)
	assert_int(ticks.size()).override_failure_message(str(ticks)).is_equal(6)
	if ticks.size() == 6:
		var gaps: Array[int] = []
		for index in range(1, ticks.size()):
			gaps.append(ticks[index] - ticks[index - 1])
		# Inside each burst 4 ticks; between them one shot interval (6 ticks).
		assert_array(gaps).is_equal([4, 4, 6, 4, 4])
	AudioDrain.stop_all(arena)


func test_a_tap_from_the_hip_keeps_the_arm_up_for_the_burst_and_lets_it_down_after() -> void:
	var arena := auto_free(PlayArena.new()) as PlayArena
	add_child(arena)
	var player := arena.add_player(Vector3.ZERO)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.3, 3.0)
	arena.add_child(camera)
	camera.make_current()
	await InputSim.ticks(get_tree(), 4)
	var definition := _burst_rifle()
	definition.magazine_size = 200
	player.weapon.definition = definition
	player.weapon.make_ready()
	var shots := [0]
	player.weapon.fired.connect(func(_shot: Projectile) -> void: shots[0] += 1)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await InputSim.ticks(get_tree(), 1)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
	# The arm keeps coming up with the button already up, and stays up until the last shot.
	var aimed_after_release := 0
	var last_shot_tick := -1
	for tick in SETTLE_TICKS:
		await get_tree().physics_frame
		if player.aiming:
			aimed_after_release += 1
		if shots[0] == 3 and last_shot_tick < 0:
			last_shot_tick = tick
	assert_int(shots[0]).is_equal(3)
	assert_int(last_shot_tick).is_greater(0)
	# Aiming ends on the tick after the last shot: nothing of the aim outlasts the burst.
	assert_int(aimed_after_release).is_between(last_shot_tick, last_shot_tick + 2)
	assert_bool(player.aiming).is_false()
	assert_bool(player.weapon.bursting).is_false()
	AudioDrain.stop_all(arena)


func test_with_the_full_burst_off_a_tap_from_the_hip_fires_one_shot() -> void:
	var arena := auto_free(PlayArena.new()) as PlayArena
	add_child(arena)
	var player := arena.add_player(Vector3.ZERO)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.3, 3.0)
	arena.add_child(camera)
	camera.make_current()
	await InputSim.ticks(get_tree(), 4)
	var definition := _burst_rifle()
	definition.magazine_size = 200
	definition.full_burst_per_press = false
	player.weapon.definition = definition
	player.weapon.make_ready()
	var shots := [0]
	player.weapon.fired.connect(func(_shot: Projectile) -> void: shots[0] += 1)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await InputSim.ticks(get_tree(), 1)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
	await InputSim.ticks(get_tree(), SETTLE_TICKS)
	# The press still fires (the arm comes up for it), with the button long up: one shot.
	assert_int(shots[0]).is_equal(1)
	assert_bool(player.aiming).is_false()
	assert_bool(player.weapon.bursting).is_false()
	AudioDrain.stop_all(arena)


# The inspector usage flags of `definition`'s property `field` (after `_validate_property`).
func _usage(definition: WeaponDef, field: StringName) -> int:
	for property in definition.get_property_list():
		if property["name"] == field:
			return property["usage"]
	return 0
