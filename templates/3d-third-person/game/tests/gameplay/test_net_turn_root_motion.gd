# A sprint reversal online (gdstudio #1442): the predicting client and the game server both move
# the body by the reversal clip's root (`CharacterTurnMotion`), from the same commands and the same
# record, so the client's body ends where the server's does with no correction.
extends GdUnitTestSuite

## Where the run goes in `world/prototype/prototype_level.tscn`: off the dais to the first point,
## a stand, then a sprint toward the second, reversed back toward the first after
## `REVERSE_AFTER` ticks of it.
const FIRST := Vector3(2.0, 0.0, 9.0)
const SECOND := Vector3(-6.0, 0.0, 6.0)
const REVERSE_AFTER := 40
## Ticks the body stands at the first point before it sprints.
const STAND_TICKS := 30
const TICKS := 360

var _rig: OnlineRig
var _client: NetClient
var _phase := 0
var _sprinted := 0


func before_test() -> void:
	_rig = auto_free(OnlineRig.new())
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_phase = 0
	_sprinted = 0


func test_a_sprint_reversal_ends_where_the_server_body_ends() -> void:
	_client = await _rig.join("Ada")
	assert_object(_client).is_not_null()
	_rig.controllers[0].plan = _run
	await _rig.wait(TICKS + 90)
	var body := _client.player
	var server_body := _rig.server_body(_client)
	var gap := body.global_position.distance_to(server_body.global_position)
	var reconciler := _client.reconciler
	prints(
		"turn online: gap %.6f m," % gap,
		"server clip",
		server_body.turn_motion.clip,
		"corrections",
		reconciler.corrections,
		"worst error %.4f m" % reconciler.worst_error
	)
	assert_str(String(server_body.turn_motion.clip)).starts_with("gds/Sprint_Turn_180_")
	assert_str(String(body.turn_motion.clip)).is_equal(String(server_body.turn_motion.clip))
	assert_float(gap).is_less(0.0002)
	assert_int(reconciler.lost).is_equal(0)
	assert_float(reconciler.worst_error).is_less(Reconciler.DEAD_ZONE)


func _run(tick: int) -> PlayerCommand:
	var command := PlayerCommand.new()
	var at := _client.player.global_position
	command.yaw = _client.player.view_yaw
	if tick >= TICKS:
		return command
	# 0: to the first point; 1: stand there (a cut from a jog would be a pivot); 2: sprint toward
	# the second; 3: back toward the first.
	var target := SECOND if _phase == 2 else FIRST
	var way := Vector3(target.x - at.x, 0.0, target.z - at.z)
	if _phase == 0 and way.length() < 0.5:
		_phase = 1
	elif _phase == 1:
		_sprinted += 1
		if _sprinted > STAND_TICKS:
			_phase = 2
			_sprinted = 0
		return command
	elif _phase == 2:
		_sprinted += 1
		if _sprinted > REVERSE_AFTER:
			_phase = 3
	if _phase == 3 and way.length() < 0.5:
		return command
	command.set_from_world(way, way)
	command.sprint = _phase >= 2
	return command
