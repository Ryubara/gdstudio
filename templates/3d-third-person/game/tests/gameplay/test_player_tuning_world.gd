# The rest of the tuning, live: the slopes and steps, pushing, the actions and the body (the
# ground, the jump and the air are in test_player_tuning_live.gd).
extends GdUnitTestSuite

const TICKS := 60
const TUNING := "res://gameplay/player/player_tuning.tres"
const PROP := "res://gameplay/physics_prop/physics_prop.tscn"

var _arena: PlayArena
var _player: Player
var _tuning: CharacterTuning


func before_test() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3(0.0, 0.0, 0.0))
	# A copy: the file is a cached resource that other suites read.
	_player.tuning = (load(TUNING) as CharacterTuning).duplicate()
	_tuning = _player.tuning
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()


func _ticks(count: int) -> void:
	await InputSim.ticks(get_tree(), count)


func _ticks_in(state: Player.State, limit: int) -> int:
	var count := 0
	while _player.state == state and count < limit:
		await get_tree().physics_frame
		count += 1
	return count


func test_max_slope_and_snap_length_reach_the_body() -> void:
	_tuning.max_slope = 30.0
	assert_float(_player.floor_max_angle).is_equal_approx(deg_to_rad(30.0), 0.0001)
	_tuning.snap_length = 0.6
	await _ticks(2)
	assert_float(_player.floor_snap_length).is_equal_approx(0.6, 0.0001)


func test_max_slope_changes_which_slope_it_can_climb() -> void:
	var ramp := _arena.add_block(Vector2(0.0, -6.0), Vector3(4.0, 0.4, 10.0), 0.0)
	ramp.rotation_degrees.x = 30.0
	_player.teleport(Vector3(0.0, 0.0, -4.0))
	await _ticks(4)
	_tuning.max_slope = 20.0
	InputSim.key(KEY_W, true)
	await _ticks(TICKS * 2)
	assert_float(_player.global_position.y).is_less(0.8)


func test_step_height_changes_which_edge_it_walks_up() -> void:
	_arena.add_block(Vector2(0.0, -7.0), Vector3(4.0, 0.6, 8.0), 0.6)
	InputSim.key(KEY_W, true)
	await _ticks(TICKS)
	assert_float(_player.global_position.y).is_less(0.05)
	_tuning.step_height = 0.7
	await _ticks(40)
	assert_float(_player.global_position.y).is_equal_approx(0.6, 0.05)


func _push_distance(at_x: float, weight: float) -> float:
	var crate := load(PROP).instantiate() as PhysicsProp
	crate.weight = weight
	crate.position = Vector3(at_x, 0.5, -1.2)
	_arena.add_child(crate)
	_player.teleport(Vector3(at_x, 0.0, 0.0))
	await _ticks(4)
	InputSim.key(KEY_W, true)
	await _ticks(TICKS)
	InputSim.key(KEY_W, false)
	return absf(crate.global_position.z + 1.2)


func test_push_strength_sets_how_hard_a_prop_is_pushed() -> void:
	_tuning.push_strength = 0.0
	var barely := await _push_distance(-8.0, 40.0)
	_tuning.push_strength = 1.0
	var moved := await _push_distance(8.0, 40.0)
	assert_float(moved).is_greater(barely + 1.0)


func test_push_mass_sets_which_props_count_as_light() -> void:
	_tuning.push_mass = 1.0
	var stubborn := await _push_distance(-8.0, 100.0)
	_tuning.push_mass = 100.0
	var pushed := await _push_distance(8.0, 100.0)
	assert_float(pushed).is_greater(stubborn * 2.0)


func test_interact_reach_and_time_change_what_it_can_use_and_how_long_it_stands() -> void:
	var door := load("res://gameplay/door/door.tscn").instantiate() as Door
	door.position = Vector3(0.0, 0.0, -2.4)
	_arena.add_child(door)
	await _ticks(4)
	assert_object(_player.interact()).is_null()
	_tuning.interact_reach = 3.0
	_tuning.interact_time = 0.2
	assert_object(_player.interact()).is_same(door)
	var short := await _ticks_in(Player.State.INTERACT, 120)
	assert_int(short).is_between(8, 20)


func test_hit_stun_and_knockback_set_how_long_and_how_far_a_hit_throws_it() -> void:
	var source := Node3D.new()
	auto_free(source)
	_arena.add_child(source)
	source.position = Vector3(0.0, 0.0, -1.0)
	_tuning.knockback_speed = 9.0
	_tuning.hit_stun_time = 0.15
	_player.hit(1.0, source)
	assert_float(Vector2(_player.velocity.x, _player.velocity.z).length()).is_equal_approx(
		9.0, 0.01
	)
	var stunned := await _ticks_in(Player.State.HIT, 120)
	assert_int(stunned).is_between(5, 14)


func test_land_clip_speed_and_land_time_set_the_landing() -> void:
	_tuning.land_clip_speed = 100.0
	_player.teleport(Vector3(0.0, 4.0, 0.0))
	var landed := false
	for _tick in TICKS:
		await get_tree().physics_frame
		landed = landed or _player.state == Player.State.LAND
	assert_bool(landed).is_false()
	_tuning.land_clip_speed = 0.0
	_tuning.land_time = 0.1
	_player.teleport(Vector3(0.0, 4.0, 0.0))
	var landing_ticks := 0
	for _tick in TICKS:
		await get_tree().physics_frame
		if _player.state == Player.State.LAND:
			landing_ticks += 1
	assert_int(landing_ticks).is_between(3, 9)


func test_stand_speed_decides_when_it_counts_as_walking() -> void:
	_tuning.stand_speed = 3.0
	InputSim.key(KEY_X, true)
	InputSim.key(KEY_W, true)
	await _ticks(40)
	assert_int(_player.state).is_equal(Player.State.IDLE)
	_tuning.stand_speed = 0.15
	await _ticks(3)
	assert_int(_player.state).is_equal(Player.State.WALK)


func test_radius_and_height_reshape_the_capsule_at_once() -> void:
	_tuning.radius = 0.5
	_tuning.height = 2.4
	var capsule := (_player.get_node("%Body") as CollisionShape3D).shape as CapsuleShape3D
	assert_float(capsule.radius).is_equal_approx(0.5, 0.0001)
	assert_float(capsule.height).is_equal_approx(2.4, 0.0001)
	var body := _player.get_node("%Body") as CollisionShape3D
	assert_float(body.position.y).is_equal_approx(1.2, 0.0001)


func test_two_players_do_not_share_a_capsule() -> void:
	var other := _arena.add_player(Vector3(5.0, 0.0, 0.0))
	other.tuning = other.tuning.duplicate()
	other.tuning.radius = 0.6
	var mine := (_player.get_node("%Body") as CollisionShape3D).shape as CapsuleShape3D
	assert_float(mine.radius).is_equal_approx(0.34, 0.001)


func test_fall_limit_sets_where_it_starts_again() -> void:
	var spawn := SpawnPoint.new()
	spawn.position = Vector3(4.0, 0.0, 4.0)
	_arena.add_child(spawn)
	_tuning.fall_limit = -2.0
	_player.teleport(Vector3(0.0, -3.0, 0.0))
	await _ticks(3)
	assert_vector(_player.global_position).is_equal_approx(
		Vector3(4.0, 0.0, 4.0), Vector3.ONE * 0.3
	)


func test_a_swapped_tuning_file_takes_over_at_once() -> void:
	var heavy := CharacterTuning.new()
	heavy.run_speed = 2.0
	_player.tuning = heavy
	InputSim.key(KEY_W, true)
	await _ticks(40)
	assert_float(_player.ground_speed()).is_equal_approx(2.0, 0.1)
