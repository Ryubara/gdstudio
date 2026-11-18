# The drawn reversal and pivot (gdstudio #1574), on the real player through its input actions,
# stepped a tick at a time with its tree as `MoveKeyMatrix` does. Every value of
# `CharacterTuning`'s Turns group that shapes a turn's look or timing is changed on a player that
# is already running (as the inspector and the remote inspector do) and the next turn reads it.
#
# `test_the_turn_times_from_the_press` prints a `TURNTIME` line a case (a jog and a sprint
# reversal, W to S, and a quarter turn of the keys, W+A to W+D): the ticks from the press until
# the drawn body (the facing and the rig's turn, `TurnLook`) is half way round and within 10
# degrees of the new way, until the velocity starts toward it, and the most the drawn body and the
# body's facing are apart. `GDS_TURN_TRACE` prints each tick.
extends GdUnitTestSuite

const CASES := [
	["jog W to S", "jog", [["W", 80], ["S", 70]]],
	["sprint W to S", "sprint", [["W", 80], ["S", 70]]],
	["jog W+A to W+D", "jog", [["WA", 80], ["WD", 70]]],
]
# Ticks a second of the template.
const RATE := 60.0

var _arena: PlayArena
var _matrix: MoveKeyMatrix
var _player: Player
var _tuning: CharacterTuning
var _trace := OS.get_environment("GDS_TURN_TRACE") != ""


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_arena.add_block(Vector2.ZERO, Vector3(400.0, 1.0, 400.0), 0.0)
	_player = _arena.add_player(Vector3.ZERO)
	_player.tuning = (
		(load("res://gameplay/player/player_tuning.tres") as CharacterTuning).duplicate()
	)
	_tuning = _player.tuning
	_player.set_physics_process(false)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 40.0, 0.0)
	_arena.add_child(camera)
	camera.make_current()
	_matrix = MoveKeyMatrix.new()
	_matrix.player = _player
	_matrix.input = _player.controller as PlayerInput
	_matrix.animation = _player.get_node("Animation")
	_matrix.camera = camera
	_matrix.tree = get_tree()
	await InputSim.ticks(get_tree(), 4)
	_matrix.animation.set_throttled(true)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


# Steps `steps` at `gait` (a step is `[keys, ticks]` or `[keys, ticks, camera degrees]`) and
# returns one sample a tick of the last step: `{left, apart, kind, time, offset, along, before,
# serial}`, with `left` the degrees from the drawn body to the way asked, `apart` the degrees
# between the drawn body and the facing, `along` the velocity's share along the wish (m/s) after
# the tick and `before` before it, `serial` the transitions begun or ended since the step began.
func _turn(gait: String, steps: Array) -> Array:
	await _matrix._settle()
	_player.teleport(Vector3.ZERO, PI)
	_matrix.camera.rotation = Vector3.ZERO
	var held: Key = MoveKeyMatrix.GAIT_KEYS[gait]
	if held != KEY_NONE:
		InputSim.key(held, true)
	var animation := _matrix.animation
	var transitions := animation.gait.transitions
	var step_seconds := 1.0 / RATE
	var samples: Array = []
	var serial := 0
	for index in steps.size():
		var step: Array = steps[index]
		_matrix._hold(step[0])
		if step.size() > 2:
			_matrix.camera.rotation = Vector3(0.0, deg_to_rad(step[2]), 0.0)
		var last := index == steps.size() - 1
		serial = transitions.serial
		for count in int(step[1]):
			if count % 6 == 0:
				await get_tree().physics_frame
			var prior := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
			_player.step(_matrix.input.sample(), step_seconds)
			animation.advance(step_seconds)
			if not last:
				continue
			var wish := _player._wish_direction().normalized()
			var drawn := _player.facing + transitions.look.offset
			var velocity := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
			var sample := {
				"left": rad_to_deg(absf(angle_difference(drawn, atan2(wish.x, wish.z)))),
				"apart": rad_to_deg(absf(transitions.look.offset)),
				"kind": transitions.kind,
				"time": transitions.time(),
				"offset": transitions.look.offset,
				"along": velocity.dot(wish),
				"before": prior.dot(wish),
				"serial": transitions.serial - serial,
			}
			samples.append(sample)
			if _trace:
				print("TRACE %d %s" % [count + 1, sample])
	_matrix._hold("")
	if held != KEY_NONE:
		InputSim.key(held, false)
	return samples


# The ticks from the press until the drawn body has turned `share` of its way round (1: within
# 10 degrees), or -1.
func _ticks_to(samples: Array, share: float) -> int:
	var whole: float = samples[0].left
	for index in samples.size():
		var left: float = samples[index].left
		if (share >= 1.0 and left <= 10.0) or (share < 1.0 and left <= whole * (1.0 - share)):
			return index + 1
	return -1


# Ticks a look of `kind` played from the press, and the clip time it began at (-1: none).
func _look(samples: Array, kind: GaitTransitions.Kind) -> Dictionary:
	var ticks := 0
	var began := -1.0
	for sample: Dictionary in samples:
		if sample.kind == kind:
			if began < 0.0:
				began = sample.time
			ticks += 1
		elif ticks > 0:
			break
	return {"ticks": ticks, "began": began}


func _reversal(gait: String) -> Array:
	return await _turn(gait, [["W", 80], ["S", 70]])


# A jog, then the camera turned `degrees` with W held: the way asked turns that far.
func _cut(degrees: float) -> Array:
	return await _turn("jog", [["W", 80], ["W", 50, degrees]])


func test_the_turn_times_from_the_press() -> void:
	for case: Array in CASES:
		var samples := await _turn(case[1], case[2])
		var half := _ticks_to(samples, 0.5)
		var near := _ticks_to(samples, 1.0)
		var answered := -1
		var apart := 0.0
		for index in samples.size():
			var sample: Dictionary = samples[index]
			apart = maxf(apart, sample.apart)
			if answered < 0 and sample.along > float(samples[0].before) + 0.05:
				answered = index + 1
		print(
			(
				(
					"TURNTIME | %s | half %d ticks (%.2f s) | within 10 deg %d ticks (%.2f s)"
					% [case[0], half, half / RATE, near, near / RATE]
				)
				+ " | velocity %d | drawn and facing apart at most %.0f deg" % [answered, apart]
			)
		)
		assert_int(answered).is_equal(1)
		# Slower than before #1574 (half round in 4 ticks), still short.
		assert_int(half).is_between(6, 30)
		assert_int(near).is_between(12, 50)


func test_the_reversal_look_times_set_how_long_each_reversal_is_drawn() -> void:
	_tuning.jog_reversal_look_time = 0.3
	var short := _look(await _reversal("jog"), GaitTransitions.Kind.REVERSAL)
	_tuning.jog_reversal_look_time = 0.9
	var long := _look(await _reversal("jog"), GaitTransitions.Kind.REVERSAL)
	assert_int(short.ticks).is_between(16, 20)
	assert_int(long.ticks).is_between(52, 56)
	_tuning.sprint_reversal_look_time = 0.4
	short = _look(await _reversal("sprint"), GaitTransitions.Kind.REVERSAL)
	_tuning.sprint_reversal_look_time = 1.0
	long = _look(await _reversal("sprint"), GaitTransitions.Kind.REVERSAL)
	assert_int(short.ticks).is_between(22, 26)
	assert_int(long.ticks).is_between(58, 62)


func test_the_pivot_look_time_sets_how_long_a_pivot_is_drawn() -> void:
	_tuning.pivot_look_time = 0.3
	var short := _look(await _cut(115.0), GaitTransitions.Kind.PIVOT)
	_tuning.pivot_look_time = 0.8
	var long := _look(await _cut(115.0), GaitTransitions.Kind.PIVOT)
	assert_int(short.ticks).is_between(16, 20)
	assert_int(long.ticks).is_between(46, 50)


func test_the_look_angles_pick_the_reversal_and_the_pivot() -> void:
	_tuning.look_pivot_angle = 100.0
	assert_int(_look(await _cut(115.0), GaitTransitions.Kind.PIVOT).ticks).is_greater(0)
	_tuning.look_pivot_angle = 125.0
	assert_int(_look(await _cut(115.0), GaitTransitions.Kind.PIVOT).ticks).is_equal(0)
	_tuning.look_reversal_angle = 135.0
	assert_int(_look(await _cut(150.0), GaitTransitions.Kind.REVERSAL).ticks).is_greater(0)
	_tuning.look_reversal_angle = 160.0
	var samples := await _cut(150.0)
	assert_int(_look(samples, GaitTransitions.Kind.REVERSAL).ticks).is_equal(0)
	assert_int(_look(samples, GaitTransitions.Kind.PIVOT).ticks).is_greater(0)


func test_the_lead_sets_where_in_the_clip_the_look_begins() -> void:
	_tuning.turn_look_lead = 0.0
	var at_turn: float = _look(await _reversal("jog"), GaitTransitions.Kind.REVERSAL).began
	_tuning.turn_look_lead = 0.4
	var earlier: float = _look(await _reversal("jog"), GaitTransitions.Kind.REVERSAL).began
	assert_float(at_turn - earlier).is_between(0.3, 0.45)


func test_the_cut_angle_sets_how_far_the_stick_moves_before_the_look_gives_way() -> void:
	# A jog reversal, then S+D 8 ticks in: the way asked moves 45 degrees.
	var steps := [["W", 80], ["S", 8], ["SD", 40]]
	_tuning.turn_look_cut_angle = 40.0
	var cut := await _turn("jog", steps)
	_tuning.turn_look_cut_angle = 55.0
	var kept := await _turn("jog", steps)
	# Cut, the reversal ends on the change (another clip may begin); kept, it plays on.
	assert_int(int(cut[2].serial)).is_greater(0)
	assert_int(int(kept[2].serial)).is_equal(0)
	assert_int(int(kept[2].kind)).is_equal(GaitTransitions.Kind.REVERSAL)


func test_the_settle_sets_how_fast_a_cut_look_eases_onto_the_facing() -> void:
	# A sprint reversal cut 8 ticks in by S+D; 6 ticks after the cut the drawn turn left differs.
	var steps := [["W", 80], ["S", 8], ["SD", 20]]
	_tuning.turn_look_settle = 0.02
	var quick := await _turn("sprint", steps)
	_tuning.turn_look_settle = 0.2
	var slow := await _turn("sprint", steps)
	assert_float(absf(quick[6].offset)).is_less(absf(slow[6].offset) * 0.5)
	assert_float(absf(slow[6].offset)).is_greater(0.01)


func test_the_brake_sets_how_fast_a_reversal_sheds_its_speed() -> void:
	# The brake is never softer than `acceleration` (28 m/s²).
	_tuning.brake_deceleration = 30.0
	var soft := await _reversal("sprint")
	_tuning.brake_deceleration = 80.0
	var hard := await _reversal("sprint")
	# Three ticks after the press: 1.5 m/s against 4 m/s shed from -6.5.
	assert_float(soft[2].along).is_equal_approx(-5.0, 0.2)
	assert_float(hard[2].along).is_equal_approx(-2.5, 0.2)
