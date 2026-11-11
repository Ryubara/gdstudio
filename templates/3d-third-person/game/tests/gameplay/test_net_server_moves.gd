# The moves that landed after the server, stepped by the server from a client's commands over a
# real socket: crouch pressed at a sprint slides the server's body and every TICK says `SLIDE`; a
# jump at a wall that carries a `Vaultable` vaults it (`VAULT` in the TICKs, the body past the
# wall); the weapon presses of protocol version 3 (flag bits 11 to 14, #887) put the pistol away,
# bring it back, and reload it after a shot. The client is never struck for any of them.
extends GdUnitTestSuite

## Where the vault wall's near face is, ahead of slot 0's spawn point (along -Z).
const WALL_FACE_Z := 7.0
const WALL_HEIGHT := 0.9
const WALL_DEPTH := 0.4

var _rig: NetServerRig
var _client: HandClient
var _body: Character
var _states: Array[Character.State] = []
var _sent_states: Array[int] = []


func before_test() -> void:
	_rig = auto_free(NetServerRig.new())
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_client = await _rig.join("Ada")
	assert_object(_client).is_not_null()
	_body = _rig.server.body_at(0)
	_states = []
	_sent_states = []
	_body.state_changed.connect(func(state: Character.State) -> void: _states.append(state))


# Sends one command a frame for `frames` frames (`make` builds each, given the frame), keeping the
# states the client read for slot 0; stops early when `done` holds.
func _drive(make: Callable, frames: int, done := Callable()) -> void:
	for frame in frames:
		_client.send_command(make.call(frame))
		_rig.pump()
		var tick := _client.last_tick()
		if tick != null and not tick.players.is_empty():
			_sent_states.append(tick.players[0].state)
		if done.is_valid() and done.call():
			return
		await get_tree().physics_frame


func _assert_never_struck() -> void:
	var peer := _rig.server.peer_at(0)
	assert_bool(_client.closed).is_false()
	assert_int(peer.limits.drops.total()).is_equal(0)
	assert_int(_rig.lines_of("kicked").size()).is_equal(0)


func test_crouch_at_a_sprint_slides_and_every_client_sees_it() -> void:
	var sprint := func(frame: int) -> PlayerCommand:
		var command := PlayerCommand.new()
		command.move = Vector2(0.0, 1.0)
		command.sprint = true
		# Crouch is the toggle's result: on from the 50th frame, at full sprint speed.
		command.crouch = frame >= 50
		return command
	await _drive(sprint, 110)
	assert_array(_states).contains([Character.State.SLIDE])
	assert_array(_sent_states).contains([Character.State.SLIDE])
	_assert_never_struck()


func test_a_jump_at_a_vaultable_wall_vaults_it_on_the_server() -> void:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, WALL_HEIGHT, WALL_DEPTH)
	shape.shape = box
	wall.add_child(shape)
	wall.add_child(Vaultable.new())
	var spawn := NetServerRig.SPAWNS[0]
	wall.position = Vector3(spawn.x, WALL_HEIGHT / 2.0, WALL_FACE_Z - WALL_DEPTH / 2.0)
	_rig.add_child(wall)
	var far_face := WALL_FACE_Z - WALL_DEPTH
	var pressed := [false]
	var run := func(_frame: int) -> PlayerCommand:
		var command := PlayerCommand.new()
		command.move = Vector2(0.0, 1.0)
		# Jump pressed once, 0.9 m from the face, as the character's own vault test does.
		var gap := _body.global_position.z - WALL_FACE_Z - _body.tuning.radius
		if not pressed[0] and gap <= 0.9:
			pressed[0] = true
			command.jump = true
			command.jump_pressed = true
		return command
	var past := func() -> bool:
		return _body.global_position.z < far_face - 0.5 and _body.is_on_floor()
	await _drive(run, 240, past)
	assert_bool(pressed[0]).is_true()
	assert_array(_states).contains([Character.State.VAULT])
	assert_float(_body.global_position.z).is_less(far_face)
	# A few more TICKs so the client has read the vault too.
	await _drive(func(_frame: int) -> PlayerCommand: return PlayerCommand.new(), 10)
	assert_array(_sent_states).contains([Character.State.VAULT])
	_assert_never_struck()


func test_the_weapon_presses_switch_and_reload_the_servers_body() -> void:
	var loadout := _body.loadout
	var weapon := _body.weapon
	assert_str(weapon.definition.display_name).is_equal("Pistol")
	var full: int = weapon.ammo
	var idle := func(_frame: int) -> PlayerCommand: return PlayerCommand.new()
	var press := func(field: StringName) -> Callable:
		return func(frame: int) -> PlayerCommand:
			var command := PlayerCommand.new()
			command.set(field, frame == 0)
			return command
	# Bit 14: the empty hands; the switch takes its time, then the fists are held.
	await _drive(press.call(&"unarmed_pressed"), 60)
	assert_int(loadout.held_slot()).is_equal(WeaponLoadout.UNARMED)
	assert_str(weapon.definition.display_name).is_equal("Fists")
	# Bit 12: the next weapon, the pistol again, with its magazine.
	await _drive(press.call(&"next_weapon_pressed"), 60)
	assert_int(loadout.held_slot()).is_equal(0)
	assert_int(weapon.ammo).is_equal(full)
	# One shot (fire held until the round leaves), then bit 11: a reload that fills it again.
	var fire := func(_frame: int) -> PlayerCommand:
		var command := PlayerCommand.new()
		command.fire = true
		command.fire_pressed = _frame == 0
		return command
	await _drive(fire, 30, func() -> bool: return weapon.ammo < full)
	assert_int(weapon.ammo).is_equal(full - 1)
	await _drive(idle, 30)
	await _drive(press.call(&"reload_pressed"), 2)
	assert_bool(weapon.is_reloading()).is_true()
	await _drive(idle, 180, func() -> bool: return not weapon.is_reloading())
	assert_int(weapon.ammo).is_equal(full)
	_assert_never_struck()
