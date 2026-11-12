# How many shots a press of the fire button gives (gdstudio #1335): a mouse button pressed through
# the engine's own input path (`InputSim`), read by the player's `PlayerInput` as a player's is,
# and the weapon's `fired` signal counted. For every weapon of the template, one shot a press and
# automatic: a press of one frame and a tap shorter than the weapon's shot interval each fire
# exactly one shot, from the arm down or with the aim already up, and a held press fires the
# weapon's rate for as long as it is held (within one shot), with nothing after the release.
extends GdUnitTestSuite

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
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


func test_a_one_frame_press_fires_one_shot_from_the_arm_down() -> void:
	for automatic: bool in [false, true]:
		for path in WEAPONS:
			await _arm(path, automatic)
			await _tap(1)
			_expect(1, path, automatic, "one frame, arm down")


func test_a_one_frame_press_fires_one_shot_with_the_aim_up() -> void:
	for automatic: bool in [false, true]:
		for path in WEAPONS:
			await _arm(path, automatic)
			await _aim_up()
			await _tap(1)
			_expect(1, path, automatic, "one frame, aim up")
			InputSim.mouse_button(MOUSE_BUTTON_RIGHT, false)


func test_a_tap_shorter_than_the_shot_interval_fires_one_shot() -> void:
	for automatic: bool in [false, true]:
		for path in WEAPONS:
			for aim_up: bool in [false, true]:
				var definition := await _arm(path, automatic)
				var tap := _interval_ticks(definition) - 1
				if aim_up:
					await _aim_up()
				await _tap(tap)
				_expect(1, path, automatic, "tap of %d ticks, aim up %s" % [tap, aim_up])
				InputSim.mouse_button(MOUSE_BUTTON_RIGHT, false)


func test_a_held_press_fires_the_rate_while_held_and_nothing_after() -> void:
	for automatic: bool in [false, true]:
		for path in WEAPONS:
			var definition := await _arm(path, automatic)
			await _aim_up()
			var ticks := roundi(HOLD_SECONDS * Engine.physics_ticks_per_second)
			InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
			await InputSim.ticks(get_tree(), ticks)
			var held := _shots
			InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
			await InputSim.ticks(get_tree(), SETTLE_TICKS)
			var label := "%s automatic %s" % [path.get_file(), automatic]
			if automatic:
				var expected := HOLD_SECONDS * definition.fire_rate
				(
					assert_float(float(held))
					. override_failure_message(
						"%s: %d shots in %.1f s" % [label, held, HOLD_SECONDS]
					)
					. is_between(expected - 1.0, expected + 1.0)
				)
			else:
				_expect(1, path, automatic, "held")
			(
				assert_int(_shots)
				. override_failure_message(
					"%s: %d shots after the release" % [label, _shots - held]
				)
				. is_equal(held)
			)
			InputSim.mouse_button(MOUSE_BUTTON_RIGHT, false)


# Gives the player a copy of the weapon at `path`, automatic or not, with rounds enough for the
# test, and waits until it is ready; the shot count starts again.
func _arm(path: String, automatic: bool) -> WeaponDef:
	InputSim.release_all()
	await InputSim.ticks(get_tree(), SETTLE_TICKS)
	var definition := (load(path) as WeaponDef).duplicate() as WeaponDef
	definition.automatic = automatic
	definition.auto_reload = false
	if definition.uses_ammo():
		definition.magazine_size = 200
	_player.weapon.definition = definition
	_player.weapon.make_ready()
	await InputSim.ticks(get_tree(), 4)
	_shots = 0
	return definition


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


func _expect(count: int, path: String, automatic: bool, what: String) -> void:
	(
		assert_int(_shots)
		. override_failure_message(
			"%s automatic %s, %s: %d shots" % [path.get_file(), automatic, what, _shots]
		)
		. is_equal(count)
	)
