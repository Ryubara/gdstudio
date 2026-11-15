# Every combination of movement keys a player presses, on the real player through its input
# actions (gdstudio #1563): each direction alone, each opposing pair held together, overlapped and
# swapped with gaps below and above the let-go grace, the diagonals there and back, letting go of
# every held set, a let-go pressed again inside and outside the grace and quick taps of the other
# key, at a walk, a jog, a sprint and crouched. A stop belongs only to the move input going to
# zero: it never begins while a movement key is held, and a let-go shorter than the grace plays
# none. Each case prints a `MATRIX` line: the keys, then each clip that began (tick, keys held,
# kind, clip, ticks it played, cut or not); `GDS_MATRIX_OUT` names a file to append them to.
#
# Before the fix W then S (or A then D) held together was no input at all, so it played the stop,
# cut when the first key went up; a let-go of a tick or two between two keys did the same.
#
# The `test_answers_*`, `test_spam_*` and `test_actions_*` cases (gdstudio #1565) measure how fast
# the body answers (`MoveResponse`): per key change the ticks until its velocity starts toward the
# new wish, until it is within 30 degrees of it, and until the transition clip drawn before is left;
# random direction changes during each kind of clip (start, stop, reversal, pivot, landing); and
# crouch, prone, aim, jump and fire pressed during each clip, which must end it at once with no
# jump of the drawn pose. Each prints a `RESPONSE` line (to `GDS_MATRIX_OUT` too). Before the fix a
# reversal or a pivot held the body on its clip's path until its turn was made (1.5 to 2.2 s) and a
# hard landing held it 0.67 s, every key pressed meanwhile ignored.
extends GdUnitTestSuite

# The key changes from a steady run: back, aside, back and aside, and W+A to W+D at once and with
# W alone for 3 ticks between.
const _CHANGES := [
	["W then S", [["W", 80], ["S", 60]], [1]],
	["W then D", [["W", 80], ["D", 60]], [1]],
	["W then S+D", [["W", 80], ["SD", 60]], [1]],
	["W+A then W+D", [["WA", 80], ["WD", 60]], [1]],
	["W+A, W 3 ticks, W+D", [["WA", 80], ["W", 3], ["WD", 60]], [2]],
]

var _arena: PlayArena
var _matrix: MoveKeyMatrix
var _response: MoveResponse


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_arena.add_block(Vector2.ZERO, Vector3(400.0, 1.0, 400.0), 0.0)
	var player := _arena.add_player(Vector3.ZERO)
	player.tuning = (
		(load("res://gameplay/player/player_tuning.tres") as CharacterTuning).duplicate()
	)
	player.tuning.crouch_toggle = false
	player.set_physics_process(false)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 40.0, 0.0)
	_arena.add_child(camera)
	camera.make_current()
	_matrix = MoveKeyMatrix.new()
	_matrix.player = player
	_matrix.input = player.controller as PlayerInput
	_matrix.animation = player.get_node("Animation")
	_matrix.camera = camera
	_matrix.tree = get_tree()
	_response = MoveResponse.new()
	_response.matrix = _matrix
	await InputSim.ticks(get_tree(), 4)
	_matrix.animation.set_throttled(true)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


func _check(gait: String, yaw: float, subset := false) -> void:
	await _matrix.play_all(gait, yaw, MoveKeyMatrix.cases(gait, subset))
	var out := OS.get_environment("GDS_MATRIX_OUT")
	var file: FileAccess = null
	if out != "":
		file = FileAccess.open(out, FileAccess.READ_WRITE)
		if file == null:
			file = FileAccess.open(out, FileAccess.WRITE)
		else:
			file.seek_end()
	for line in _matrix.lines:
		print("MATRIX | ", line)
		if file != null:
			file.store_line(line)
	if file != null:
		file.close()
	assert_array(Array(_matrix.failures)).is_empty()


func test_at_a_walk() -> void:
	await _check("walk", 0.0)


func test_at_a_jog() -> void:
	await _check("jog", 0.0)


func test_at_a_sprint() -> void:
	await _check("sprint", 0.0)


func test_crouched() -> void:
	await _check("crouch", 0.0)


func test_with_the_camera_turned() -> void:
	for gait: String in ["walk", "jog", "sprint"]:
		await _check(gait, deg_to_rad(135.0), true)
		_matrix.lines.clear()


func _answers(gait: String, yaw: float) -> void:
	for case: Array in _CHANGES:
		var samples := await _response.run(gait, yaw, case[1])
		_response.check(case[0], gait, yaw, samples, case[2])
	_report()


func test_answers_at_a_jog() -> void:
	await _answers("jog", 0.0)


func test_answers_at_a_sprint() -> void:
	await _answers("sprint", 0.0)


func test_answers_with_the_camera_turned() -> void:
	await _answers("jog", deg_to_rad(135.0))
	await _answers("sprint", deg_to_rad(-60.0))


# What starts each kind of clip, as the steps before the spam or the action.
func _lead_in(kind: String) -> Array:
	var grace := MoveKeyMatrix.grace_ticks()
	match kind:
		"start":
			return [["", 10], ["W", 4]]
		"stop":
			return [["W", 80], ["", grace + 4]]
		"reversal":
			return [["W", 80], ["S", 6]]
		"pivot":
			return [["W", 80], ["W", 6, "", 115.0]]
	return []


func _spam(gait: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = MoveResponse.SEED
	for kind: String in ["start", "stop", "reversal", "pivot"]:
		var steps := _lead_in(kind)
		var lead := steps.size()
		var last: String = steps[-1][0]
		steps.append_array(MoveResponse.spam(rng, last, 10))
		if kind == "pivot":
			for index in range(lead, steps.size()):
				steps[index] = [steps[index][0], steps[index][1], "", 115.0]
		var samples := await _response.run(gait, 0.0, steps)
		_response.check("spam in a %s" % kind, gait, 0.0, samples, range(lead, steps.size()), true)
	_report()


func test_spam_through_each_clip_at_a_jog() -> void:
	await _spam("jog")


func test_spam_through_each_clip_at_a_sprint() -> void:
	await _spam("sprint")


# Random direction changes as a body lands hard from 8 m, running, and through its landing.
func test_spam_through_a_hard_landing() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = MoveResponse.SEED + 1
	var steps: Array = [["W", 4]]
	steps.append_array(MoveResponse.spam(rng, "W", 40))
	var samples := await _response.run("jog", 0.0, steps, 8.0)
	var landed := false
	for sample: Dictionary in samples:
		landed = landed or sample.state == Character.State.LAND
	assert_bool(landed).override_failure_message("the body never landed").is_true()
	_response.check("spam through a hard landing", "jog", 0.0, samples, range(1, steps.size()))
	_report()


func _actions(gait: String) -> void:
	for action: String in MoveResponse.ACTION_KEYS:
		# The same action from the steady gait: what the hand-off from a clip is held against.
		var plain_steps: Array = [["W", 80], ["W", MoveResponse.POSE_TICKS + 4, action]]
		plain_steps.append_array(_after_action(action))
		var plain_samples := await _response.run(gait, 0.0, plain_steps, 0.0, true)
		var plain := MoveResponse.peak_move(plain_samples, 1)
		for kind: String in ["start", "stop", "reversal", "pivot"]:
			var steps := _lead_in(kind)
			var at := steps.size()
			var last: Array = steps[-1]
			var turn: float = last[3] if last.size() > 3 else 0.0
			steps.append([last[0], MoveResponse.POSE_TICKS + 4, action, turn])
			steps.append_array(_after_action(action))
			var samples := await _response.run(gait, 0.0, steps, 0.0, true)
			_response.check_action("%s in a %s" % [action, kind], gait, samples, at, plain)
	_report()


# Steps after an action's case that leave the body standing for the next: lying down is a toggle.
func _after_action(action: String) -> Array:
	if action == "prone":
		return [["", 2, "prone"], ["", 90]]
	return [["", 60]]


func test_actions_end_each_clip_at_a_jog() -> void:
	await _actions("jog")


func test_actions_end_each_clip_at_a_sprint() -> void:
	await _actions("sprint")


func _report() -> void:
	var out := OS.get_environment("GDS_MATRIX_OUT")
	var file: FileAccess = null
	if out != "":
		file = FileAccess.open(out, FileAccess.READ_WRITE)
		if file == null:
			file = FileAccess.open(out, FileAccess.WRITE)
		else:
			file.seek_end()
	for line in _response.lines:
		print("RESPONSE | ", line)
		if file != null:
			file.store_line("RESPONSE | " + line)
	if file != null:
		file.close()
	var failed := Array(_response.failures)
	_response.lines.clear()
	_response.failures.clear()
	assert_array(failed).is_empty()
