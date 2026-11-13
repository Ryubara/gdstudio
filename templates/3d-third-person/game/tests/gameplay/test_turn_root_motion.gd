# `CharacterTurnMotion` (gdstudio #1442): a body that reverses or cuts off at a run is moved by
# its clip's own root. Through a reversal it keeps going the old way while it brakes, then comes
# back, with its place on the clip's travel curve and its facing on the clip's turn curve every
# committed tick; once the turn is made its steering takes over without a jump in its velocity
# and it runs on at its gait's speed. A body put back mid-turn turns on the same path.
extends GdUnitTestSuite

## Metres the body's place may be off the clip's travel (turned into the frame it ran in).
const PLACE_SLACK := 0.03
## Degrees its facing may be off the clip's turn curve.
const FACING_SLACK := 0.5
## The most the body's velocity may change in a tick through the hand-back (m/s): about the
## steering's own acceleration over a tick (28 m/s² at 60 ticks a second).
const HAND_BACK_STEP := 0.6

var _arena: PlayArena
var _player: Player
var _players: Array[Player] = []


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3(0.0, 0.0, -20.0))
	_player.tuning = _player.tuning.duplicate()
	CommandDriver.take(_player)
	_players = [_player]
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	AudioDrain.stop_all(_arena)


func _command(direction: Vector3, sprint: bool) -> PlayerCommand:
	var command := CommandDriver.walking(direction)
	command.sprint = sprint
	return command


# Runs +z at a jog (or a sprint), then asks for `turn_to`; returns, per tick of the clip, the
# body's place, its facing and the clip's time, and the place and heading it began at.
func _turn(turn_to: Vector3, sprint: bool) -> Dictionary:
	await CommandDriver.run(get_tree(), _players, _command(Vector3.BACK, sprint), 60)
	var start := _player.global_position
	var ticks: Array = []
	var motion := _player.turn_motion
	var record := func(_tick: int) -> void:
		if motion.is_active() or ticks.is_empty():
			(
				ticks
				. append(
					[
						_player.global_position,
						_player.facing,
						motion.elapsed,
						_player.velocity,
						motion.is_committed(),
					]
				)
			)
	await CommandDriver.run(get_tree(), _players, _command(turn_to, sprint), 240, record)
	var committed := ticks.filter(func(tick: Array) -> bool: return tick[4])
	return {
		"start": start,
		"ticks": ticks,
		"committed": committed,
		"clip": motion.clip,
		"release": motion.release_time(),
		"final": _player.velocity,
	}


func _curve_at(curve: Array, time: float, column: int) -> float:
	var frame := time * GaitClips.FPS
	for index in range(curve.size() - 1):
		var a: Array = curve[index]
		var b: Array = curve[index + 1]
		if frame <= b[0]:
			var share := clampf((frame - a[0]) / maxf(b[0] - a[0], 0.001), 0.0, 1.0)
			return lerpf(a[column], b[column], share)
	return curve[-1][column]


# Every tick on the clip's curves, from the place and heading the body ran from (+z, facing 0).
func _assert_follows(run: Dictionary, gait_speed: float) -> void:
	var record := GaitClips.record(run.clip)
	var travel: Array = record.travel
	var turn: Array = record.turn
	var entry: float = (travel[1][1] - travel[0][1]) / (travel[1][0] - travel[0][0]) * GaitClips.FPS
	var scale := gait_speed / entry
	var ticks: Array = run.committed
	assert_int(ticks.size()).is_greater(30)
	# The first tick is the clip's first: the curves are read from the place before it.
	var origin: Vector3 = run.start
	var worst_place := 0.0
	var worst_facing := 0.0
	for tick: Array in ticks:
		var time: float = tick[2]
		var forward := _curve_at(travel, time, 1) * scale
		var left := _curve_at(travel, time, 2) * scale
		# Running +z the body faces 0: its forward is +z and its left +x.
		var expected := origin + Vector3(left, 0.0, forward)
		var place: Vector3 = tick[0]
		worst_place = maxf(
			worst_place, Vector2(place.x - expected.x, place.z - expected.z).length()
		)
		var facing := rad_to_deg(wrapf(tick[1] - deg_to_rad(_curve_at(turn, time, 1)), -PI, PI))
		worst_facing = maxf(worst_facing, absf(facing))
	print(
		(
			"TURN_ROOT %s: %d ticks, %.4f m off travel, %.3f deg off turn"
			% [run.clip, ticks.size(), worst_place, worst_facing]
		)
	)
	(
		assert_float(worst_place)
		. override_failure_message("%s: %.3f m off the travel curve" % [run.clip, worst_place])
		. is_less(PLACE_SLACK)
	)
	(
		assert_float(worst_facing)
		. override_failure_message("%s: %.2f degrees off the turn curve" % [run.clip, worst_facing])
		. is_less(FACING_SLACK)
	)


# The body goes on the old way (+z) after the stick asks it back, comes past its furthest point,
# is handed back with no jump in its velocity and runs on -z at its gait's speed.
func _assert_brakes_and_returns(run: Dictionary, gait_speed: float) -> void:
	var ticks: Array = run.ticks
	var start: Vector3 = run.start
	var furthest := 0.0
	var worst_step := 0.0
	for index in ticks.size():
		var tick: Array = ticks[index]
		furthest = maxf(furthest, (tick[0] as Vector3).z - start.z)
		if index > 0 and not tick[4]:
			var change: Vector3 = tick[3] - ticks[index - 1][3]
			worst_step = maxf(worst_step, Vector2(change.x, change.z).length())
	var first_velocity: Vector3 = ticks[0][3]
	var released: Vector3 = run.committed[-1][3]
	var final: Vector3 = run.final
	print(
		(
			(
				"TURN_BRAKE %s: committed %.2f s, %.2f m on the old way, released at %.2f m/s,"
				+ " hand-back step %.3f m/s, runs on at %.2f m/s"
			)
			% [run.clip, run.release, furthest, -released.z, worst_step, -final.z]
		)
	)
	assert_float(first_velocity.z).is_greater(gait_speed * 0.8)
	assert_float(furthest).is_greater(0.5)
	assert_float(worst_step).is_less(HAND_BACK_STEP)
	assert_float(-final.z).is_equal_approx(gait_speed, 0.05)


func test_a_jog_reversal_brakes_the_old_way_then_runs_back_on_the_clip() -> void:
	var run := await _turn(Vector3.FORWARD, false)
	assert_str(String(run.clip)).starts_with("gds/Jog_Turn_180_")
	_assert_follows(run, _player.tuning.run_speed)
	_assert_brakes_and_returns(run, _player.tuning.run_speed)


func test_a_sprint_reversal_brakes_further_than_a_jog() -> void:
	var run := await _turn(Vector3.FORWARD, true)
	assert_str(String(run.clip)).starts_with("gds/Sprint_Turn_180_")
	_assert_follows(run, _player.tuning.sprint_speed)
	_assert_brakes_and_returns(run, _player.tuning.sprint_speed)


func test_a_cut_at_a_jog_follows_the_pivot_and_turns_its_way() -> void:
	var run := await _turn(Vector3.LEFT, false)
	# Running +z and asked toward -x is a turn to the right.
	assert_str(String(run.clip)).is_equal("gds/Jog_Turn_90_R")
	_assert_follows(run, _player.tuning.run_speed)
	var final: Vector3 = run.final
	assert_float(-final.x).is_equal_approx(_player.tuning.run_speed, 0.05)


func test_the_turn_hands_back_when_it_is_made_or_free_comes_first() -> void:
	for clip: StringName in [&"gds/Jog_Turn_180_L", &"gds/Sprint_Turn_180_L", &"gds/Jog_Turn_90_R"]:
		var record := GaitClips.record(clip)
		var turn: Array = record.turn
		var made := 0.0
		for key: Array in turn:
			if absf(key[1] - turn[-1][1]) < 0.01:
				made = key[0]
				break
		var free: float = record.frames
		for event: Dictionary in record.events:
			if event.name == "free":
				free = minf(free, event.frame)
		var curves := CharacterTurnMotion.curves_of(clip)
		assert_float(curves.release).is_equal_approx(minf(made, free) / GaitClips.FPS, 0.001)
		assert_float(curves.release).is_less(curves.length * 0.8)


func test_letting_go_of_the_stick_ends_the_reversal_at_once() -> void:
	await CommandDriver.run(get_tree(), _players, _command(Vector3.BACK, false), 60)
	await CommandDriver.run(get_tree(), _players, _command(Vector3.FORWARD, false), 6)
	assert_bool(_player.turn_motion.is_active()).is_true()
	await CommandDriver.run(get_tree(), _players, PlayerCommand.new(), 1)
	assert_bool(_player.turn_motion.is_active()).is_false()


func test_off_the_body_turns_by_its_steering_as_before() -> void:
	_player.tuning.turn_root_motion = false
	await CommandDriver.run(get_tree(), _players, _command(Vector3.BACK, false), 60)
	await CommandDriver.run(get_tree(), _players, _command(Vector3.FORWARD, false), 20)
	assert_bool(_player.turn_motion.is_active()).is_false()
	assert_float(_player.velocity.z).is_less(-3.0)


func test_a_body_put_back_mid_turn_turns_on_the_same_path() -> void:
	await _put_back_after(15)


func test_a_body_put_back_in_the_hand_back_steers_on_the_same_path() -> void:
	var release := CharacterTurnMotion.curves_of(&"gds/Jog_Turn_180_L").release
	await _put_back_after(roundi(release * Engine.physics_ticks_per_second) + 4)


func _put_back_after(ticks: int) -> void:
	await CommandDriver.run(get_tree(), _players, _command(Vector3.BACK, false), 60)
	var back := _command(Vector3.FORWARD, false)
	await CommandDriver.run(get_tree(), _players, back, ticks)
	var kept := _player.state_snapshot()
	await CommandDriver.run(get_tree(), _players, back, 20)
	var first := _player.global_position
	_player.restore(kept)
	await CommandDriver.run(get_tree(), _players, back, 20)
	assert_float(_player.global_position.distance_to(first)).is_less(0.001)


func test_a_controller_that_keeps_to_its_path_turns_by_steering() -> void:
	# An AI's controller turns it off: its body keeps to the navigator's path.
	var controller: CharacterController = auto_free(CharacterController.new())
	controller.turn_clips = false
	_player.controller = controller
	await CommandDriver.run(get_tree(), _players, _command(Vector3.BACK, false), 60)
	await CommandDriver.run(get_tree(), _players, _command(Vector3.FORWARD, false), 20)
	assert_bool(_player.turn_motion.is_active()).is_false()
	assert_float(_player.velocity.z).is_less(-3.0)
	assert_bool((auto_free(AiController.new()) as AiController).turn_clips).is_false()
