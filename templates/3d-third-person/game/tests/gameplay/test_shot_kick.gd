# The pistol's shot kicks the gun up from wherever it aims (kit #1280): the shot's clip is added to
# the aim pose as its difference from its own first frame, so aiming down at a crouched target the
# gun kicks a little and stays on the target, where the replacing clip swung it up to the level aim
# and above on every shot. Driven by commands, read from the muzzle in the drawn pose.
extends GdUnitTestSuite

## The pitches the shots are fired at, in degrees (negative looks down).
const PITCHES: Array[float] = [-45.0, -30.0, -15.0, 0.0, 15.0, 30.0, 45.0]
## How far a shot's kick may differ from the level shot's, in degrees.
const KICK_SPREAD := 4.0
## How far the muzzle may point off the view at rest, aiming down, in degrees (`test_aim_layer.gd`).
const REST_TOLERANCE := 3.0
## Ticks after the press that are read for the kick's peak (the clip, sped up, is over by then).
const SHOT_TICKS := 24

var _arena: PlayArena
var _player: Player


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3(0.0, 0.0, 26.0))
	CommandDriver.take(_player)
	await InputSim.ticks(get_tree(), 6)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


# A command that stands still and aims `pitch` degrees up along -Z.
func _aiming(pitch: float, crouched: bool) -> PlayerCommand:
	var look := CommandCodec.direction_from_angles(0.0, deg_to_rad(pitch))
	var command := CommandDriver.walking(Vector3.ZERO, look)
	command.aim = true
	command.crouch = crouched
	return command


# Degrees the muzzle points above level in the drawn pose.
func _muzzle_pitch() -> float:
	var along := -_player.weapon.muzzle.global_basis.z.normalized()
	return rad_to_deg(asin(clampf(along.y, -1.0, 1.0)))


# Aims at `pitch` until the arm is up and still, fires one shot and returns the muzzle's pitch at
# rest (x), at the shot's highest (y) and at its lowest (z).
func _shoot_at(pitch: float, crouched: bool) -> Vector3:
	var idle := _aiming(0.0, false)
	idle.aim = false
	_player.teleport(Vector3(0.0, 0.0, 26.0), PI)
	await CommandDriver.run(get_tree(), [_player], idle, 20)
	var aimed := _aiming(pitch, crouched)
	await CommandDriver.run(get_tree(), [_player], aimed, 40)
	await _settle()
	var rest := _muzzle_pitch()
	var peak := [rest, rest]
	var shots := [0]
	var count := func(_projectile: Projectile) -> void: shots[0] += 1
	_player.weapon.fired.connect(count)
	var read := func() -> void:
		peak[0] = maxf(peak[0], _muzzle_pitch())
		peak[1] = minf(peak[1], _muzzle_pitch())
	get_tree().process_frame.connect(read)
	# A full magazine, so no reload plays over the shot.
	_player.weapon.make_ready()
	var fire := aimed.clone()
	fire.fire_pressed = true
	await CommandDriver.run(get_tree(), [_player], fire, SHOT_TICKS)
	get_tree().process_frame.disconnect(read)
	_player.weapon.fired.disconnect(count)
	assert_int(shots[0]).override_failure_message("one shot at %s" % pitch).is_equal(1)
	return Vector3(rest, peak[0], peak[1])


# The pose is drawn per render frame, a frame after the tick.
func _settle() -> void:
	for _frame in 2:
		await get_tree().process_frame


func test_the_shot_kicks_the_same_from_every_pitch() -> void:
	for crouched: bool in [false, true]:
		var level := await _shoot_at(0.0, crouched)
		var kick := level.y - level.x
		assert_float(kick).override_failure_message("the level shot kicks").is_greater(3.0)
		for pitch in PITCHES:
			var shot := await _shoot_at(pitch, crouched)
			(
				assert_float(shot.y - shot.x)
				. override_failure_message(
					(
						"crouched %s, pitch %s: the shot kicks %.1f degrees, the level one %.1f"
						% [crouched, pitch, shot.y - shot.x, kick]
					)
				)
				. is_equal_approx(kick, KICK_SPREAD)
			)
			# The kick lifts the gun; it never swings it down past where it aims.
			(
				assert_float(shot.z - shot.x)
				. override_failure_message(
					(
						"crouched %s, pitch %s: the shot drops the gun %.1f degrees"
						% [crouched, pitch, shot.x - shot.z]
					)
				)
				. is_greater(-KICK_SPREAD)
			)


func test_aiming_down_the_muzzle_points_along_the_view() -> void:
	for crouched: bool in [false, true]:
		for pitch: float in [-15.0, -30.0]:
			var shot := await _shoot_at(pitch, crouched)
			(
				assert_float(shot.x)
				. override_failure_message(
					"crouched %s, pitch %s: the muzzle rests at %.1f" % [crouched, pitch, shot.x]
				)
				. is_equal_approx(pitch, REST_TOLERANCE)
			)
