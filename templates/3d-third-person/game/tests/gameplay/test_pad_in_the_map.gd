# The prototype level's pressure pad and coins, in the real level with the real character. The
# pad's box also overlaps the floor and the landing it stands on, and the level's coins sit among
# its blocks (issue #848): none of them may act before the player does.
extends GdUnitTestSuite

const PAD_AT := Vector3(13.0, 0.1, -5.0)

var _scene: Node
var _player: Player
var _pad: TriggerZone
var _door: Door


func before_test() -> void:
	_scene = scene_runner("res://main.tscn").scene()
	_player = _scene.get_node("PlayerRig/Player")
	_pad = _scene.get_node("World/Level/Triggers/PressurePad")
	_door = _scene.get_node("World/Level/Doors/MainDoor")
	await InputSim.ticks(get_tree(), 10)


func after_test() -> void:
	InputSim.release_all()


func test_the_pad_never_hears_of_the_level_and_nobody_presses_it_at_the_start() -> void:
	await InputSim.ticks(get_tree(), 60)
	# The pad stands in the floor and the landing; its mask (Characters and Props, #924) leaves
	# them out, so the area does not even report them.
	assert_array(_pad.get_overlapping_bodies()).is_empty()
	assert_bool(_pad.is_active()).is_false()
	assert_bool(_door.is_open() or _door.is_moving()).is_false()


func test_the_player_on_the_pad_presses_it_and_leaving_releases_it() -> void:
	_player.teleport(PAD_AT)
	await InputSim.ticks(get_tree(), 20)
	assert_bool(_pad.is_active()).is_true()
	assert_int(_pad.occupant_count()).is_equal(1)
	_player.teleport(Vector3(-2.0, 0.1, 4.0))
	await InputSim.ticks(get_tree(), 20)
	assert_bool(_pad.is_active()).is_false()


func test_every_coin_of_the_map_is_there_until_the_player_comes() -> void:
	await InputSim.ticks(get_tree(), 60)
	for coin: Pickup in _scene.get_node("World/Level/Pickups").get_children():
		assert_bool(coin.is_available()).is_true()
