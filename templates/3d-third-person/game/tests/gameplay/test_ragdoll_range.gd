# How far a death may be a ragdoll (`ragdoll_range`), now that the ragdoll reads no camera (#901):
# the human's death past the range of its camera is still the death clip and inside it a ragdoll,
# a character nobody watches (no controller, as a server's) always gets its ragdoll, and
# `can_start(viewer)` weighs only the viewer it is given.
extends GdUnitTestSuite

const RANGE := 10.0

var _arena: PlayArena
var _player: Player
var _camera: Camera3D


func before_test() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_camera = Camera3D.new()
	_arena.add_child(_camera)
	_camera.current = true
	_player = _arena.add_player(Vector3(0.0, 0.0, 0.0))
	_player.ragdoll_body.ragdoll_range = RANGE
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	if _player != null and is_instance_valid(_player) and _player.is_dead():
		_player.revive()
	InputSim.release_all()


func _put_camera(distance: float) -> void:
	_camera.global_position = Vector3(0.0, 1.0, distance)


func test_the_human_dies_by_clip_past_the_range_of_its_camera() -> void:
	_put_camera(RANGE * 3.0)
	_player.die()
	assert_bool(_player.died_by_clip).is_true()
	assert_bool(_player.ragdoll_body.is_limp()).is_false()


func test_the_human_goes_limp_inside_the_range_of_its_camera() -> void:
	_put_camera(RANGE * 0.5)
	_player.die()
	assert_bool(_player.died_by_clip).is_false()
	assert_bool(_player.ragdoll_body.is_limp()).is_true()


func test_a_character_nobody_watches_goes_limp_whatever_the_camera() -> void:
	_put_camera(RANGE * 3.0)
	CommandDriver.take(_player)
	await InputSim.ticks(get_tree(), 1)
	_player.die()
	assert_bool(_player.died_by_clip).is_false()
	assert_bool(_player.ragdoll_body.is_limp()).is_true()


func test_can_start_weighs_only_the_viewer_it_is_given() -> void:
	var ragdoll := _player.ragdoll_body
	var hips := ragdoll.hips()
	_put_camera(RANGE * 3.0)
	assert_bool(ragdoll.call(&"can_start", hips + Vector3.BACK * RANGE * 2.0)).is_false()
	assert_bool(ragdoll.call(&"can_start", hips + Vector3.BACK * RANGE * 0.5)).is_true()
	assert_bool(ragdoll.call(&"can_start", Vector3.INF)).is_true()
	ragdoll.ragdoll_range = 0.0
	assert_bool(ragdoll.call(&"can_start", hips + Vector3.BACK * RANGE * 2.0)).is_true()


func test_the_player_input_names_its_camera_as_the_viewer() -> void:
	_put_camera(7.0)
	var viewer: Vector3 = _player.controller.viewer_position()
	assert_vector(viewer).is_equal_approx(_camera.global_position, Vector3.ONE * 0.0001)
	_camera.current = false
	_camera.queue_free()
	await InputSim.ticks(get_tree(), 1)
	assert_bool(_player.controller.viewer_position().is_finite()).is_false()
