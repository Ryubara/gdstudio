# How many shots a press of the fire button gives (gdstudio #1335, #1352): a mouse button pressed
# through the engine's own input path (`InputSim`), read by the player's `PlayerInput` as a
# player's is, and the weapon's `fired` signal counted. For every weapon of the template in every
# fire mode (single, burst, automatic): a press of one frame fires exactly one press's worth (one
# shot, or one burst of `burst_size`), from the arm down or with the aim up; so does a tap shorter
# than the weapon's shot interval; a held press fires one press's worth on single and burst, and
# the weapon's rate for as long as it is held (within one shot) on automatic, with nothing after
# the release. From the arm down the arm keeps coming up after a tap until its shots have left
# (gdstudio #1352). The fists' press is a blow (gdstudio #1254), counted as a shot: one a press,
# aimed or not, held or not, whatever the fire mode. With a burst weapon's `full_burst_per_press`
# off, the burst lasts only while the button is held: a one-tick tap fires one shot (aimed or from
# the hip), a 2-tick hold what the burst's spacing allows, a long hold the whole burst.
extends GdUnitTestSuite

const MODES: Array[WeaponDef.FireMode] = [
	WeaponDef.FireMode.SINGLE,
	WeaponDef.FireMode.BURST,
	WeaponDef.FireMode.AUTOMATIC,
]
const WEAPONS: Array[String] = [
	"res://gameplay/weapon/pistol.tres",
	"res://gameplay/weapon/rifle.tres",
	"res://gameplay/weapon/fists.tres",
]
## Seconds the trigger is held in the held test.
const HOLD_SECONDS := 2.0
## Ticks the aim button is held before a press, so the arm is up and the weapon ready.
const AIM_TICKS := 40
## Ticks waited after a release: past the fire buffer and several shot intervals.
const SETTLE_TICKS := 60

var _arena: PlayArena
var _player: Player
var _shots := 0


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.3, 3.0)
	_arena.add_child(camera)
	camera.make_current()
	_player.weapon.fired.connect(func(_shot: Projectile) -> void: _shots += 1)
	_player.weapon.melee_started.connect(func(_blow: int) -> void: _shots += 1)
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


func test_a_one_frame_press_from_the_arm_down_fires_one_press() -> void:
	for mode in MODES:
		for path in WEAPONS:
			var definition := await _arm(path, mode)
			await _tap(1)
			_expect(_press_shots(definition), definition, "one frame, arm down")


func test_a_one_frame_press_fires_one_press_with_the_aim_up() -> void:
	for mode in MODES:
		for path in WEAPONS:
			var definition := await _arm(path, mode)
			await _aim_up()
			await _tap(1)
			_expect(_press_shots(definition), definition, "one frame, aim up")
			InputSim.mouse_button(MOUSE_BUTTON_RIGHT, false)


func test_a_tap_shorter_than_the_shot_interval_fires_one_press() -> void:
	for mode in MODES:
		for path in WEAPONS:
			for aim_up: bool in [false, true]:
				var definition := await _arm(path, mode)
				var tap := _interval_ticks(definition) - 1
				if aim_up:
					await _aim_up()
				await _tap(tap)
				_expect(
					_press_shots(definition),
					definition,
					"tap of %d ticks, aim up %s" % [tap, aim_up]
				)
				InputSim.mouse_button(MOUSE_BUTTON_RIGHT, false)


func test_a_held_press_fires_the_rate_while_held_and_nothing_after() -> void:
	for mode in MODES:
		for path in WEAPONS:
			var definition := await _arm(path, mode)
			await _aim_up()
			var ticks := roundi(HOLD_SECONDS * Engine.physics_ticks_per_second)
			InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
			await InputSim.ticks(get_tree(), ticks)
			var held := _shots
			InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
			await InputSim.ticks(get_tree(), SETTLE_TICKS)
			var label := _label(definition)
			if mode == WeaponDef.FireMode.AUTOMATIC and not _is_blow(path):
				var expected := HOLD_SECONDS * definition.fire_rate
				(
					assert_float(float(held))
					. override_failure_message(
						"%s: %d shots in %.1f s" % [label, held, HOLD_SECONDS]
					)
					. is_between(expected - 1.0, expected + 1.0)
				)
			else:
				_expect(_press_shots(definition), definition, "held")
			(
				assert_int(_shots)
				. override_failure_message(
					"%s: %d shots after the release" % [label, _shots - held]
				)
				. is_equal(held)
			)
			InputSim.mouse_button(MOUSE_BUTTON_RIGHT, false)


func test_with_the_full_burst_off_a_press_fires_the_shots_it_is_held_for() -> void:
	var hold := roundi(HOLD_SECONDS * Engine.physics_ticks_per_second)
	for path in WEAPONS:
		for press: int in [1, 2, hold]:
			for aim_up: bool in [false, true]:
				var definition := await _arm(path, WeaponDef.FireMode.BURST)
				definition.full_burst_per_press = false
				if aim_up:
					await _aim_up()
				await _tap(press)
				# From the hip the arm comes up after a short press is let go: one shot; a long
				# hold still fires the whole burst.
				var expected := _held_shots(definition, press)
				if not aim_up and press < hold:
					expected = 1
				_expect(expected, definition, "held %d ticks, aim up %s" % [press, aim_up])
				InputSim.mouse_button(MOUSE_BUTTON_RIGHT, false)


# What a burst press held `ticks` ticks with the aim up fires when the release ends the burst: a
# shot every burst spacing from the first tick, at most the burst (a blow for a melee weapon).
func _held_shots(definition: WeaponDef, ticks: int) -> int:
	if definition.kind == WeaponDef.Kind.MELEE:
		return 1
	var spacing := roundi(definition.burst_interval() * Engine.physics_ticks_per_second)
	return mini(ceili(float(ticks) / spacing), definition.shots_a_press())


# Gives the player a copy of the weapon at `path` in fire mode `mode`, with rounds enough for the
# test, and waits until it is ready; the shot count starts again.
func _arm(path: String, mode: WeaponDef.FireMode) -> WeaponDef:
	InputSim.release_all()
	await InputSim.ticks(get_tree(), SETTLE_TICKS)
	var definition := (load(path) as WeaponDef).duplicate() as WeaponDef
	definition.fire_mode = mode
	definition.auto_reload = false
	if definition.uses_ammo():
		definition.magazine_size = 200
	_player.weapon.definition = definition
	_player.weapon.make_ready()
	await InputSim.ticks(get_tree(), 4)
	_shots = 0
	return definition


# True for a weapon whose press is a melee blow (the fists).
func _is_blow(path: String) -> bool:
	return (load(path) as WeaponDef).kind == WeaponDef.Kind.MELEE


func _aim_up() -> void:
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	await InputSim.ticks(get_tree(), AIM_TICKS)
	_shots = 0


# Holds the fire button for `ticks` physics frames, lets go and waits for anything buffered.
func _tap(ticks: int) -> void:
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await InputSim.ticks(get_tree(), ticks)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
	await InputSim.ticks(get_tree(), SETTLE_TICKS)


func _interval_ticks(definition: WeaponDef) -> int:
	return floori(definition.shot_interval() * Engine.physics_ticks_per_second)


# What one press fires: a blow for a melee weapon, else one shot or one burst.
func _press_shots(definition: WeaponDef) -> int:
	return 1 if definition.kind == WeaponDef.Kind.MELEE else definition.shots_a_press()


func _label(definition: WeaponDef) -> String:
	return "%s %s" % [definition.display_name, WeaponDef.FireMode.keys()[definition.fire_mode]]


func _expect(count: int, definition: WeaponDef, what: String) -> void:
	(
		assert_int(_shots)
		. override_failure_message("%s, %s: %d shots" % [_label(definition), what, _shots])
		. is_equal(count)
	)
