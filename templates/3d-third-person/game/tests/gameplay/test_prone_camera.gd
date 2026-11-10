# The camera with a lying player, in the template's main scene: it follows the lowered target,
# its pitch is drawn in to the prone look limits (so the lens stays off the ground), and it gets
# its whole range back when the player gets up.
extends GdUnitTestSuite

var _runner: GdUnitSceneRunner
var _scene: Node
var _player: Player
var _rig: PlayerCamera
var _camera: Camera3D


func before_test() -> void:
	_runner = scene_runner("res://main.tscn")
	_scene = _runner.scene()
	_player = _scene.get_node("PlayerRig/Player")
	_rig = _scene.get_node("PlayerRig/PlayerCamera")
	_camera = _scene.get_node("PlayerRig/Camera")
	await InputSim.ticks(get_tree(), 12)


func after_test() -> void:
	InputSim.release_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _tap_prone() -> void:
	InputSim.key(KEY_Z, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_Z, false)


func test_lying_down_draws_the_pitch_in_and_getting_up_gives_it_back() -> void:
	var prone := _player.prone_tuning
	assert_vector(_rig.pitch_limits()).is_equal(Vector2(_rig.min_pitch, _rig.max_pitch))
	await _tap_prone()
	await InputSim.ticks(get_tree(), 50)
	assert_bool(_player.prone).is_true()
	assert_vector(_rig.pitch_limits()).is_equal_approx(
		Vector2(-prone.look_up_limit, prone.look_down_limit), Vector2(0.01, 0.01)
	)
	# Looking up as far as the stick goes stops at the limit, and the lens is over the floor.
	_rig.orbit(Vector2(0.0, -180.0))
	await InputSim.ticks(get_tree(), 30)
	assert_float(_rig.pitch).is_equal_approx(-prone.look_up_limit, 0.01)
	var floor_y := _player.global_position.y
	assert_float(_camera.global_position.y).is_greater(floor_y + 0.15)
	# Looking down too.
	_rig.orbit(Vector2(0.0, 180.0))
	assert_float(_rig.pitch).is_equal_approx(prone.look_down_limit, 0.01)
	await _tap_prone()
	await InputSim.ticks(get_tree(), 80)
	assert_bool(_player.prone).is_false()
	_rig.orbit(Vector2(0.0, 180.0))
	assert_float(_rig.pitch).is_equal_approx(_rig.max_pitch, 0.01)


func test_the_camera_follows_the_lowered_target() -> void:
	var target := _player.get_node("%CameraTarget") as Node3D
	var standing := _camera.global_position.y
	await _tap_prone()
	await InputSim.ticks(get_tree(), 90)
	assert_float(target.position.y).is_equal_approx(_player.prone_tuning.camera_height, 0.001)
	assert_float(_camera.global_position.y).is_less(standing - 0.5)
