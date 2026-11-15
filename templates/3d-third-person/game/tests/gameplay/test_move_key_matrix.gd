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
extends GdUnitTestSuite

var _arena: PlayArena
var _matrix: MoveKeyMatrix


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
