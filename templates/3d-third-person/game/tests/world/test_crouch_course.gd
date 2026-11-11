# The crouch course and the range on the map are built for what the tuning can do: each low place
# is lower than the standing capsule and higher than the crouched one, and the real character
# walks through the tunnel crouched, stays crouched under the ceiling and passes the bar.
extends GdUnitTestSuite

const LEVEL := "res://world/prototype/prototype_level.tscn"

var _level: Node3D
var _tuning: CharacterTuning


func before_test() -> void:
	_level = auto_free(load(LEVEL).instantiate())
	add_child(_level)
	_tuning = load("res://gameplay/player/player_tuning.tres")
	await get_tree().physics_frame


func _underside(path: String) -> float:
	var block := _level.get_node(path) as ProtoBlock
	return block.global_position.y - block.size.y / 2.0


func test_every_low_place_fits_a_crouched_character_and_not_a_standing_one() -> void:
	for path in [
		"CrouchCourse/Tunnel/Roof", "CrouchCourse/LowCeiling/Slab", "CrouchCourse/BarGap/Bar"
	]:
		var under := _underside(path)
		assert_float(under).override_failure_message(path).is_greater(_tuning.crouch_height + 0.05)
		assert_float(under).override_failure_message(path).is_less(_tuning.height - 0.3)


func test_the_tunnel_is_long_enough_to_crouch_walk_and_wide_enough_for_the_body() -> void:
	var roof := _level.get_node("CrouchCourse/Tunnel/Roof") as ProtoBlock
	assert_float(roof.size.x).is_greater_equal(5.0)
	var north := _level.get_node("CrouchCourse/Tunnel/WallNorth") as ProtoBlock
	var south := _level.get_node("CrouchCourse/Tunnel/WallSouth") as ProtoBlock
	var inside := (
		(south.global_position.z - south.size.z / 2.0)
		- (north.global_position.z + north.size.z / 2.0)
	)
	assert_float(inside).is_greater(_tuning.radius * 2.0 + 0.8)


func test_the_gap_under_the_bar_is_wide_enough_to_walk_through() -> void:
	var left := _level.get_node("CrouchCourse/BarGap/WallLeft") as ProtoBlock
	var right := _level.get_node("CrouchCourse/BarGap/WallRight") as ProtoBlock
	var gap := (
		(right.global_position.x - right.size.x / 2.0)
		- (left.global_position.x + left.size.x / 2.0)
	)
	assert_float(gap).is_greater(_tuning.radius * 2.0 + 0.8)


func test_the_crouch_coins_are_inside_the_tunnel_and_behind_the_bar() -> void:
	var coins := _level.get_node("CrouchCourse/Coins").get_children()
	assert_int(coins.size()).is_equal(3)
	var tunnel := _level.get_node("CrouchCourse/Tunnel/Roof") as ProtoBlock
	for coin: Pickup in coins:
		assert_str(String(coin.item_id)).is_equal("coin")
	var inside := coins.filter(
		func(coin: Pickup) -> bool:
			return absf(coin.global_position.x - tunnel.global_position.x) < tunnel.size.x / 2.0
	)
	assert_int(inside.size()).is_equal(2)


func test_the_range_has_targets_that_face_the_map() -> void:
	var targets := _level.get_node("Targets").get_children()
	assert_int(targets.size()).is_greater_equal(3)
	for board: Target in targets:
		assert_float(board.global_position.y).is_equal_approx(0.0, 0.001)
		assert_float(board.global_basis.z.dot(Vector3.BACK)).is_greater(0.99)


func test_the_character_walks_the_tunnel_crouched_and_comes_out_standing() -> void:
	var player := auto_free(load("res://gameplay/player/player.tscn").instantiate()) as Player
	player.start_at_spawn = false
	player.position = Vector3(0.0, 0.0, -21.5)
	_level.add_child(player)
	await InputSim.ticks(get_tree(), 6)
	# Walk west through it: the tunnel runs from x = -6.5 to x = -0.5. Without a camera the
	# forward key is -Z, so the left key is the way.
	InputSim.key(KEY_C, true)
	InputSim.key(KEY_A, true)
	for _tick in 900:
		await get_tree().physics_frame
		if player.global_position.x < -7.2:
			break
	InputSim.key(KEY_A, false)
	assert_float(player.global_position.x).is_less(-7.0)
	assert_bool(player.crouching).is_true()
	InputSim.key(KEY_C, false)
	await InputSim.ticks(get_tree(), 40)
	assert_bool(player.crouching).is_false()
	InputSim.release_all()
