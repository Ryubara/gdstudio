# The character in the sample map: the door, the coins, the platform and the stairs are meant
# for it.
extends GdUnitTestSuite

var _runner: GdUnitSceneRunner
var _scene: Node
var _player: Player


func before_test() -> void:
	_runner = scene_runner("res://main.tscn")
	_scene = _runner.scene()
	_player = _scene.get_node("Player")
	await InputSim.ticks(get_tree(), 10)


func after_test() -> void:
	InputSim.release_all()


func test_it_starts_on_the_dais_facing_into_the_map() -> void:
	assert_bool(_player.is_on_floor()).is_true()
	assert_float(_player.global_position.y).is_equal_approx(1.0, 0.05)
	assert_float(_player.global_position.length()).is_less(4.0)


func test_stepping_on_the_pressure_pad_opens_the_room_door() -> void:
	var door: Door = _scene.get_node("Level/Doors/MainDoor")
	assert_bool(door.is_open()).is_false()
	_player.teleport(Vector3(13.0, 0.1, -5.0))
	await InputSim.ticks(get_tree(), 80)
	assert_bool(door.is_open()).is_true()


func test_the_gate_door_opens_as_the_player_comes_near() -> void:
	var door: Door = _scene.get_node("Level/Doors/GateDoor")
	assert_bool(door.is_open()).is_false()
	_player.teleport(Vector3(-7.0, 0.1, 6.5))
	await InputSim.ticks(get_tree(), 80)
	assert_bool(door.is_open()).is_true()


func test_a_coin_of_the_map_is_collected_and_counted_on_screen() -> void:
	var coin: Pickup = _scene.get_node("Level/Pickups/JumpCoin1")
	_player.teleport(coin.global_position - Vector3(0.0, 0.7, 0.0))
	await InputSim.ticks(get_tree(), 8)
	assert_int(_player.count_of(&"coin")).is_equal(1)
	var counter: ItemCounter = _scene.get_node("Hud/Root/SafeArea/TopLeft/ItemCounter")
	assert_str(counter.label.text).is_equal("coin 1")


func test_the_shuttle_platform_carries_the_player_across_the_gap() -> void:
	var shuttle: MovingPlatform = _scene.get_node("Level/Platforms/Shuttle")
	_player.teleport(shuttle.global_position + Vector3(0.0, 0.6, 0.0))
	await InputSim.ticks(get_tree(), 8)
	var start_z := _player.global_position.z
	await InputSim.ticks(get_tree(), 150)
	assert_bool(_player.is_on_floor()).is_true()
	assert_float(_player.global_position.z - start_z).is_greater(2.0)


func test_it_walks_up_the_twelve_steps_to_the_tower() -> void:
	var stairs: ProtoBlock = _scene.get_node("Level/Landings/TowerStairs")
	# The stairs rise toward their own +X; stand at the low end and walk that way.
	var rise := stairs.global_basis.x.normalized()
	var low := stairs.global_position - rise * (stairs.size.x / 2.0 - 0.3)
	_player.teleport(Vector3(low.x, 0.0, low.z))
	await InputSim.ticks(get_tree(), 6)
	var heading := atan2(rise.x, rise.z)
	_player.facing = heading
	var camera_rig: PlayerCamera = _scene.get_node("PlayerCamera")
	camera_rig.yaw = rad_to_deg(atan2(-rise.x, -rise.z))
	await InputSim.ticks(get_tree(), 20)
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 150)
	assert_float(_player.global_position.y).is_greater(2.8)
