# A hard landing holds a still body until its clip gives control back (gdstudio #1535): a fall of
# `CharacterTuning.hard_land_speed` or more holds the body for `hard_land_time` (the hard landing
# clip's `control` frame) as an action holds it, so the tree plays `Land_Hard` to that frame with
# its planted feet still. A push of the stick ends the hold on that tick (gdstudio #1565: a landing
# recovery never holds movement input) and the tree gives the legs back at once. A soft landing
# holds nothing, as before. The hold is the body's step state (`_action_lock`), so a body put back
# mid-hold (a predicting client, the server) steps the same.
extends GdUnitTestSuite

## How far a planted foot of the hard landing may slide before its control frame (m).
const PLANTED_SLIDE := 0.003
## The share of a flat window its foot takes to settle on the floor, left out of the measure.
const ROLL_ON := 0.25
## The bones whose places say where a foot is.
const FEET: Dictionary[String, StringName] = {"l": &"ball_l", "r": &"ball_r"}

var _arena: PlayArena
var _player: Player
var _animation: CharacterAnimation
var _skeleton: Skeleton3D
# Each drawn frame of the hard landing: [the clip's time, {foot: world place}].
var _frames: Array = []


func before_test() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	_animation = _player.get_node("Animation")
	CommandDriver.take(_player)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_skeleton = _player.model.skeleton()
	_skeleton.skeleton_updated.connect(_on_skeleton_updated)
	_animation.set_throttled(true)
	_frames.clear()


func after_test() -> void:
	if (
		is_instance_valid(_skeleton)
		and _skeleton.skeleton_updated.is_connected(_on_skeleton_updated)
	):
		_skeleton.skeleton_updated.disconnect(_on_skeleton_updated)


func _on_skeleton_updated() -> void:
	var playback := _animation._playback
	if playback.get_current_node() != CharacterAnimation.LAND:
		return
	if _animation.gait.jump.landing != CharacterClips.LAND_HARD:
		return
	var places := {}
	for foot: String in FEET:
		var pose := _skeleton.get_bone_global_pose(_skeleton.find_bone(FEET[foot]))
		places[foot] = (_skeleton.global_transform * pose).origin
	_frames.append([playback.get_current_play_position(), places])


func _command(push: float, jump := false) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.move = Vector2(0.0, push)
	command.jump = jump
	command.jump_pressed = jump
	return command


# Steps one tick of `command` and draws it.
func _tick(command: PlayerCommand) -> void:
	var step := CommandDriver.tick_seconds()
	await get_tree().physics_frame
	_player.step(command, step)
	command.clear_edges()
	_animation.advance(step)


func _ticks(command: PlayerCommand, count: int) -> void:
	for tick in count:
		await _tick(command)


# Steps a still stand until the body has landed from where it is: the ticks it took.
func _until_landed(command: PlayerCommand, count := 120) -> int:
	for tick in count:
		if _player.state == Character.State.LAND:
			return tick
		await _tick(command)
	fail("the body never landed (it is in %s)" % Character.State.keys()[_player.state])
	return count


# Steps `command` until the body leaves its landing state: the seconds it was in it, counted from
# the tick it landed on.
func _land_seconds(command: PlayerCommand) -> float:
	var ticks := 1
	while _player.state == Character.State.LAND and ticks < 200:
		await _tick(command)
		ticks += 1
	return (ticks - 1) * CommandDriver.tick_seconds()


# Puts the body `height` up and steps it until it lands, the stick pushed by `push` in the air.
func _drop(height: float, push := 0.0) -> void:
	await _ticks(_command(0.0), 20)
	_player.global_position = Vector3(0.0, height, 0.0)
	await _until_landed(_command(push))


func test_the_hold_is_the_hard_landing_clip_s_numbers() -> void:
	var tuning := CharacterTuning.new()
	var record := GaitClips.record(CharacterClips.LAND_HARD)
	assert_float(tuning.hard_land_speed).is_equal_approx(float(record.fall_speed.from), 0.0001)
	assert_float(tuning.hard_land_time).is_equal_approx(
		float(record.control) / GaitClips.FPS, 0.001
	)
	# The soft landing's control frame is inside `land_time`, so it needs no hold.
	var soft := GaitClips.record(CharacterClips.LAND)
	assert_float(float(soft.control) / GaitClips.FPS).is_less_equal(tuning.land_time + 0.0001)
	assert_float(tuning.land_hold_after(tuning.hard_land_speed - 0.1)).is_equal(0.0)
	assert_float(tuning.land_hold_after(tuning.hard_land_speed)).is_equal(tuning.hard_land_time)
	assert_float(tuning.land_time_after(tuning.hard_land_speed, 0.0)).is_equal(
		tuning.hard_land_time
	)
	assert_float(tuning.land_time_after(tuning.land_clip_speed, 0.0)).is_equal(tuning.land_time)
	assert_float(tuning.land_time_after(1.0, 0.125)).is_equal(0.125)


func test_a_hard_landing_holds_a_still_body_and_a_push_frees_it_at_once() -> void:
	await _drop(3.0)
	assert_str(String(_animation.gait.jump.landing)).is_equal(String(CharacterClips.LAND_HARD))
	var landed_at := _player.global_position
	await _ticks(_command(0.0), 10)
	assert_int(_player.state).is_equal(Character.State.LAND)
	assert_float(_player._action_lock).is_greater(0.0)
	var moved := Vector2(
		_player.global_position.x - landed_at.x, _player.global_position.z - landed_at.z
	)
	assert_float(moved.length()).is_less(0.0005)
	# Pushed, the body moves from that tick and leaves its landing state with the hold.
	var walk := _command(1.0)
	await _tick(walk)
	assert_float(_player._action_lock).is_equal(0.0)
	assert_float(_player.ground_speed()).is_greater(0.3)
	assert_int(_player.state).is_not_equal(Character.State.LAND)
	await _ticks(walk, 3)
	assert_str(String(_animation.body_state())).is_not_equal(String(CharacterAnimation.LAND))


func test_a_hard_landing_s_planted_feet_hold_the_floor_to_its_control_frame() -> void:
	# Standing, the held body leaves the clip's planted feet still to its control frame.
	var standing := await _feet_after_drop(0.0, 0.0)
	for window: String in standing:
		prints("HARD_LANDING %s: slid %.2f mm standing" % [window, standing[window] * 1e3])
		assert_float(standing[window]).is_less(PLANTED_SLIDE)
	assert_int(standing.size()).is_equal(2)


# Drops the body 3 m (the stick pushed by `fall_push` in the air), pushes it by `push` from the
# touch-down until past the hold, and
# measures how far each planted foot of `Land_Hard` slid over the floor up to its control frame:
# by window (`<foot> <first>-<last>`), each from a quarter into its flat frames (the roll onto the
# floor left out, as `test_gait_stops.gd` does); INF for a window no drawn frame reached.
func _feet_after_drop(push: float, fall_push: float) -> Dictionary:
	_frames.clear()
	await _drop(3.0, fall_push)
	await _ticks(_command(push), int(_player.tuning.hard_land_time * 60.0) + 6)
	await _ticks(_command(0.0), 60)
	var record := GaitClips.record(CharacterClips.LAND_HARD)
	var control := float(record.control)
	var out := {}
	for foot: String in FEET:
		for window: Array in record.flat[foot]:
			var first := float(window[0]) + ROLL_ON * (float(window[1]) - float(window[0]))
			var last := minf(float(window[1]), control)
			if last <= first:
				continue
			var start := Vector3.INF
			var slide := 0.0
			var seen := 0
			for frame: Array in _frames:
				var at := float(frame[0]) * GaitClips.FPS
				if at < first or at > last:
					continue
				var place: Vector3 = frame[1][foot]
				if start == Vector3.INF:
					start = place
				slide = maxf(slide, Vector2(place.x - start.x, place.z - start.z).length())
				seen += 1
			# A window the clip never reached (cut before it) counts as failed.
			out["%s %.0f-%.0f" % [foot, first, last]] = slide if seen > 1 else INF
	return out


func test_a_hard_landing_holds_the_jump_of_a_still_body_and_a_push_turns_it() -> void:
	await _drop(3.0)
	var facing := _player.facing
	var jump := _command(0.0, true)
	await _tick(jump)
	await _ticks(_command(0.0), 10)
	assert_bool(_player.is_on_floor()).is_true()
	assert_float(_player.velocity.y).is_less_equal(0.0)
	# A push frees it at once and the body turns to the stick (gdstudio #1565).
	await _ticks(_command(-1.0), 10)
	assert_float(absf(angle_difference(facing, _player.facing))).is_greater(0.5)


func test_a_soft_landing_holds_nothing() -> void:
	await _ticks(_command(0.0), 20)
	var held := _command(0.0, true)
	await _tick(held)
	held.jump_pressed = false
	await _until_landed(held)
	assert_float(_player._action_lock).is_equal(0.0)
	assert_str(String(_animation.gait.jump.landing)).is_equal(String(CharacterClips.LAND))
	var walk := _command(1.0)
	await _tick(walk)
	await _tick(walk)
	assert_float(_player.ground_speed()).is_greater(0.5)
	var seconds := (await _land_seconds(walk)) + 2.0 * CommandDriver.tick_seconds()
	prints("SOFT_LANDING pushed: in its landing state %.3f s" % seconds)
	assert_float(seconds).is_equal_approx(_player.tuning.land_time, 0.02)


func test_a_body_put_back_mid_hold_steps_the_same() -> void:
	await _drop(3.0)
	await _ticks(_command(0.0), 5)
	var walk := _command(1.0)
	var kept := _player.state_snapshot()
	var first: Array[Vector3] = []
	for tick in 60:
		await _tick(walk)
		first.append(_player.global_position)
	_player.restore(kept)
	for tick in 60:
		await _tick(walk)
		assert_vector(_player.global_position).is_equal(first[tick])
	assert_float(first[-1].distance_to(first[0])).is_greater(1.0)


func test_hard_land_time_and_speed_are_live() -> void:
	_player.tuning = _player.tuning.duplicate()
	_player.tuning.hard_land_time = 0.0
	await _drop(3.0)
	await _tick(_command(1.0))
	await _tick(_command(1.0))
	assert_float(_player.ground_speed()).is_greater(0.5)
	_player.tuning.hard_land_time = 1.0
	_player.tuning.hard_land_speed = 20.0
	await _ticks(_command(0.0), 60)
	await _drop(3.0)
	await _tick(_command(1.0))
	await _tick(_command(1.0))
	assert_float(_player.ground_speed()).is_greater(0.5)
	_player.tuning.hard_land_speed = 9.0
	await _ticks(_command(0.0), 60)
	await _drop(3.0)
	await _ticks(_command(0.0), 50)
	assert_int(_player.state).is_equal(Character.State.LAND)
	await _ticks(_command(0.0), 14)
	assert_int(_player.state).is_not_equal(Character.State.LAND)


func test_hard_land_keep_is_live() -> void:
	_player.tuning = _player.tuning.duplicate()
	await _drop(3.0, 1.0)
	assert_float(_player.ground_speed()).is_equal(0.0)
	_player.tuning.hard_land_keep = 1.0
	await _ticks(_command(0.0), 30)
	await _drop(3.0, 1.0)
	var kept := _player.ground_speed()
	assert_float(kept).is_greater(1.0)
	await _tick(_command(0.0))
	# Held, it slows by `deceleration` with the stick let go.
	assert_float(_player.ground_speed()).is_equal_approx(
		kept - _player.tuning.deceleration * CommandDriver.tick_seconds(), 0.01
	)


func test_a_teleport_ends_the_hold() -> void:
	# A body put somewhere (a respawn, a bench's next run) stands there free, not held by the
	# landing it left (`test_jump_reach.gd` runs again from its start after a fall into the gap).
	await _drop(3.0)
	_player.teleport(Vector3(2.0, 0.0, 0.0))
	assert_int(_player.state).is_equal(Character.State.IDLE)
	await _tick(_command(1.0))
	await _tick(_command(1.0))
	assert_float(_player.ground_speed()).is_greater(0.5)


func test_a_body_put_down_mid_fall_does_not_land_hard() -> void:
	# A teleport keeps no fall speed: the body falling 11 m/s and put on the floor lands softly
	# (`test_jump_reach.gd` starts each run where the last one fell into the gap).
	_player.global_position = Vector3(0.0, 6.0, 0.0)
	await _ticks(_command(0.0), 40)
	assert_float(_player._fall_speed).is_greater(9.0)
	_player.teleport(Vector3(0.0, 0.05, 0.0))
	await _ticks(_command(1.0), 4)
	assert_float(_player._action_lock).is_equal(0.0)
	assert_float(_player.ground_speed()).is_greater(0.5)
