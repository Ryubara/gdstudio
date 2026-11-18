# Speeding up into a sprint on the real player through its input actions (gdstudio #1578), measured
# as `test_move_key_matrix.gd`'s response cases are (`MoveResponse`): every drawn update, each tick
# its own frame. Its own suite: the matrix holds as many cases as a suite may.
extends GdUnitTestSuite

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


# Speeding up into a sprint from a steady jog and from a crouch walk (crouch let go as sprint is
# pressed), the sprint press at several places in the stride (gdstudio #1578): no drawn bone moves
# further in a tick than the steady jog's largest allows (`MoveResponse.POSE_JUMP_SHARE` and
# `POSE_JUMP_PLUS`). Where the jog alone (to 5.2 m/s) meets the sprint alone (from 5.2) the blend
# had no speeds between, the body crossed it in one tick and a foot moved 0.16 to 0.33 m there
# (0.17 to 0.25 from the crouch walk); the ground blend now takes `gait_change_time` over it.
func test_speeding_up_into_a_sprint() -> void:
	var jog: Array = [["W", 80], ["W", MoveResponse.POSE_TICKS + 4]]
	var plain := MoveResponse.peak_move(await _response.run("jog", 0.0, jog, 0.0, true), 1)
	for lead: int in [80, 83, 86, 89, 92, 95, 98, 101]:
		for from: String in ["jog", "crouch walk"]:
			var held := "crouch" if from == "crouch walk" else ""
			var steps: Array = [
				["W", lead, held], ["W", MoveResponse.POSE_TICKS + 4, "sprint"], ["", 60]
			]
			var samples := await _response.run("jog", 0.0, steps, 0.0, true)
			var label := "%s to sprint, pressed at tick %d" % [from, lead]
			_response.check_action(label, "jog", samples, 1, plain, false)
	_report()


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
