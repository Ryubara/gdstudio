# A predicting client and the game server stop a body at the same place (gdstudio #1415): the stop
# decelerations of `CharacterTuning` are a function of the body's speed alone, so the client's
# own step and the server's, given the same commands, slow a sprint over the sprint stop's ground
# and end within 0.2 mm of each other.
extends GdUnitTestSuite

## Ticks of sprinting before the stick is let go, and ticks after it to come to rest.
const SPRINT_TICKS := 80
const REST_TICKS := 180
## Where the body sprints: from its spawn point towards open ground in the prototype map.
const HEADING := Vector3(-1.0, 0.0, -0.3)
## The least ground a sprint's stop covers (the sprint stop clip's travel is 4.82 m).
const LEAST_STOP := 4.4

var _rig: OnlineRig
var _client: NetClient
var _let_go := Vector3.INF
var _let_go_speed := 0.0


func before_test() -> void:
	_rig = auto_free(OnlineRig.new())
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_let_go = Vector3.INF


func test_a_sprint_stop_ends_where_the_server_body_ends() -> void:
	_client = await _rig.join("Ada")
	assert_object(_client).is_not_null()
	_rig.controllers[0].plan = _plan
	await _rig.wait(SPRINT_TICKS + REST_TICKS + 60)
	var body := _client.player
	var server_body := _rig.server_body(_client)
	var gap := body.global_position.distance_to(server_body.global_position)
	var stop := Vector2(body.global_position.x - _let_go.x, body.global_position.z - _let_go.z)
	prints(
		"sprint stop online: from %.2f m/s at %s," % [_let_go_speed, _let_go],
		"%.3f m to %s, gap %.6f m" % [stop.length(), body.global_position, gap]
	)
	(
		assert_float(gap)
		. override_failure_message(
			"client %s, server %s" % [body.global_position, server_body.global_position]
		)
		. is_less(0.0002)
	)
	assert_float(body.ground_speed()).is_less(0.01)
	assert_float(stop.length()).is_greater(LEAST_STOP)


func _plan(tick: int) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.yaw = _client.player.view_yaw
	if tick < SPRINT_TICKS:
		command.set_from_world(HEADING, HEADING)
		command.sprint = true
	elif _let_go == Vector3.INF:
		_let_go = _client.player.global_position
		_let_go_speed = _client.player.ground_speed()
	return command
