# The peek lean online (gdstudio #1400): a predicting client and the game server in one process
# (`OnlineRig`, lockstep loopback), with a second client watching. The first client's controller
# leans right (and, in the second case, left: the weapon goes to the left side and the server's
# shot start is mirrored with it, gdstudio #1435), aims and fires with the crosshair's ray from its
# leaning eye, as a player's input would. The client's lean, its eye and its shape match the
# server body's on every tick, its shots leave where the server's leave, as many of them, and the
# watching client's puppet of it leans with the server's lean (one byte in its entry) and moves its
# eye and shape with it. Standing up, the entry is its 12 bytes again.
extends GdUnitTestSuite

## Where the leaning client stands, on open ground, looking along -Z.
const SPOT := Vector3(-3.0, 0.3, -6.0)
const WATCHER := Vector3(-3.0, 0.3, -12.0)
const LEAN_FROM := 10
const AIM_FROM := 40
const FIRE_TICKS: Array[int] = [80, 120, 160]
const STAND_FROM := 220

var _rig: OnlineRig
var _client: NetClient
var _watcher: NetClient
## The side the client leans to: 1 right, -1 left.
var _side := 1


func before_test() -> void:
	_rig = auto_free(OnlineRig.new())
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_client = await _rig.join("Ada", 600)
	assert_object(_client).is_not_null()
	_watcher = await _rig.join("Bo", 600)
	assert_object(_watcher).is_not_null()
	_rig.server_body(_client).teleport(SPOT, PI)
	_client.player.teleport(SPOT, PI)
	_rig.server_body(_watcher).teleport(WATCHER, 0.0)
	_watcher.player.teleport(WATCHER, 0.0)
	await _rig.wait(30)
	_rig.controllers[0].ticks = 0
	_rig.controllers[0].plan = _plan


func after_test() -> void:
	_rig = null
	_client = null
	_watcher = null


func test_the_client_lean_and_its_shots_match_the_server(
	side: int, _test_parameters := [[1], [-1]]
) -> void:
	_side = side
	var server_body := _rig.server_body(_client)
	var client_shots: Array[Vector3] = []
	var server_shots: Array[Vector3] = []
	_client.player.weapon.fired.connect(
		func(shot: Projectile) -> void: client_shots.append(_start_of(shot))
	)
	server_body.weapon.fired.connect(
		func(shot: Projectile) -> void: server_shots.append(_start_of(shot))
	)
	# The lean and the eye's place on the body after each command, by the command's number, on
	# both sides: the client steps a command at once, the server a tick or two later.
	var mine: Dictionary[int, Vector4] = {}
	var theirs: Dictionary[int, Vector4] = {}
	var watch := func() -> bool:
		_note(mine, _client.player)
		_note(theirs, server_body)
		return _rig.controllers[0].ticks >= STAND_FROM - 10
	assert_bool(await _rig.until(watch, STAND_FROM + 120)).is_true()
	var worst := {"amount": 0.0, "eye": 0.0}
	var leaned := 0
	for seq in theirs:
		if not mine.has(seq):
			continue
		worst.amount = maxf(worst.amount, absf(mine[seq].w - theirs[seq].w))
		var eye_mine := Vector3(mine[seq].x, mine[seq].y, mine[seq].z)
		var eye_theirs := Vector3(theirs[seq].x, theirs[seq].y, theirs[seq].z)
		worst.eye = maxf(worst.eye, eye_mine.distance_to(eye_theirs))
		leaned += int(theirs[seq].w == float(side))
	prints("peek online: worst lean", worst.amount, "eye", worst.eye, "leaned", leaned)
	prints("peek online shots: client", client_shots, "server", server_shots)
	# The client predicts the lean the server steps, command for command.
	assert_float(worst.amount).is_less(0.0001)
	assert_float(worst.eye).is_less(0.005)
	assert_int(leaned).is_greater(100)
	# The shots: as many, each from beside the leaning eye on both sides. The client's leaves its
	# pistol's muzzle as the bend drew it (on a left lean across to the left eye), the server's (a
	# body with no model) from the weapon's `no_muzzle_offset` rolled with the lean and mirrored on
	# a left one: within a few centimetres of each other.
	assert_int(client_shots.size()).is_equal(FIRE_TICKS.size())
	assert_int(server_shots.size()).is_equal(client_shots.size())
	for index in client_shots.size():
		assert_vector(client_shots[index]).is_equal_approx(server_shots[index], Vector3.ONE * 0.1)
		assert_float((client_shots[index].x - SPOT.x) * side).is_greater(0.2)
	# The watching client's puppet leans as the server's body does.
	var puppet := _watcher.remote_players.puppet_at(_client.slot)
	assert_object(puppet).is_not_null()
	assert_float(puppet.peek_motion.amount).is_equal_approx(float(side), 1.0 / 127.0)
	assert_bool((puppet.get_node("PeekShape") as CollisionShape3D).disabled).is_false()
	var shift := _eye(puppet) - puppet.global_position
	assert_float(shift.x * side).is_greater(0.3)
	# The entry carries one more byte while leaning, and none once it stands up.
	var entry := NetServer.entry_of(_client.slot, server_body)
	assert_int(SnapshotCodec.player_size(entry)).is_equal(SnapshotCodec.PLAYER_SIZE + 2)
	(
		assert_bool(await _rig.until(func() -> bool: return puppet.peek_motion.amount == 0.0, 120))
		. is_true()
	)
	entry = NetServer.entry_of(_client.slot, server_body)
	assert_int(SnapshotCodec.player_size(entry)).is_equal(SnapshotCodec.PLAYER_SIZE)
	assert_bool((puppet.get_node("PeekShape") as CollisionShape3D).disabled).is_true()


# The lean and the eye's place on `body` (from its feet) after the command it stepped last.
func _note(into: Dictionary[int, Vector4], body: Character) -> void:
	var seq := body.last_command.seq
	if seq <= 0 or into.has(seq):
		return
	var eye := _eye(body) - body.global_position
	into[seq] = Vector4(eye.x, eye.y, eye.z, body.peek_motion.amount)


func _eye(body: Character) -> Vector3:
	return (body.get_node("CameraTarget") as Node3D).global_position


func _start_of(shot: Projectile) -> Vector3:
	return shot.global_position if shot != null else Vector3.INF


# Lean to `_side`, aim from `AIM_FROM`, fire on `FIRE_TICKS` along -Z from the leaning eye, stand
# up at `STAND_FROM`.
func _plan(tick: int) -> PlayerCommand:
	var command := PlayerCommand.new()
	var ahead := CommandCodec.direction_angles(Vector3.FORWARD)
	command.yaw = ahead.x
	var leaning := tick >= LEAN_FROM and tick < STAND_FROM
	command.lean_right = leaning and _side > 0
	command.lean_left = leaning and _side < 0
	if tick < AIM_FROM or tick >= STAND_FROM or _client == null:
		return command
	command.aim = true
	command.has_shot = true
	command.origin = _eye(_client.player)
	command.shot_yaw = ahead.x
	command.shot_pitch = ahead.y
	command.fire = FIRE_TICKS.has(tick)
	command.fire_pressed = command.fire
	return command
