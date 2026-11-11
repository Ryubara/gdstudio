# The server's rules for shots (gdstudio #906), over a real socket with clients driven by hand: a
# shot from 50 m off the body, a press during the cooldown and a shot block that is not finite are
# refused (a REJECTED event to the shooter alone) and fire nothing; a shot that leaves is a SHOT to
# the others and its hit a HIT to everyone; a death is a 9-byte DIED with no bone and the body gets
# up where the server says; eight players firing four shots a second add less than 1 KB/s down a
# client. Below them, the parts: a cosmetic projectile and a cosmetic ray change nothing, and one
# seed gives one pellet whatever was fired before.
extends GdUnitTestSuite

## Where the hand-driven shooters aim: the floor this far ahead, so every shot is a HIT.
const AIM_AHEAD := 3.0
## Ticks of aim held before a press (the arm comes up in `aim_pose_time`).
const AIM_TICKS := 20

var _rig: NetServerRig


func after_test() -> void:
	_rig = null


func test_a_shot_from_far_off_the_body_is_rejected_and_fires_nothing() -> void:
	_rig = auto_free(NetServerRig.new())
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	var ada := await _rig.join("Ada")
	var bo := await _rig.join("Bo")
	var body := _rig.server.body_at(0)
	var ammo: int = body.weapon.ammo
	await _aim(ada, body, AIM_TICKS)
	var hostile := _shot_at(body, _floor_ahead(body), true)
	hostile.origin += Vector3(50.0, 0.0, 0.0)
	ada.send_command(hostile)
	await _aim(ada, body, 30)
	assert_int(_rejections(ada, ServerCombat.Reason.ORIGIN)).is_equal(1)
	assert_int(body.weapon.ammo).is_equal(ammo)
	assert_int(_rig.server.combat.shots).is_equal(0)
	assert_array(bo.heard(NetEvent.Kind.SHOT)).is_empty()
	assert_array(bo.heard(NetEvent.Kind.REJECTED)).is_empty()
	# The same press from the eye fires: a SHOT to Bo (never to Ada), a HIT to both.
	ada.send_command(_shot_at(body, _floor_ahead(body), true))
	var heard_hit := func() -> bool:
		return (
			not bo.heard(NetEvent.Kind.HIT).is_empty()
			and not ada.heard(NetEvent.Kind.HIT).is_empty()
		)
	assert_bool(await _rig.until(heard_hit, 90)).is_true()
	assert_int(body.weapon.ammo).is_equal(ammo - 1)
	assert_int(bo.heard(NetEvent.Kind.SHOT).size()).is_equal(1)
	assert_array(ada.heard(NetEvent.Kind.SHOT)).is_empty()
	var shot: NetEvent = bo.heard(NetEvent.Kind.SHOT)[0]
	assert_int(shot.slot).is_equal(0)
	assert_int(shot.amount).is_equal(body.loadout.held_slot() + 1)
	var hit: NetEvent = bo.heard(NetEvent.Kind.HIT)[0]
	assert_int(hit.code).is_equal(NetHits.Kind.WORLD)
	assert_int(hit.id).is_equal(NetEvent.NO_ID)
	assert_float(hit.point.y).is_equal_approx(0.0, 0.02)


func test_a_press_during_the_cooldown_is_rejected() -> void:
	_rig = auto_free(NetServerRig.new())
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	var ada := await _rig.join("Ada")
	var bo := await _rig.join("Bo")
	var body := _rig.server.body_at(0)
	await _aim(ada, body, AIM_TICKS)
	ada.send_command(_shot_at(body, _floor_ahead(body), true))
	await _aim(ada, body, 2)
	ada.send_command(_shot_at(body, _floor_ahead(body), true))
	await _aim(ada, body, 30)
	assert_int(_rejections(ada, ServerCombat.Reason.COOLDOWN)).is_equal(1)
	assert_int(_rig.server.combat.shots).is_equal(1)
	assert_int(bo.heard(NetEvent.Kind.SHOT).size()).is_equal(1)


func test_a_shot_block_that_is_not_finite_never_leaves_and_is_refused() -> void:
	var body := (
		auto_free(load("res://gameplay/character/character.tscn").instantiate()) as Character
	)
	add_child(body)
	var command := PlayerCommand.new()
	command.has_shot = true
	command.fire_pressed = true
	command.origin = body.global_position + Vector3.UP * body.tuning.camera_height
	command.shot_yaw = NAN
	# A client cannot send it (the encoder refuses a number that is not finite) ...
	assert_bool(CommandCodec.encode(command).is_empty()).is_true()
	# ... and the server's rule refuses it anyway.
	assert_int(ServerCombat.reason_for(body, command, 4.0)).is_equal(ServerCombat.Reason.NOT_FINITE)
	command.shot_yaw = 0.0
	command.origin = Vector3(INF, 0.0, 0.0)
	assert_int(ServerCombat.reason_for(body, command, 4.0)).is_equal(ServerCombat.Reason.NOT_FINITE)
	command.origin = body.global_position + Vector3.UP * body.tuning.camera_height
	assert_int(ServerCombat.reason_for(body, command, 4.0)).is_equal(0)


func test_a_death_is_a_nine_byte_event_and_the_body_gets_up_where_the_server_says() -> void:
	_rig = auto_free(NetServerRig.new(func(server: NetServer) -> void: server.revive_seconds = 1.0))
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	var ada := await _rig.join("Ada")
	var bo := await _rig.join("Bo")
	var sizes: Array[int] = []
	var first_tick := bo.ticks.size()
	bo.link.packet_received.connect(
		func(data: PackedByteArray) -> void:
			if NetWire.type_of(data) == NetWire.Type.TICK:
				sizes.append(data.size())
	)
	var victim := _rig.server.body_at(0)
	var spot := victim.global_position
	victim.take_hit(HitRecord.shot(500.0, &"", &"", spot, Vector3.FORWARD, 40.0))
	assert_bool(victim.is_dead()).is_true()
	var heard_died := func() -> bool: return not bo.heard(NetEvent.Kind.DIED).is_empty()
	assert_bool(await _rig.until(heard_died, 30)).is_true()
	var died: NetEvent = bo.heard(NetEvent.Kind.DIED)[0]
	assert_int(SnapshotCodec.event_size(died)).is_equal(9)
	assert_int(died.slot).is_equal(0)
	assert_int(died.code).is_equal(ServerCombat.Cause.DAMAGE)
	# Every TICK is exactly its header, its events, its players and its moving props: there is no
	# room for a bone.
	for index in range(first_tick, bo.ticks.size()):
		var tick := bo.ticks[index]
		var expected := NetWire.TICK_HEADER + tick.players.size() * SnapshotCodec.PLAYER_SIZE
		expected += NetWire.TICK_TAIL
		for row in tick.parts:
			expected += NetWire.STREAM_ROW_HEADER + row.state.size()
		for event in tick.events:
			expected += SnapshotCodec.event_size(event)
		if index - first_tick < sizes.size():
			assert_int(sizes[index - first_tick]).is_equal(expected)
	var heard_revived := func() -> bool:
		return (
			not ada.heard(NetEvent.Kind.REVIVED).is_empty()
			and not bo.heard(NetEvent.Kind.REVIVED).is_empty()
		)
	assert_bool(await _rig.until(heard_revived, 90)).is_true()
	assert_bool(victim.is_dead()).is_false()
	assert_float(victim.health).is_equal(victim.max_health)
	var revived: NetEvent = ada.heard(NetEvent.Kind.REVIVED)[0]
	assert_vector(revived.point).is_equal_approx(victim.global_position, Vector3.ONE * 0.006)
	assert_vector(revived.point).is_equal_approx(spot, Vector3.ONE * 0.02)


func test_eight_players_firing_four_shots_a_second_add_under_1_kb_a_second_down() -> void:
	_rig = auto_free(NetServerRig.new())
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	var clients: Array[HandClient] = []
	for index in NetLimits.MAX_PLAYERS:
		clients.append(await _rig.join("P%d" % index))
	assert_int(_rig.server.player_count()).is_equal(NetLimits.MAX_PLAYERS)
	var seconds := 4
	var quiet := await _down_bytes(clients, seconds * NetLimits.TICK_RATE, false)
	var shots_before := _rig.server.combat.shots
	var firing := await _down_bytes(clients, seconds * NetLimits.TICK_RATE, true)
	var shots := _rig.server.combat.shots - shots_before
	# A press every 16 ticks (3.75 a second: a press on the 15th tick finds the cooldown a hair
	# above zero and is refused), scaled to four shots a second each.
	var added := (firing - quiet) / float(seconds) * (NetLimits.MAX_PLAYERS * 4 * seconds) / shots
	prints(
		"8 players firing:",
		shots,
		"shots,",
		_rig.server.combat.hits,
		"hits; down a client",
		roundi(quiet / float(seconds)),
		"->",
		roundi(firing / float(seconds)),
		"B/s, added",
		roundi(added),
		"B/s"
	)
	assert_int(shots).is_greater_equal(NetLimits.MAX_PLAYERS * 3 * seconds)
	assert_float(added).is_less_equal(1024.0)


func test_a_cosmetic_projectile_hits_nothing_and_pushes_nothing() -> void:
	var arena := auto_free(Node3D.new()) as Node3D
	add_child(arena)
	var crate := RigidBody3D.new()
	crate.gravity_scale = 0.0
	crate.collision_layer = PhysicsLayers.PROPS
	var box := CollisionShape3D.new()
	box.shape = BoxShape3D.new()
	crate.add_child(box)
	crate.position = Vector3(0.0, 1.0, -4.0)
	arena.add_child(crate)
	var target := (load("res://gameplay/target/target.tscn") as PackedScene).instantiate() as Target
	target.position = Vector3(3.0, 0.0, -4.0)
	arena.add_child(target)
	var taken := [0]
	Health.of(target).hit_taken.connect(func(_hit: HitRecord) -> void: taken[0] += 1)
	var touched: Array[Node] = []
	for aim in [Vector3(0.0, 1.0, -4.0), target.global_position + Vector3.UP * 0.9]:
		var shot := (
			(load("res://gameplay/projectile/projectile.tscn") as PackedScene).instantiate()
			as Projectile
		)
		shot.authoritative = false
		arena.add_child(shot)
		shot.impacted.connect(
			func(collider: Node, _p: Vector3, _n: Vector3) -> void: touched.append(collider)
		)
		shot.launch(Vector3(0.0, 1.0, 0.0), (aim as Vector3) - Vector3(0.0, 1.0, 0.0), 45.0)
	for _frame in 30:
		await get_tree().physics_frame
	assert_array(touched).contains_exactly_in_any_order([crate, target])
	assert_vector(crate.linear_velocity).is_equal(Vector3.ZERO)
	assert_int(taken[0]).is_equal(0)
	assert_bool(target.is_down()).is_false()


func test_one_seed_gives_one_pellet_whatever_was_fired_before() -> void:
	var definition := (
		(load("res://gameplay/weapon/pistol.tres") as WeaponDef).duplicate() as WeaponDef
	)
	definition.spread = 6.0
	definition.fire_rate = 60.0
	var headings: Array[Vector3] = []
	for earlier in [0, 5]:
		var weapon := (
			(load("res://gameplay/weapon/weapon.tscn") as PackedScene).instantiate() as Weapon
		)
		weapon.definition = definition
		weapon.effects = false
		weapon.seed_base = 2
		var muzzle := Marker3D.new()
		weapon.add_child(muzzle)
		weapon.muzzle = muzzle
		add_child(auto_free(weapon))
		for _shot in earlier:
			weapon.shot_seq = 1000 + _shot
			weapon.make_ready()
			weapon.fire(Vector3.ZERO, Vector3.FORWARD)
		weapon.shot_seq = 77
		weapon.make_ready()
		weapon.fire(Vector3.ZERO, Vector3.FORWARD)
		headings.append(weapon.last_heading)
	assert_vector(headings[0]).is_equal_approx(headings[1], Vector3.ONE * 0.000001)
	assert_bool(headings[0].is_equal_approx(Vector3.FORWARD)).is_false()


# --- Helpers ---


func _floor_ahead(body: Character) -> Vector3:
	var ahead := Vector3.FORWARD.rotated(Vector3.UP, body.facing - PI)
	return body.global_position + ahead * AIM_AHEAD


# A command that aims at `point` from `body`'s eye, with its shot block, pressing fire when `fire`.
static func _shot_at(body: Character, point: Vector3, fire: bool) -> PlayerCommand:
	var eye := body.global_position + Vector3.UP * body.tuning.camera_height
	var angles := CommandCodec.direction_angles(point - eye)
	var command := PlayerCommand.new()
	command.yaw = angles.x
	command.pitch = angles.y
	command.aim = true
	command.has_shot = true
	command.origin = eye
	command.shot_yaw = angles.x
	command.shot_pitch = angles.y
	command.fire_pressed = fire
	return command


# Holds aim at the floor ahead for `ticks` ticks, one command a frame.
func _aim(client: HandClient, body: Character, ticks: int) -> void:
	for _tick in ticks:
		client.send_command(_shot_at(body, _floor_ahead(body), false))
		await _rig.wait(1)


func _rejections(client: HandClient, reason: int) -> int:
	return (
		client
		. heard(NetEvent.Kind.REJECTED)
		. filter(func(event: NetEvent) -> bool: return event.code == reason)
		. size()
	)


# Bytes down summed over every client for `ticks` ticks, each aiming at the floor ahead (turned by
# its slot so no shot meets another body) and, when `fire`, pressing four times a second.
func _down_bytes(clients: Array[HandClient], ticks: int, fire: bool) -> int:
	var start_bytes := 0
	for client in clients:
		start_bytes += client.link.bytes_in
	var press_every := 16
	for tick in ticks:
		for index in clients.size():
			var body := _rig.server.body_at(clients[index].welcome.slot)
			var heading := TAU * index / clients.size()
			var point := (
				body.global_position + Vector3.FORWARD.rotated(Vector3.UP, heading) * AIM_AHEAD
			)
			var command := _shot_at(body, point, fire and tick % press_every == index % press_every)
			clients[index].send_command(command)
		await _rig.wait(1)
	var end_bytes := 0
	for client in clients:
		end_bytes += client.link.bytes_in
	return (end_bytes - start_bytes) / clients.size()
