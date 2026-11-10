# The real character in the real map, driven as a server will drive it: its input is off, it has
# no controller, and commands alone walk it to the gate, use the gate and stand it on the pressure
# pad. No input action is pressed at any point.
extends GdUnitTestSuite

const PAD_AT := Vector3(13.0, 0.1, -5.0)
const NEAR_THE_GATE := Vector3(-7.0, 0.1, 5.0)

var _scene: Node
var _player: Player
var _players: Array[Player] = []


func before_test() -> void:
	InputSim.release_all()
	_scene = scene_runner("res://main.tscn").scene()
	_player = _scene.get_node("PlayerRig/Player")
	_player.input_enabled = false
	CommandDriver.take(_player)
	_players = [_player]
	await InputSim.ticks(get_tree(), 10)


func after_test() -> void:
	for action: StringName in InputMap.get_actions():
		assert_bool(Input.is_action_pressed(action)).is_false()


func _run(command: PlayerCommand, count: int) -> void:
	await CommandDriver.run(get_tree(), _players, command, count)


func test_it_has_no_controller_and_does_not_step_itself() -> void:
	assert_object(_player.controller).is_null()
	assert_object(_player.get_node_or_null("PlayerInput")).is_null()
	assert_bool(_player.is_physics_processing()).is_false()
	var spot := _player.global_position
	# Nothing steps it: it stays where it is, whatever is held.
	Input.action_press(&"move_forward")
	await InputSim.ticks(get_tree(), 20)
	Input.action_release(&"move_forward")
	assert_vector(_player.global_position).is_equal(spot)


func test_commands_walk_it_to_the_gate_and_use_it() -> void:
	var gate: Door = _scene.get_node("World/Level/Doors/GateDoor")
	gate.close_after = 1.0
	_player.teleport(NEAR_THE_GATE, 0.0)
	await _run(PlayerCommand.new(), 10)
	assert_bool(gate.is_open()).is_false()
	# The gate opens by itself for a character that walks up to it (3 m), +Z from here.
	var toward := CommandDriver.walking(Vector3.BACK)
	await _run(toward, 50)
	await _run(PlayerCommand.new(), 80)
	assert_float(_player.global_position.z).is_greater(7.0)
	assert_bool(gate.is_open()).is_true()
	# One press of interact in one command shuts it.
	var uses: Array[int] = [0]
	_player.interacted.connect(func(_target: Node3D) -> void: uses[0] += 1)
	var use := PlayerCommand.new()
	use.interact_pressed = true
	await _run(use, 90)
	assert_int(uses[0]).is_equal(1)
	assert_float(gate.openness()).is_equal(0.0)


func test_commands_walk_it_onto_the_pad_and_the_door_answers() -> void:
	var pad: TriggerZone = _scene.get_node("World/Level/Triggers/PressurePad")
	var door: Door = _scene.get_node("World/Level/Doors/MainDoor")
	_player.teleport(PAD_AT + Vector3(0.0, 0.0, 2.5), PI)
	await _run(PlayerCommand.new(), 20)
	assert_bool(pad.is_active()).is_false()
	await _run(CommandDriver.walking(Vector3.FORWARD), 45)
	await _run(PlayerCommand.new(), 30)
	assert_float(_player.global_position.distance_to(PAD_AT)).is_less(1.2)
	assert_bool(pad.is_active()).is_true()
	assert_bool(door.is_open() or door.is_moving()).is_true()
