# The aim layer (kit #1253): sliding, the body keeps along the slide and the upper body turns so
# the pistol's muzzle points at the aim, to either side and up and down; past the slide's reach the
# body turns, or the shot is refused when the weapon says so; standing and crouched the muzzle is
# on the aim too. Driven by commands, as a server or a bot drives a body, and read from the muzzle
# the animation, the layer and the hold leave in the drawn pose.
extends GdUnitTestSuite

## How far the muzzle may point off the aim's point, in degrees.
const TOLERANCE := 3.0
## The slide runs along -Z.
const ALONG := Vector3.FORWARD

var _arena: PlayArena
var _player: Player
var _layer: AimLayer


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3(0.0, 0.0, 26.0))
	CommandDriver.take(_player)
	# Copies: the files are cached resources that other suites read.
	_player.slide_tuning = _player.slide_tuning.duplicate()
	_player.slide_tuning.aim_limits = _player.slide_tuning.aim_limits.duplicate()
	# A long slide on the flat, so every case aims well inside it.
	_player.slide_tuning.max_time = 4.0
	_player.slide_tuning.friction = 0.4
	_player.slide_tuning.drag = 0.0
	_player.weapon.definition = _player.weapon.definition.duplicate()
	_layer = _player.get_node("AimLayer")
	await InputSim.ticks(get_tree(), 6)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


# A command that moves along -Z, sprinting, looking `yaw` degrees to the character's left of the
# slide and `pitch` degrees up.
func _command(yaw: float, pitch: float) -> PlayerCommand:
	var look := CommandCodec.direction_from_angles(deg_to_rad(yaw), deg_to_rad(pitch))
	var command := CommandDriver.walking(ALONG, look)
	command.sprint = true
	return command


# Sprints, drops into a slide, then aims `yaw` and `pitch` off the slide for `ticks` ticks.
func _slide_and_aim(yaw: float, pitch: float, ticks: int = 24) -> PlayerCommand:
	await CommandDriver.run(get_tree(), [_player], _command(0.0, 0.0), 40)
	var slide := _command(0.0, 0.0)
	slide.crouch = true
	await CommandDriver.run(get_tree(), [_player], slide, 4)
	assert_bool(_player.sliding).is_true()
	var aimed := _command(yaw, pitch)
	aimed.crouch = true
	aimed.aim = true
	await CommandDriver.run(get_tree(), [_player], aimed, ticks)
	await _settle()
	return aimed


# The pose is drawn per render frame, a frame after the tick.
func _settle() -> void:
	for _frame in 2:
		await get_tree().process_frame


# Degrees between the way the muzzle points and the way from it to the layer's aim point.
func _muzzle_miss() -> float:
	var muzzle := _player.weapon.muzzle
	var toward := _layer.aim_point(1.0) - muzzle.global_position
	return rad_to_deg((-muzzle.global_basis.z).angle_to(toward))


# Degrees the body faces off the slide's line (positive to the character's left).
func _facing_off() -> float:
	return rad_to_deg(wrapf(_player.facing - PI, -PI, PI))


func test_sliding_the_muzzle_points_at_the_aim_ahead_left_right_up_and_down() -> void:
	for aim: Vector2 in [
		Vector2(0, 0), Vector2(50, 0), Vector2(-50, 0), Vector2(0, 20), Vector2(0, -25)
	]:
		await _reset()
		await _slide_and_aim(aim.x, aim.y)
		var sliding := "still sliding at %s" % aim
		assert_bool(_player.sliding).override_failure_message(sliding).is_true()
		assert_float(_layer.weight()).is_greater(0.95)
		(
			assert_float(_muzzle_miss())
			. override_failure_message(
				"aim %s: the muzzle is %.1f degrees off" % [aim, _muzzle_miss()]
			)
			. is_less(TOLERANCE)
		)
		# The body slides on along its line; the upper body does the turning.
		(
			assert_float(absf(_facing_off()))
			. override_failure_message(
				"aim %s: the body faces %.1f degrees off the slide" % [aim, _facing_off()]
			)
			. is_less(3.0)
		)


# Puts the player back at the start, standing still, for the next aim of a sweep.
func _reset() -> void:
	var idle := PlayerCommand.new()
	idle.yaw = 0.0
	_player.teleport(Vector3(0.0, 0.0, 26.0), PI)
	await CommandDriver.run(get_tree(), [_player], idle, 30)


func test_without_the_layer_the_slide_points_the_pistol_off_the_aim() -> void:
	# The fault the layer mends: the aim clips are posed for an upright body, and the slide leans
	# the hips back.
	_layer.disabled = true
	await _slide_and_aim(0.0, 0.0)
	assert_float(_muzzle_miss()).is_greater(10.0)


func test_past_the_reach_the_body_turns_by_default() -> void:
	var reach := _player.slide_tuning.aim_limits.yaw_left
	await _slide_and_aim(reach + 40.0, 0.0, 40)
	assert_float(_facing_off()).is_equal_approx(40.0, 3.0)
	assert_float(_muzzle_miss()).is_less(TOLERANCE)


func test_past_the_reach_a_weapon_that_refuses_keeps_the_body_and_fires_nothing() -> void:
	_player.weapon.definition.past_aim_limit = WeaponDef.PastAimLimit.REFUSE_SHOT
	var reach := _player.slide_tuning.aim_limits.yaw_right
	var aimed := await _slide_and_aim(-(reach + 30.0), 0.0)
	assert_float(absf(_facing_off())).is_less(3.0)
	var shots := [0]
	_player.weapon.fired.connect(func(_projectile: Projectile) -> void: shots[0] += 1)
	aimed.fire_pressed = true
	await CommandDriver.run(get_tree(), [_player], aimed, 6)
	assert_int(shots[0]).is_equal(0)
	# Within reach the same trigger shoots.
	var within := _command(-(reach - 20.0), 0.0)
	within.crouch = true
	within.aim = true
	within.fire_pressed = true
	await CommandDriver.run(get_tree(), [_player], within, 6)
	assert_int(shots[0]).is_equal(1)


func test_standing_and_crouched_the_muzzle_points_at_the_aim() -> void:
	for crouched: bool in [false, true]:
		for pitch: float in [-30.0, 0.0, 30.0]:
			var look := CommandCodec.direction_from_angles(0.0, deg_to_rad(pitch))
			var command := CommandDriver.walking(Vector3.ZERO, look)
			command.aim = true
			command.crouch = crouched
			await CommandDriver.run(get_tree(), [_player], command, 30)
			await _settle()
			(
				assert_float(_muzzle_miss())
				. override_failure_message(
					(
						"crouched %s, pitch %s: the muzzle is %.1f degrees off"
						% [crouched, pitch, _muzzle_miss()]
					)
				)
				. is_less(TOLERANCE)
			)


func test_the_limits_are_the_move_s_own() -> void:
	assert_object(_player.aim_limits).is_same(_player.tuning.aim_limits)
	await _slide_and_aim(0.0, 0.0, 4)
	assert_object(_player.aim_limits).is_same(_player.slide_tuning.aim_limits)


func test_a_limit_holds_the_turn() -> void:
	# With no room to turn left, an aim to the left is not reached.
	_player.slide_tuning.aim_limits.yaw_left = 0.0
	_player.weapon.definition.past_aim_limit = WeaponDef.PastAimLimit.REFUSE_SHOT
	await _slide_and_aim(40.0, 0.0)
	assert_float(_muzzle_miss()).is_greater(20.0)
	# The muzzle points along the body instead, the most the limit lets it turn.
	var muzzle := _player.weapon.muzzle
	var heading := -muzzle.global_basis.z
	var off := rad_to_deg(Vector2(heading.x, heading.z).angle_to(Vector2(ALONG.x, ALONG.z)))
	assert_float(absf(off)).is_less(TOLERANCE)


func test_every_aim_limit_is_pinned() -> void:
	var tuning := load("res://gameplay/player/player_tuning.tres") as CharacterTuning
	var slide := load("res://gameplay/player/slide_tuning.tres") as SlideTuning
	var prone := load("res://gameplay/player/prone_tuning.tres") as ProneTuning
	var standing := {
		&"enabled": true,
		&"yaw_left": 70.0,
		&"yaw_right": 70.0,
		&"pitch_up": 45.0,
		&"pitch_down": 45.0,
	}
	var sliding := standing.duplicate()
	sliding.merge(
		{&"yaw_left": 75.0, &"yaw_right": 75.0, &"pitch_up": 50.0, &"pitch_down": 70.0}, true
	)
	# Lying, the weapon stops at the look the prone down clips are made for (kit #1111).
	var lying := standing.duplicate()
	lying[&"pitch_down"] = 25.0
	var pinned := [
		[tuning.aim_limits, standing],
		[tuning.crouch_aim_limits, standing],
		[CharacterTuning.new().aim_limits, standing],
		[prone.aim_limits, lying],
		[ProneTuning.new().aim_limits, lying],
		[slide.aim_limits, sliding],
		[SlideTuning.new().aim_limits, sliding],
	]
	for pair: Array in pinned:
		assert_array(ExportPins.differences(pair[0], pair[1])).is_empty()
		assert_array(ExportPins.wrong_values(pair[0], pair[1])).is_empty()
	var layer := {
		&"character": _player,
		&"model": _player.model,
		&"animation": _player.get_node("Animation"),
		&"hold": _player.get_node("WeaponHold"),
		&"chain": [&"spine_01", &"spine_02", &"spine_03"] as Array[StringName],
		&"chain_weights": PackedFloat32Array([0.3, 0.3, 0.4]),
		&"converge_distance": 15.0,
		&"release_time": 0.12,
		&"disabled": false,
		&"head_neck_share": 0.4,
		&"head_crouch_neck_share": 0.5,
		&"head_prone_neck_share": 0.5,
		&"head_max_turn": 90.0,
		&"head_disabled": false,
	}
	assert_array(ExportPins.differences(_layer, layer)).is_empty()
	assert_array(ExportPins.wrong_values(_layer, layer)).is_empty()
