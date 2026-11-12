# The head while aiming (kit #1334): with every weapon, in every stance, the head sits level on a
# straight neck and looks along the aim, and holds still while the aim does. The aim clips carried
# a head of their own: the pistol's leaned it 10 degrees to the right and tipped it 19 down
# whatever the aim, its up and down blends bent the neck and the head against each other, the
# rifle and the fists looked straight ahead aiming 30 degrees down, and the crouched rifle looked
# at the floor. Driven by commands, as a server or a bot drives a body, and read from the pose the
# skin gets each drawn frame (`HeadPoseProbe`), with the physics ticking slower than the frames so
# the drawn frames fall between ticks.
extends GdUnitTestSuite

## The physics rate of the suite: three drawn frames a tick (the suites run at 60 frames a second).
const TICKS_PER_SECOND := 20
## How far the head may roll off level in the world, in degrees.
const LEVEL := 3.0
## How far the head may face off the way to the aim's point, in degrees (within its reach).
const LOOK := 4.0
## How far the head may roll on the neck, or the neck on the chest, in degrees.
const ROLL_ON_NECK := 8.0
## Below this the head's and the neck's pitches count as straight whatever their signs, in degrees.
const STRAIGHT := 4.0
## How far the head may turn between two drawn frames while the aim holds still, in degrees.
const STEP := 0.5
## A weapon aimed down its sights (the rifle): how far the eye may be off the sight line, in
## metres (the cheek on the stock, as near as the skin lets it), and how far the face may be off
## the aim, in degrees.
const SIGHT_OFF := 0.081
const SIGHT_FACE := 20.0
## The aim pitches each case holds (negative looks down).
const PITCHES: Array[float] = [-30.0, 0.0, 20.0]

var _arena: PlayArena
var _player: Player
var _layer: AimLayer
var _probe: HeadPoseProbe


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3(0.0, 0.0, 20.0))
	CommandDriver.take(_player)
	await InputSim.ticks(get_tree(), 6)
	Engine.physics_ticks_per_second = TICKS_PER_SECOND
	_layer = _player.get_node("AimLayer")
	_probe = HeadPoseProbe.attach(_player.model.skeleton())
	_probe.layer = _layer


func after_test() -> void:
	Engine.physics_ticks_per_second = 60
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


func test_the_pistol_aimed_holds_the_head_level_on_the_neck() -> void:
	await _every_stance("pistol")


# A shouldered weapon is aimed with the eye behind its sights: a level head erases the cheek on
# the stock (kit #1082). The rifle's definition asks for it (`WeaponDef.AimHead.SIGHT`).
func test_the_rifle_aimed_brings_the_eye_to_its_sights() -> void:
	_player.loadout.give(load("res://gameplay/weapon/rifle.tres") as WeaponDef, 30)
	await _stand(30)
	assert_str(String(_player.weapon.definition.resource_path)).ends_with("rifle.tres")
	assert_int(_player.weapon.definition.aim_head).is_equal(WeaponDef.AimHead.SIGHT)
	var holds := _player.loadout.model.find_children("*", "TwoHandHold", true, false)
	assert_int(holds.size()).is_equal(1)
	assert_float((holds[0] as TwoHandHold).weight()).is_equal_approx(1.0, 0.01)
	# The hold made its modifiers after the probe: the probe reads the pose they leave.
	_probe.get_parent().move_child(_probe, -1)
	await _every_stance("rifle", true)
	# The head's modifier runs after the stance that placed the rifle in the same update.
	var stance := 0
	for child in _layer.head_modifier().get_parent().get_children():
		if child.get_script() == TwoHandHold.STANCE_SCRIPT:
			stance = child.get_index()
	assert_int(_layer.head_modifier().get_index()).is_greater(stance)


func test_the_fists_aimed_hold_the_head_level_on_the_neck() -> void:
	_player.loadout.toggle_unarmed()
	await _stand(30)
	await _every_stance("fists")


func test_firing_while_aimed_keeps_the_head_level() -> void:
	var command := _command(Vector3.ZERO, 0.0)
	await CommandDriver.run(get_tree(), [_player], command, 30)
	var fire := _command(Vector3.ZERO, 0.0)
	fire.fire_pressed = true
	for shot in 3:
		_probe.clear()
		await CommandDriver.run(get_tree(), [_player], fire, 6)
		_check_level("pistol firing, shot %d" % shot, 0)


func test_without_the_head_modifier_the_pistol_s_head_leans() -> void:
	# The fault the modifier mends: the pistol's aim clips lean and tip the head.
	_layer.head_disabled = true
	await CommandDriver.run(get_tree(), [_player], _command(Vector3.ZERO, 0.0), 30)
	_probe.clear()
	await CommandDriver.run(get_tree(), [_player], _command(Vector3.ZERO, 0.0), 10)
	assert_float(absf(_probe.model_turns[-1].y)).is_greater(LEVEL * 2.0)
	assert_float(_probe.misses[-1]).is_greater(LOOK * 2.0)


func test_the_head_comes_and_goes_with_the_aim() -> void:
	await CommandDriver.run(get_tree(), [_player], _command(Vector3.ZERO, -30.0), 30)
	assert_float(_layer.head_weight()).is_equal_approx(1.0, 0.01)
	assert_bool(_layer.head_modifier().active).is_true()
	var lowered := _command(Vector3.ZERO, -30.0)
	lowered.aim = false
	await CommandDriver.run(get_tree(), [_player], lowered, 30)
	assert_float(_layer.head_weight()).is_equal(0.0)
	assert_bool(_layer.head_modifier().active).is_false()


# Standing, moving, crouched and lying, each at every pitch of `PITCHES`.
func _every_stance(weapon: String, sights := false) -> void:
	for stance: String in ["standing", "moving", "crouched", "lying"]:
		await _stand(30)
		for pitch: float in PITCHES:
			var command := _command(Vector3.RIGHT if stance == "moving" else Vector3.ZERO, pitch)
			command.crouch = stance == "crouched"
			command.prone = stance == "lying"
			# The stance and the aim settle, then the drawn frames are read.
			await CommandDriver.run(get_tree(), [_player], command, 40)
			_probe.clear()
			await CommandDriver.run(get_tree(), [_player], command, 8)
			var label := "%s %s, pitch %+.0f" % [weapon, stance, pitch]
			assert_float(_layer.head_weight()).override_failure_message(label).is_greater(0.99)
			if sights:
				_check_sights(label)
			else:
				_check_level(label, 0)
			# Lying, the clip shifts the body as it crawls and settles; standing, crouched or walking
			# a still aim leaves the head still.
			if stance != "lying":
				_check_still(label)


# A command that aims `pitch` degrees up along the body's facing, moving along `move`.
func _command(move: Vector3, pitch: float) -> PlayerCommand:
	var look := CommandCodec.direction_from_angles(_player.facing + PI, deg_to_rad(pitch))
	var command := CommandDriver.walking(move, look)
	command.aim = true
	return command


# Stands up and lowers the weapon, back at the start.
func _stand(ticks: int) -> void:
	var idle := PlayerCommand.new()
	idle.yaw = 0.0
	_player.teleport(Vector3(0.0, 0.0, 20.0), PI)
	await CommandDriver.run(get_tree(), [_player], idle, ticks)


func _check_level(label: String, from: int) -> void:
	assert_int(_probe.turns.size()).override_failure_message(label + ": no frame").is_greater(from)
	for index in range(from, _probe.turns.size()):
		var world := _probe.model_turns[index]
		var on_neck := _probe.turns[index]
		var neck := _probe.neck_turns[index]
		var frame := "%s, frame %d: " % [label, index]
		(
			assert_float(absf(world.y))
			. override_failure_message(frame + "the head rolls %.1f degrees off level" % world.y)
			. is_less(LEVEL)
		)
		# The head faces the aim, or, where the chest the clip leaves is bent too far for that (the
		# crouch and the prone clips aiming up), it turns as far as it may toward it.
		var turned := absf(on_neck.x + neck.x)
		var at_most := turned >= _layer.head_max_turn - 1.0
		(
			assert_bool(_probe.misses[index] < LOOK or at_most)
			. override_failure_message(
				(
					frame
					+ (
						"the head faces %.1f degrees off the aim, turned only %.1f"
						% [_probe.misses[index], turned]
					)
				)
			)
			. is_true()
		)
		(
			assert_float(maxf(absf(on_neck.y), absf(neck.y)))
			. override_failure_message(
				frame + "rolled on the neck %.1f, the neck on the chest %.1f" % [on_neck.y, neck.y]
			)
			. is_less(ROLL_ON_NECK)
		)
		# The neck and the head bend the same way, never one against the other.
		var against := on_neck.x * neck.x < 0.0 and minf(absf(on_neck.x), absf(neck.x)) > STRAIGHT
		(
			assert_bool(against)
			. override_failure_message(
				frame + "the head bends %.1f on a neck bent %.1f" % [on_neck.x, neck.x]
			)
			. is_false()
		)
	print(
		(
			(
				"%s: head off level %.1f, off the aim %.1f, on the neck (pitch %.1f, roll %.1f), neck"
				% [
					label,
					_probe.model_turns[-1].y,
					_probe.misses[-1],
					_probe.turns[-1].x,
					_probe.turns[-1].y,
				]
			)
			+ " (pitch %.1f, roll %.1f)" % [_probe.neck_turns[-1].x, _probe.neck_turns[-1].y]
		)
	)


# The eye is by the sight line on every drawn frame, the face near the aim, and the neck and the
# head bend the same way.
func _check_sights(label: String) -> void:
	assert_int(_probe.eye_offs.size()).override_failure_message(label + ": no frame").is_greater(0)
	for index in _probe.eye_offs.size():
		var frame := "%s, frame %d: " % [label, index]
		(
			assert_float(_probe.eye_offs[index])
			. override_failure_message(
				frame + "the eye is %.1f mm off the sight line" % (_probe.eye_offs[index] * 1e3)
			)
			. is_less(SIGHT_OFF)
		)
		(
			assert_float(_probe.misses[index])
			. override_failure_message(
				frame + "the head faces %.1f degrees off the aim" % _probe.misses[index]
			)
			. is_less(SIGHT_FACE)
		)
		var on_neck := _probe.turns[index]
		var neck := _probe.neck_turns[index]
		var against := on_neck.x * neck.x < 0.0 and minf(absf(on_neck.x), absf(neck.x)) > STRAIGHT
		(
			assert_bool(against)
			. override_failure_message(
				frame + "the head bends %.1f on a neck bent %.1f" % [on_neck.x, neck.x]
			)
			. is_false()
		)
	print(
		(
			(
				"%s: eye %.1f mm off the sight line, face %.1f off the aim, head roll %.1f, on the neck"
				% [label, _probe.eye_offs[-1] * 1e3, _probe.misses[-1], _probe.model_turns[-1].y]
			)
			+ (
				" (pitch %.1f, roll %.1f), neck (pitch %.1f, roll %.1f)"
				% [
					_probe.turns[-1].x,
					_probe.turns[-1].y,
					_probe.neck_turns[-1].x,
					_probe.neck_turns[-1].y
				]
			)
		)
	)


func _check_still(label: String) -> void:
	var step := _probe.largest_step()
	var world_step := 0.0
	for index in range(1, _probe.model_turns.size()):
		world_step = maxf(
			world_step, (_probe.model_turns[index] - _probe.model_turns[index - 1]).length()
		)
	print("%s: largest step on the neck %.2f, in the world %.2f" % [label, step, world_step])
	(
		assert_float(maxf(step, world_step))
		. override_failure_message(
			"%s: the head moves %.2f degrees between frames" % [label, maxf(step, world_step)]
		)
		. is_less(STEP)
	)
