# The bot of `--bot`: it presses the actions and turns the camera, and the player's own
# `PlayerInput` makes the commands. A rig (body, camera, input) on a flat floor in a view of its
# own.
extends GdUnitTestSuite

const RIG := "res://ui/player_rig/player_rig.tscn"


# The other players a watching bot sees: one standing body in place of a puppet.
class StandIns:
	extends RemotePlayers

	var bodies: Array[Player] = []

	func slots() -> Array[int]:
		var out: Array[int] = []
		for index in bodies.size():
			out.append(index)
		return out

	func puppet_at(slot: int) -> Player:
		return bodies[slot] if slot < bodies.size() else null


var _arena: PlayArena
var _rig: PlayerRig


func _make() -> PlayerBot:
	var view := SubViewport.new()
	view.own_world_3d = true
	view.size = Vector2i(320, 180)
	add_child(auto_free(view))
	_arena = PlayArena.new()
	view.add_child(_arena)
	_rig = (load(RIG) as PackedScene).instantiate() as PlayerRig
	_rig.get_node("Player").start_at_spawn = false
	_arena.add_child(_rig)
	_rig.player.global_position = Vector3(0.0, 0.05, 0.0)
	var bot := PlayerBot.new()
	bot.player = _rig.player
	bot.camera_rig = _rig.camera_rig
	_arena.add_child(bot)
	return bot


# Runs `frames` physics frames and counts the commands that pressed fire and interact, and held aim.
func _run(frames: int) -> Dictionary:
	var seen := {"fire": 0, "interact": 0, "aim": 0}
	for _i in frames:
		await get_tree().physics_frame
		var command := _rig.player.last_command
		seen["fire"] += 1 if command.fire_pressed else 0
		seen["interact"] += 1 if command.interact_pressed else 0
		seen["aim"] += 1 if command.aim else 0
	return seen


func test_the_route_walks_to_each_point_presses_interact_and_fires_its_shots() -> void:
	var bot := _make()
	bot.route = PackedVector3Array([Vector3(4.0, 0.0, -4.0)])
	bot.door_side = Vector3(4.0, 1.2, -8.0)
	bot.door_wait = 0.2
	bot.stand_at = Vector3(0.0, 0.0, -2.0)
	bot.shots = 3
	var seen := await _run(600)
	assert_float(_rig.player.global_position.distance_to(Vector3(0.0, 0.0, -2.0))).is_less(1.0)
	assert_int(seen["interact"]).is_equal(1)
	assert_int(bot.fired).is_equal(3)
	assert_int(seen["fire"]).is_equal(3)
	assert_int(seen["aim"]).is_greater(10)
	# Done: it stands, and holds no key.
	assert_int(bot.stage).is_greater_equal(bot.route.size() + 5)
	assert_bool(Input.is_action_pressed(&"move_forward")).is_false()
	assert_bool(Input.is_action_pressed(&"aim")).is_false()


func test_the_watcher_turns_to_the_other_player_then_fires_at_it() -> void:
	var bot := _make()
	var others := StandIns.new()
	_arena.add_child(others)
	var target := _arena.add_player(Vector3(6.0, 0.0, 3.0))
	target.input_enabled = false
	others.bodies.append(target)
	bot.plan = PlayerBot.Plan.WATCH
	bot.remote_players = others
	bot.fire_after = 1.0
	var waiting := await _run(50)
	assert_int(waiting["fire"]).is_zero()
	# The crosshair's ray (through the middle of the screen, from the shifted lens) meets its chest.
	var camera := _rig.camera_rig.camera
	var centre := camera.get_viewport().get_visible_rect().size / 2.0
	var origin := camera.project_ray_origin(centre)
	var chest := target.global_position + Vector3.UP * PlayerBot.CHEST_HEIGHT
	var along := camera.project_ray_normal(centre)
	var miss := (chest - origin) - along * (chest - origin).dot(along)
	assert_float(miss.length()).is_less(0.3)
	var firing := await _run(120)
	assert_int(firing["fire"]).is_greater_equal(2)
	assert_int(firing["aim"]).is_greater(30)
	# Aimed down the crosshair's ray (the lens sits over the shoulder), so the shots hit.
	assert_float(target.health).is_less(target.max_health)


func test_a_hold_the_window_let_go_of_is_pressed_again() -> void:
	var bot := _make()
	bot.route = PackedVector3Array([Vector3(0.0, 0.0, -20.0)])
	await _run(20)
	# What the engine does to every pressed action when the window loses the focus.
	Input.action_release(&"move_forward")
	await _run(2)
	assert_bool(Input.is_action_pressed(&"move_forward")).is_true()


func test_a_dead_player_lets_go_of_every_key() -> void:
	var bot := _make()
	bot.route = PackedVector3Array([Vector3(0.0, 0.0, -20.0)])
	await _run(20)
	assert_bool(Input.is_action_pressed(&"move_forward")).is_true()
	_rig.player.die()
	await _run(2)
	assert_bool(Input.is_action_pressed(&"move_forward")).is_false()


func test_a_bot_that_leaves_lets_go_of_every_key() -> void:
	var bot := _make()
	bot.route = PackedVector3Array([Vector3(0.0, 0.0, -20.0)])
	await _run(20)
	bot.queue_free()
	await get_tree().process_frame
	assert_bool(Input.is_action_pressed(&"move_forward")).is_false()
