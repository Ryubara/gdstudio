# The numbers that were constants in the body's code until #901 (the stick's walk threshold and
# least share, the run margin, the step probe, the aim walk cap and shot threshold, the push
# numbers and the dead camera's rise), live: each is changed on a running character and its
# effect is read. Their defaults are pinned with the others in test_player_tuning_live.gd.
extends GdUnitTestSuite

const TICKS := 60
const TUNING := "res://gameplay/player/player_tuning.tres"
const PROP := "res://gameplay/physics_prop/physics_prop.tscn"

var _arena: PlayArena
var _player: Player
var _tuning: PlayerTuning
var _first_shot := -1
var _tick := 0


func before_test() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3(0.0, 0.0, 0.0))
	# A copy: the file is a cached resource that other suites read.
	_player.tuning = (load(TUNING) as PlayerTuning).duplicate()
	_tuning = _player.tuning
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()


func _ticks(count: int) -> void:
	await InputSim.ticks(get_tree(), count)


func test_walk_below_push_decides_which_push_walks() -> void:
	var walked: float = _player.call(&"_target_speed", 0.4)
	_tuning.walk_below_push = 0.3
	var ran: float = _player.call(&"_target_speed", 0.4)
	assert_float(walked).is_equal_approx(_tuning.walk_speed * 0.5, 0.0001)
	assert_float(ran).is_equal_approx(_tuning.run_speed * 0.4, 0.0001)


func test_least_walk_share_sets_the_pace_of_a_nudge() -> void:
	var nudged: float = _player.call(&"_target_speed", 0.2)
	_tuning.least_walk_share = 1.0
	var full: float = _player.call(&"_target_speed", 0.2)
	assert_float(nudged).is_equal_approx(_tuning.walk_speed * 0.5, 0.0001)
	assert_float(full).is_equal_approx(_tuning.walk_speed, 0.0001)


func test_aim_walk_cap_sets_the_fastest_aimed_walk() -> void:
	_player.aiming = true
	var capped: float = _player.call(&"_target_speed", 1.0)
	_tuning.aim_walk_cap = 1.0
	var slower: float = _player.call(&"_target_speed", 1.0)
	_player.aiming = false
	assert_float(capped).is_equal_approx(_tuning.walk_speed * 1.5 * _tuning.aim_move_scale, 0.0001)
	assert_float(slower).is_equal_approx(_tuning.walk_speed * _tuning.aim_move_scale, 0.0001)


func test_run_above_walk_decides_when_a_walk_is_a_run() -> void:
	_player.velocity = Vector3(_tuning.walk_speed + 0.2, 0.0, 0.0)
	var walking: Player.State = _player.call(&"_pick_state", true, Vector3.ZERO)
	_tuning.run_above_walk = 0.1
	var running: Player.State = _player.call(&"_pick_state", true, Vector3.ZERO)
	_player.velocity = Vector3.ZERO
	assert_int(walking).is_equal(Player.State.WALK)
	assert_int(running).is_equal(Player.State.RUN)


# A step 0.3 m high and 0.6 m deep with a wall behind it: the climb looks past the step's edge by
# the capsule's radius and the margin, so a long look meets the wall and the body stays below.
func _climbs_the_shallow_step(margin: float, at_x: float) -> float:
	_arena.add_block(Vector2(at_x, -1.3), Vector3(2.0, 0.3, 0.6), 0.3)
	_arena.add_block(Vector2(at_x, -2.1), Vector3(2.0, 3.0, 1.0), 3.0)
	_tuning.step_probe_margin = margin
	_player.teleport(Vector3(at_x, 0.0, 0.0), PI)
	await _ticks(4)
	InputSim.key(KEY_W, true)
	await _ticks(TICKS)
	InputSim.key(KEY_W, false)
	return _player.global_position.y


func test_step_probe_margin_sets_how_far_past_the_edge_the_climb_looks() -> void:
	var near := await _climbs_the_shallow_step(0.06, -8.0)
	var far := await _climbs_the_shallow_step(0.8, 8.0)
	assert_float(near).is_equal_approx(0.3, 0.05)
	assert_float(far).is_less(0.05)


# The tick of the first shot after aim and fire are pressed together from the hip. Methods and a
# plain loop, no lambdas: a lambda here left the suite's script in use at exit.
func _first_shot_tick() -> int:
	_first_shot = -1
	_player.weapon.fired.connect(_on_fired)
	CommandDriver.take(_player)
	var command := PlayerCommand.new()
	command.aim = true
	command.fire = true
	command.fire_pressed = true
	for tick in 20:
		_tick = tick
		await get_tree().physics_frame
		_player.step(command, CommandDriver.tick_seconds())
		command.clear_edges()
	_player.weapon.fired.disconnect(_on_fired)
	return _first_shot


func _on_fired(_shot: Node3D) -> void:
	if _first_shot < 0:
		_first_shot = _tick


func test_shot_aim_amount_sets_how_far_the_arm_is_up_before_a_shot() -> void:
	_tuning.shot_aim_amount = 0.0
	var at_once := await _first_shot_tick()
	assert_int(at_once).is_equal(0)
	# The arm goes down and the cooldown runs out on steps that ask for nothing.
	var idle := PlayerCommand.new()
	for _step in 60:
		await get_tree().physics_frame
		_player.step(idle, CommandDriver.tick_seconds())
	assert_float(_player.aim_amount).is_equal(0.0)
	_tuning.shot_aim_amount = 1.0
	var arm_up := await _first_shot_tick()
	assert_int(arm_up).is_greater(at_once + 4)


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


func test_push_boost_sets_how_hard_a_light_prop_is_pushed() -> void:
	_tuning.push_boost = 0.5
	var soft := await _push_distance(-8.0, 40.0)
	_tuning.push_boost = 3.0
	var hard := await _push_distance(8.0, 40.0)
	assert_float(hard).is_greater(soft + 0.5)


func test_push_least_share_sets_how_much_a_heavy_prop_moves() -> void:
	_tuning.push_least_share = 0.0
	var stuck := await _push_distance(-8.0, 400.0)
	_tuning.push_least_share = 1.0
	var moved := await _push_distance(8.0, 400.0)
	assert_float(moved).is_greater(stuck + 0.5)


# Walks into a prop with a `push_speed` (a slow push) and returns the body's push cap.
func _slow_push_cap(at_x: float) -> float:
	var crate := load(PROP).instantiate() as PhysicsProp
	crate.weight = 40.0
	crate.push_speed = 1.0
	crate.position = Vector3(at_x, 0.5, -1.2)
	_arena.add_child(crate)
	_player.teleport(Vector3(at_x, 0.0, 0.0))
	await _ticks(4)
	InputSim.key(KEY_W, true)
	await _ticks(TICKS)
	var cap: float = _player.get(&"_push_cap")
	InputSim.key(KEY_W, false)
	return cap


func test_push_contact_sets_how_much_faster_than_a_slow_prop_the_body_walks() -> void:
	var near := await _slow_push_cap(-8.0)
	_tuning.push_contact = 1.5
	var ahead := await _slow_push_cap(8.0)
	assert_float(near).is_equal_approx(1.15, 0.0001)
	assert_float(ahead).is_equal_approx(1.5, 0.0001)


func test_push_hold_sets_how_long_a_slow_push_lasts_after_the_last_touch() -> void:
	_tuning.push_hold = 1.0
	await _slow_push_cap(-8.0)
	_player.teleport(Vector3(0.0, 0.0, 10.0))
	await _ticks(30)
	var held: float = _player.get(&"_push_cap")
	_tuning.push_hold = 0.0
	await _slow_push_cap(8.0)
	_player.teleport(Vector3(0.0, 0.0, 10.0))
	await _ticks(3)
	var let_go: float = _player.get(&"_push_cap")
	assert_float(held).is_greater(0.0)
	assert_float(let_go).is_equal(0.0)


func _rise_above_hips() -> float:
	var target := _player.get_node(^"CameraTarget") as Node3D
	return target.global_position.y - _player.ragdoll_body.hips().y


func test_dead_camera_rise_sets_how_high_the_camera_looks_at_a_dead_body() -> void:
	_player.die()
	# Long enough for the body to lie still, so the hips do not move between the tick and the read.
	await _ticks(90)
	var low := _rise_above_hips()
	_tuning.dead_camera_rise = 1.0
	await _ticks(2)
	var high := _rise_above_hips()
	assert_float(low).is_equal_approx(0.25, 0.05)
	assert_float(high).is_equal_approx(1.0, 0.05)
