# A hitscan shot online (gdstudio #1252), over a real socket with clients driven by hand: the
# server fires the pistol with `WeaponDef.hitscan` on, makes no projectile, and the shot costs the
# other players only its SHOT and its HIT, in the same TICK; every TICK holds nothing else (no
# projectile state, no per-tick update). The projectile pistol's shot costs the same two events,
# its HIT coming as the round lands. The tests switch the shared `pistol.tres`, which every peer of
# the rig holds, and put it back.
extends GdUnitTestSuite

const PISTOL := "res://gameplay/weapon/pistol.tres"
## Where Ada aims: the floor this far ahead, so the shot is a HIT.
const AIM_AHEAD := 3.0
## Ticks of aim held before the press (the arm comes up in `aim_pose_time`).
const AIM_TICKS := 20

var _rig: NetServerRig


func after_test() -> void:
	(load(PISTOL) as WeaponDef).hitscan = false
	_rig = null


func test_a_hitscan_shot_is_a_shot_and_a_hit_in_one_tick_and_nothing_else() -> void:
	var cost := await _one_shot(true)
	assert_int(cost["projectiles"]).is_equal(0)
	assert_int(cost["event_bytes"]).is_equal(30)
	assert_array(cost["kinds"]).contains_exactly_in_any_order(
		[NetEvent.Kind.SHOT, NetEvent.Kind.HIT]
	)
	# Instant: the HIT rides in the TICK that carries the SHOT.
	assert_int(cost["shot_tick"]).is_equal(cost["hit_tick"])


func test_a_projectile_shot_costs_the_same_two_events_on_the_wire() -> void:
	var cost := await _one_shot(false)
	assert_int(cost["projectiles"]).is_greater(0)
	assert_int(cost["event_bytes"]).is_equal(30)
	assert_array(cost["kinds"]).contains_exactly_in_any_order(
		[NetEvent.Kind.SHOT, NetEvent.Kind.HIT]
	)
	assert_int(cost["hit_tick"]).is_greater_equal(cost["shot_tick"])


# --- Helpers ---


# Ada fires one shot at the floor ahead with the pistol hitscan or not; answers what Bo's TICKs
# carried: the event bytes and kinds, the TICKs of the SHOT and the HIT, and the projectiles the
# server's world held after the press.
func _one_shot(hitscan: bool) -> Dictionary:
	(load(PISTOL) as WeaponDef).hitscan = hitscan
	_rig = auto_free(NetServerRig.new())
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	var ada := await _rig.join("Ada")
	var bo := await _rig.join("Bo")
	var body := _rig.server.body_at(0)
	await _aim(ada, body, AIM_TICKS)
	var sizes: Array[int] = []
	var first_tick := bo.ticks.size()
	bo.link.packet_received.connect(
		func(data: PackedByteArray) -> void:
			if NetWire.type_of(data) == NetWire.Type.TICK:
				sizes.append(data.size())
	)
	ada.send_command(_shot_at(body, _floor_ahead(body), true))
	var projectiles := 0
	for _tick in 8:
		await _aim(ada, body, 1)
		projectiles = maxi(projectiles, _projectiles_in(_rig))
	var heard_hit := func() -> bool: return not bo.heard(NetEvent.Kind.HIT).is_empty()
	assert_bool(await _rig.until(heard_hit, 90)).is_true()
	await _aim(ada, body, 10)
	var cost := {
		"projectiles": projectiles,
		"event_bytes": 0,
		"kinds": [],
		"shot_tick": -1,
		"hit_tick": -1,
	}
	for index in range(first_tick, bo.ticks.size()):
		var tick := bo.ticks[index]
		var expected := NetWire.TICK_HEADER + NetWire.TICK_TAIL
		# Each entry's own size: Ada aims, and an aiming entry ends with its aim yaw byte (#1300).
		for player in tick.players:
			expected += SnapshotCodec.player_size(player)
		for row in tick.parts:
			expected += NetWire.STREAM_ROW_HEADER + row.state.size()
		for event in tick.events:
			expected += SnapshotCodec.event_size(event)
			cost["event_bytes"] += SnapshotCodec.event_size(event)
			cost["kinds"].append(event.kind)
			if event.kind == NetEvent.Kind.SHOT:
				cost["shot_tick"] = index
			elif event.kind == NetEvent.Kind.HIT:
				cost["hit_tick"] = index
		# Every TICK is its header, players, props and events: no room for a projectile's state.
		if index - first_tick < sizes.size():
			assert_int(sizes[index - first_tick]).is_equal(expected)
	prints("hitscan" if hitscan else "projectile", "shot down Bo:", cost)
	assert_int(_rig.server.combat.shots).is_equal(1)
	return cost


static func _projectiles_in(root: Node) -> int:
	var flying := 0
	for node in root.find_children("*", "Projectile", true, false):
		if (node as Projectile).is_flying():
			flying += 1
	return flying


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
