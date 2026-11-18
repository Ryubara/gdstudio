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
# jump of the drawn pose. Lying down and getting up are held to the crouch's bound over what
# their clip alone moves (gdstudio #1568); `GDS_POSE_TRACE` adds each case's moves a tick to its
# line. Each prints a `RESPONSE` line (to `GDS_MATRIX_OUT` too). Before the fix a
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
	var plains := {}
	for action: String in MoveResponse.ACTION_KEYS:
		# The same action from the steady gait: what the hand-off from a clip is held against.
		var plain_steps: Array = [["W", 80], ["W", MoveResponse.POSE_TICKS + 4, action]]
		plain_steps.append_array(_after_action(action))
		var plain_samples := await _response.run(gait, 0.0, plain_steps, 0.0, true)
		plains[action] = MoveResponse.peak_move(plain_samples, 1)
		var bound: String = MoveResponse.BOUND_OF.get(action, action)
		var plain: float = plains[bound]
		var own := PackedFloat32Array()
		if bound != action:
			own = await _own_clip(gait, action, plain, plain_samples)
		for kind: String in ["start", "stop", "reversal", "pivot"]:
			var steps := _lead_in(kind)
			var at := steps.size()
			var last: Array = steps[-1]
			var turn: float = last[3] if last.size() > 3 else 0.0
			steps.append([last[0], MoveResponse.POSE_TICKS + 4, action, turn])
			steps.append_array(_after_action(action))
			var samples := await _response.run(gait, 0.0, steps, 0.0, true)
			_response.check_action(
				"%s in a %s" % [action, kind], gait, samples, at, plain, true, own
			)
	_report()


# Lying down and getting up are held to the crouch's hand-off (gdstudio #1568): before, the drawn
# body went from upright to lying in one frame and the to-prone clip lifted it. Each tick may add
# that bound to what the clip alone moves then, read from a crouch at rest (where the clip starts
# on the drawn pose, checked first): the clip is 0.9 s played in 0.5, and its leg sweep moves a
# toe 0.33 m a tick. Checks lying down from the steady gait (`plain_samples`) and getting up from
# lying still; returns the clip's own moves going down, for the cases from each transition clip.
func _own_clip(
	gait: String, action: String, plain: float, plain_samples: Array
) -> PackedFloat32Array:
	var ref_steps: Array = [["", 60], ["", 40, action], ["", 2, action], ["", 90]]
	var ref := await _response.run("crouch", 0.0, ref_steps, 0.0, true)
	var down := MoveResponse.moves_from(ref, 1)
	var up := MoveResponse.moves_from(ref, 2)
	_response.check_clip_start("lying down from a crouch at rest", gait, down)
	_response.check_clip_start("getting up to a crouch", gait, up)
	_response.check_action("%s from the gait" % action, gait, plain_samples, 1, plain, false, down)
	var up_steps: Array = [["W", 80], ["", 60, action], ["", 2, action], ["", 90]]
	var up_samples := await _response.run(gait, 0.0, up_steps, 0.0, true)
	_response.check_action("getting up", gait, up_samples, 2, plain, false, up)
	return down


# Steps after an action's case that leave the body standing for the next: lying down is a toggle.
func _after_action(action: String) -> Array:
	if action == "prone":
		return [["", 2, "prone"], ["", 90]]
	return [["", 60]]


# Every stance change, each way (gdstudio #1576), from standing still or moving with `keys`: no
# drawn bone moves further in a tick than the crouch's hand-off from the same gait allows (`plain`,
# from the steady gait, or the crouch from rest at a stand), on top of what the stance clip alone
# moves then (`_stance_clips()`), over `MoveResponse.STANCE_TICKS` from the press: the whole clip
# and its end. Before the fix getting up ended on the crouch idle and the one-shot's 0.1 s fade-out
# put the standing idle under it, the drawn body rising 0.4 m in six ticks with nothing carried.
func _stance_changes(
	gait: String, keys: String, plain: float, clips: Dictionary, weapon := "pistol"
) -> void:
	var t := MoveResponse.STANCE_TICKS
	# Into the steady gait first (its start clip over), or a moment standing still.
	var lead := 60 if keys == "" else 80
	var cases: Array = [
		["stand to prone", [[keys, lead], [keys, 2, "prone"], [keys, t]], 1, clips.down],
		[
			"prone to stand",
			[[keys, 10], [keys, 2, "prone"], ["", 80], ["", 2, "prone"], [keys, t]],
			3,
			clips.up,
		],
		[
			"crouch to prone",
			[[keys, lead, "crouch"], [keys, 2, "crouch+prone"], [keys, t, "crouch"]],
			1,
			clips.down,
		],
		[
			"prone to crouch",
			[
				["", 10],
				["", 2, "prone"],
				["", 80, "crouch"],
				["", 2, "crouch+prone"],
				[keys, t, "crouch"]
			],
			3,
			clips.up,
		],
		[
			"prone to crouch to stand",
			[
				["", 10],
				["", 2, "prone"],
				["", 80, "crouch"],
				["", 2, "crouch+prone"],
				[keys, 50, "crouch"],
				[keys, t - 50],
			],
			3,
			clips.up,
		],
	]
	var end := roundi(_matrix.player.prone_tuning.exit_time * Engine.physics_ticks_per_second)
	# Standing up into a sprint speeds through the seam where the sprint blends in over the jog,
	# checked in full since gdstudio #1578 (before, a foot jumped 0.24 to 0.33 m in a tick there).
	# A crouch pressed in a sprint is a slide (`moves.md#slide`), not a stance change.
	if gait != "sprint":
		cases.append(
			["stand to crouch", [[keys, lead], [keys, t, "crouch"]], 1, PackedFloat32Array()]
		)
		cases.append(
			["crouch to stand", [[keys, lead, "crouch"], [keys, t]], 1, PackedFloat32Array()]
		)
	for case: Array in cases:
		var steps: Array = case[1].duplicate()
		# Leave the body standing for the next case.
		if _lies_after(steps):
			steps.append_array([["", 2, "prone"], ["", 90]])
		var samples := await _response.run(gait, 0.0, steps, 0.0, true)
		var label := "%s, %s, %s" % [case[0], "still" if keys == "" else "moving " + keys, weapon]
		_response.check_action(label, gait, samples, case[2], plain, false, case[3], t)
		# Getting up in place: its clip's end hands over to the stance under it with no pop. The
		# rifle's hold takes the trunk back from the clip there (its grip is the upper body), which
		# the momentum blend carries but for a few centimetres.
		if keys == "" and String(case[0]).begins_with("prone to"):
			var extra := MoveResponse.POSE_JUMP_PLUS if weapon == "rifle" else 0.0
			_response.check_hand_off(label, gait, samples, case[2], end, extra)


# True when `steps` leave the body lying (an odd number of prone presses).
static func _lies_after(steps: Array) -> bool:
	var presses := 0
	for step: Array in steps:
		if step.size() > 2 and String(step[2]).contains("prone"):
			presses += 1
	return presses % 2 == 1


# What the stance clips alone move a tick, read from a crouch at rest, where each starts on the
# drawn pose (checked, but with the rifle, whose hold carries the trunk: the clips start on the
# crouch idle's own trunk, 0.06 m from the rifle's): lying down (`down`) and getting up to the
# crouch (`up`), over `STANCE_TICKS`.
func _stance_clips(gait: String, checked := true) -> Dictionary:
	var t := MoveResponse.STANCE_TICKS
	var ref_steps: Array = [["", 60], ["", t, "prone"], ["", 2, "prone"], ["", t]]
	var ref := await _response.run("crouch", 0.0, ref_steps, 0.0, true)
	var down := MoveResponse.moves_from(ref, 1, t)
	var up := MoveResponse.moves_from(ref, 2, t)
	if checked:
		_response.check_clip_start("lying down from a crouch at rest", gait, down)
		_response.check_clip_start("getting up to a crouch", gait, up)
	return {"down": down, "up": up}


# The crouch's hand-off from `keys` held at `gait` (the bound of every stance change there): its
# `peak_move()` from the steady gait, or from standing still.
func _crouch_bound(gait: String, keys: String) -> float:
	var steps: Array = [[keys, 80], [keys, MoveResponse.POSE_TICKS + 4, "crouch"], [keys, 60]]
	var samples := await _response.run(gait, 0.0, steps, 0.0, true)
	return MoveResponse.peak_move(samples, 1)


func test_stance_changes_standing_still() -> void:
	var clips := await _stance_clips("jog")
	await _stance_changes("jog", "", await _crouch_bound("jog", ""), clips)
	_report()


func test_stance_changes_with_the_rifle_and_the_fists() -> void:
	_matrix.player.loadout.give(load("res://gameplay/weapon/rifle.tres") as WeaponDef, 30)
	var clips := await _stance_clips("jog", false)
	assert_str(String(_matrix.player.weapon.definition.resource_path)).ends_with("rifle.tres")
	await _stance_changes("jog", "", await _crouch_bound("jog", ""), clips, "rifle")
	_matrix.player.loadout.toggle_unarmed()
	clips = await _stance_clips("jog")
	await _stance_changes("jog", "", await _crouch_bound("jog", ""), clips, "fists")
	_report()


func test_stance_changes_at_a_walk() -> void:
	var clips := await _stance_clips("walk")
	await _stance_changes("walk", "W", await _crouch_bound("walk", "W"), clips)
	_report()


func test_stance_changes_at_a_jog() -> void:
	var clips := await _stance_clips("jog")
	await _stance_changes("jog", "W", await _crouch_bound("jog", "W"), clips)
	_report()


func test_stance_changes_at_a_sprint() -> void:
	var clips := await _stance_clips("sprint")
	# A crouch in a sprint slides: the jog's crouch bounds the sprint's stance changes.
	await _stance_changes("sprint", "W", await _crouch_bound("jog", "W"), clips)
	_report()


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
