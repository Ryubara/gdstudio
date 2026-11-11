# The map's doors and pickups in an online game, with clients joined to a real server over a real
# socket on 127.0.0.1 (`OnlineRig`): the server owns every part, a client hears of each change as
# an `entity` or `pickup` event (or the WELCOME's table when it joins late) and shows it.
extends GdUnitTestSuite

## In `world/prototype/prototype_level.tscn`: in front of the room's door (`Doors/MainDoor`, at
## z -9.5), clear of the pressure pad (z -6.5 to -3.5) that also opens it.
const BEFORE_DOOR := Vector3(13.0, 0.0, -8.3)
## On the far landing, inside `Pickups/BridgeCoin` (at y 2.7 over a top at y 2).
const AT_COIN := Vector3(18.0, 2.0, 16.0)
## The body's facing for a view that looks along -Z (`facing` is `yaw + PI`).
const FACING_NORTH := PI

var _rig: OnlineRig


func before_test() -> void:
	_rig = auto_free(OnlineRig.new(false))
	add_child(_rig)
	assert_bool(_rig.start()).is_true()


func test_a_door_player_one_opens_is_seen_opening_on_player_twos_screen() -> void:
	var ada := await _rig.join("Ada")
	var bo := await _rig.join("Bo")
	await _rig.wait(20)
	_place(ada, BEFORE_DOOR, FACING_NORTH)
	await _rig.wait(20)
	var server_door := _part(_rig.server_view, "MainDoor") as Door
	var bos_door := _part(_rig.views[1], "MainDoor") as Door
	var adas_door := _part(_rig.views[0], "MainDoor") as Door
	assert_float(bos_door.openness()).is_equal(0.0)
	_rig.controllers[0].next.yaw = 0.0
	_rig.controllers[0].next.interact_pressed = true
	assert_bool(await _rig.until(func() -> bool: return server_door.openness() > 0.0)).is_true()
	assert_bool(await _rig.until(func() -> bool: return bos_door.is_open(), 180)).is_true()
	# Every peer holds the panel at the same place for the same tick.
	var from_tick := _rig.server.server_tick - 120
	for tick in range(from_tick, from_tick + 180, 3):
		assert_float(bos_door.openness_at(tick)).is_equal_approx(
			server_door.openness_at(tick), 1e-6
		)
		assert_float(adas_door.openness_at(tick)).is_equal_approx(
			server_door.openness_at(tick), 1e-6
		)
	var panel := bos_door.get_node("%Shape") as Node3D
	var server_panel := server_door.get_node("%Shape") as Node3D
	await _rig.wait(2)
	assert_vector(panel.global_position).is_equal_approx(
		server_panel.global_position, Vector3.ONE * 0.001
	)


func test_a_player_who_joins_late_sees_the_open_door_and_the_taken_coin_at_once() -> void:
	var ada := await _rig.join("Ada")
	await _rig.wait(20)
	var server_door := _part(_rig.server_view, "MainDoor") as Door
	server_door.open()
	_place(ada, AT_COIN, FACING_NORTH)
	assert_bool(await _rig.until(func() -> bool: return server_door.is_open(), 180)).is_true()
	var server_coin := _part(_rig.server_view, "BridgeCoin") as Pickup
	assert_bool(server_coin.is_available()).is_false()
	var cy := await _rig.join("Cy")
	assert_object(cy).is_not_null()
	var cys_door := _part(_rig.views[1], "MainDoor") as Door
	# The first frame after the WELCOME: open, not closed and then opening.
	assert_float(cys_door.openness()).is_equal(1.0)
	assert_float(cys_door.openness_at(cy.seq + 30)).is_equal(1.0)
	assert_bool((_part(_rig.views[1], "BridgeCoin") as Pickup).is_available()).is_false()
	assert_bool((_part(_rig.views[1], "TowerStar") as Pickup).is_available()).is_true()


func test_two_players_on_one_coin_cannot_both_take_it() -> void:
	var ada := await _rig.join("Ada")
	var bo := await _rig.join("Bo")
	await _rig.wait(20)
	_place(ada, AT_COIN, FACING_NORTH)
	_place(bo, AT_COIN, FACING_NORTH)
	await _rig.wait(40)
	var takers := 0
	for client in [ada, bo]:
		var server_count := _rig.server_body(client).count_of(&"coin")
		assert_int(client.player.count_of(&"coin")).is_equal(server_count)
		takers += server_count
	assert_int(takers).is_equal(1)
	for view in [_rig.server_view, _rig.views[0], _rig.views[1]]:
		assert_bool((_part(view, "BridgeCoin") as Pickup).is_available()).is_false()


func test_a_pickup_comes_back_on_every_screen_when_the_server_says_so() -> void:
	var ada := await _rig.join("Ada")
	await _rig.wait(20)
	var server_coin := _part(_rig.server_view, "BridgeCoin") as Pickup
	server_coin.respawn_time = 0.5
	_place(ada, AT_COIN, FACING_NORTH)
	var adas_coin := _part(_rig.views[0], "BridgeCoin") as Pickup
	assert_bool(await _rig.until(func() -> bool: return not adas_coin.is_available())).is_true()
	_place(ada, AT_COIN + Vector3(0.0, 0.0, 3.0), FACING_NORTH)
	assert_bool(await _rig.until(adas_coin.is_available, 120)).is_true()
	assert_int(ada.player.count_of(&"coin")).is_equal(1)


func test_a_client_whose_map_has_one_more_part_is_refused_for_the_world() -> void:
	var reasons: Array[int] = []
	_rig.prepare_arena = func(arena: Node) -> void:
		var extra := (load("res://gameplay/door/door.tscn") as PackedScene).instantiate()
		extra.name = "ExtraDoor"
		arena.get_node("World").add_child(extra)
		(arena.get_node("NetClient") as NetClient).refused.connect(reasons.append)
	var client := await _rig.join("Dee", 60)
	assert_object(client).is_null()
	assert_array(reasons).contains_exactly([NetWire.Refusal.WORLD])


func test_the_map_table_and_the_events_fit_the_wire() -> void:
	var parts := _rig.server.map_parts
	var table := parts.table(_rig.server.server_tick)
	var players: Array[PlayerEntry] = []
	var welcome := SnapshotCodec.welcome(0, 1, 1, table, players)
	var bare := SnapshotCodec.welcome(0, 1, 1, [] as Array[EntityEntry], players)
	var by_kind := {}
	for entry in table:
		by_kind[entry.kind] = entry.state.size()
	var no_events := SnapshotCodec.tick(1, 1, [] as Array[NetEvent], players).size()
	var door := _part(_rig.server_view, "MainDoor").get_node("NetEntity") as NetEntity
	var door_event := NetEvent.entity(door.id, 1, (door.part() as Door).net_write(1))
	var door_bytes := SnapshotCodec.tick(1, 1, [door_event] as Array[NetEvent], players).size()
	var pickup_bytes := (
		SnapshotCodec.tick(1, 1, [NetEvent.pickup(3, 0)] as Array[NetEvent], players).size()
	)
	prints(
		"map parts:",
		table.size(),
		"parts, WELCOME",
		welcome.size(),
		"bytes (",
		bare.size(),
		"without them), state bytes by kind",
		by_kind,
		"door event",
		door_bytes - no_events,
		"pickup event",
		pickup_bytes - no_events
	)
	assert_int(table.size()).is_greater(10)
	assert_int(table.size()).is_less_equal(NetLimits.MAX_ENTITIES)
	assert_bool(welcome.is_empty()).is_false()
	assert_int(by_kind[NetEntity.KINDS[&"door"]]).is_equal(4)
	assert_int(by_kind[NetEntity.KINDS[&"platform"]]).is_equal(6)
	assert_int(by_kind[NetEntity.KINDS[&"pickup"]]).is_equal(1)
	assert_int(door_bytes - no_events).is_equal(12)
	assert_int(pickup_bytes - no_events).is_equal(4)


# Puts the client's body and its server body at one spot (a test's shortcut for a walk there).
func _place(client: NetClient, at: Vector3, facing: float) -> void:
	client.player.teleport(at, facing)
	_rig.server_body(client).teleport(at, facing)


static func _part(view: Node, part_name: String) -> Node:
	return view.find_child(part_name, true, false)
