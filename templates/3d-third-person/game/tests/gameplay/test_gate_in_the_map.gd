# The prototype level's gate door, which opens by itself when the character comes near. The
# sensor around it also overlaps the gate's posts, the low wall, the floor and the door's own body
# (issue #845), so these tests run in the real level with the real character.
extends GdUnitTestSuite

const NEAR := Vector3(-7.0, 0.1, 6.5)
# Within the interact reach (1.6 m) of the gate, which opens from 3 m.
const AT_THE_GATE := Vector3(-7.0, 0.1, 8.3)
const FAR := Vector3(-7.0, 0.1, 0.0)

var _runner: GdUnitSceneRunner
var _scene: Node
var _player: Player
var _door: Door


func before_test() -> void:
	_runner = scene_runner("res://main.tscn")
	_scene = _runner.scene()
	_player = _scene.get_node("PlayerRig/Player")
	_door = _scene.get_node("World/Level/Doors/GateDoor")
	_door.close_after = 1.0
	await InputSim.ticks(get_tree(), 10)


func after_test() -> void:
	InputSim.release_all()


func test_the_gate_starts_closed_and_stays_closed_with_nobody_near() -> void:
	assert_bool(_door.is_open()).is_false()
	await InputSim.ticks(get_tree(), 90)
	assert_float(_door.openness()).is_equal(0.0)
	assert_bool(_door.is_moving()).is_false()


func test_the_gate_opens_as_the_player_comes_near_and_closes_after_they_leave() -> void:
	_player.teleport(NEAR, 0.0)
	await InputSim.ticks(get_tree(), 80)
	assert_bool(_door.is_open()).is_true()
	await InputSim.ticks(get_tree(), 90)
	assert_bool(_door.is_open()).is_true()
	_player.teleport(FAR)
	await InputSim.ticks(get_tree(), 150)
	assert_float(_door.openness()).is_equal(0.0)


func test_the_interact_button_closes_the_gate_and_it_stays_shut_until_you_return() -> void:
	_player.teleport(AT_THE_GATE, 0.0)
	await InputSim.ticks(get_tree(), 80)
	assert_bool(_door.is_open()).is_true()
	InputSim.key(KEY_F, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_F, false)
	await InputSim.ticks(get_tree(), 90)
	assert_float(_door.openness()).is_equal(0.0)
	assert_bool(_door.is_moving()).is_false()
	_player.teleport(FAR)
	await InputSim.ticks(get_tree(), 10)
	_player.teleport(AT_THE_GATE, 0.0)
	await InputSim.ticks(get_tree(), 80)
	assert_bool(_door.is_open()).is_true()
