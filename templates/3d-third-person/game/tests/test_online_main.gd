# The online game (`online_main.tscn`): the offline game with a client that joins a real server
# over a socket on 127.0.0.1, and the overlay of connecting, refused and lost. The server runs in a
# view with a world of its own (`OnlineRig`), the online game in another, as two machines would.
extends GdUnitTestSuite

const ONLINE := "res://online_main.tscn"

var _rig: OnlineRig
var _refuser: WsListener


func after_test() -> void:
	NetClient.next_url = ""
	if _refuser != null:
		_refuser.close()
		_refuser = null


func _start_rig(configure := Callable()) -> OnlineRig:
	_rig = auto_free(OnlineRig.new(false)) as OnlineRig
	_rig.prepare_server = configure
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	return _rig


# The online game in a view of its own, joining `url` as the menu would hand it over.
func _open(url: String) -> OnlineMain:
	var view := SubViewport.new()
	view.own_world_3d = true
	view.size = Vector2i(320, 180)
	add_child(auto_free(view))
	NetClient.next_url = url
	var online := (load(ONLINE) as PackedScene).instantiate() as OnlineMain
	online.client.clock = SocketRig.frame_clock
	view.add_child(online)
	return online


func _until(condition: Callable, frames := 240) -> bool:
	for _i in frames:
		if condition.call():
			return true
		await get_tree().physics_frame
	return condition.call()


func test_the_online_game_is_the_offline_game_with_a_client() -> void:
	var state := (load(ONLINE) as PackedScene).get_state()
	assert_str(state.get_node_instance(1).resource_path).is_equal("res://main.tscn")
	var online := auto_free((load(ONLINE) as PackedScene).instantiate()) as OnlineMain
	assert_object(online.client.player).is_same(online.get_node("Main/PlayerRig/Player"))
	assert_object(online.client.world_root).is_same(online.get_node("Main/World"))
	assert_object(online.client.remote_players).is_same(online.remote_players)
	assert_bool(online.client.join_on_ready).is_true()
	assert_object(online.status.client).is_same(online.client)


func test_it_joins_shows_connecting_then_plays_and_sees_the_other_player() -> void:
	var rig := _start_rig()
	var other := await rig.join("Other")
	assert_object(other).is_not_null()
	var online := _open("ws://127.0.0.1:%d" % rig.server.listener.port())
	assert_int(online.status.state).is_equal(OnlineStatus.State.CONNECTING)
	assert_bool(await _until(func() -> bool: return online.client.is_seated())).is_true()
	assert_int(online.status.state).is_equal(OnlineStatus.State.PLAYING)
	assert_bool((online.status.get_node("%Panel") as Control).visible).is_false()
	assert_bool(online.client.player.input_enabled).is_true()
	(
		assert_bool(await _until(func() -> bool: return online.remote_players.slots().size() == 1))
		. is_true()
	)
	assert_int(online.remote_players.slots()[0]).is_equal(other.slot)


func test_a_lost_server_shows_connection_lost_and_turns_the_input_off() -> void:
	var rig := _start_rig()
	var online := _open("ws://127.0.0.1:%d" % rig.server.listener.port())
	assert_bool(await _until(func() -> bool: return online.client.is_seated())).is_true()
	rig.server.listener.close()
	(
		assert_bool(
			await _until(func() -> bool: return online.status.state == OnlineStatus.State.LOST)
		)
		. is_true()
	)
	assert_str(online.status.message()).is_equal("Connection lost.")
	assert_bool((online.status.get_node("%Panel") as Control).visible).is_true()
	assert_bool((online.status.get_node("%BackButton") as Control).visible).is_true()
	assert_bool(online.client.player.input_enabled).is_false()


func test_a_full_game_says_so() -> void:
	var rig := _start_rig(func(server: NetServer) -> void: server.max_players = 1)
	assert_object(await rig.join("First")).is_not_null()
	var online := _open("ws://127.0.0.1:%d" % rig.server.listener.port())
	(
		assert_bool(
			await _until(func() -> bool: return online.status.state == OnlineStatus.State.FULL)
		)
		. is_true()
	)
	assert_str(online.status.message()).is_equal("The game is full.")


func test_a_server_of_another_version_says_reload_or_update() -> void:
	# A server that answers every hello as a server of the next version would.
	_refuser = WsListener.new()
	assert_int(_refuser.listen(0, "127.0.0.1")).is_equal(OK)
	_refuser.packet_received.connect(
		func(peer: int, _data: PackedByteArray) -> void:
			_refuser.send(
				peer,
				PackedByteArray(
					[NetWire.Type.REFUSED, NetWire.Refusal.VERSION, NetWire.VERSION + 1]
				)
			)
	)
	var pump := func() -> void: _refuser.poll()
	get_tree().physics_frame.connect(pump)
	var online := _open("ws://127.0.0.1:%d" % _refuser.port())
	var refused := await _until(
		func() -> bool: return online.status.state == OnlineStatus.State.OLD_VERSION
	)
	get_tree().physics_frame.disconnect(pump)
	assert_bool(refused).is_true()
	assert_str(online.status.message()).is_equal(
		"The server runs another version of the game. Update the game to join."
	)
	assert_bool(online.client.is_seated()).is_false()


func test_nobody_answering_is_unreachable_not_connecting_for_ever() -> void:
	# A port nothing listens on: the socket closes before it opens.
	var probe := TCPServer.new()
	probe.listen(0, "127.0.0.1")
	var port := probe.get_local_port()
	probe.stop()
	var online := _open("ws://127.0.0.1:%d" % port)
	online.status.connect_seconds = 3.0
	(
		assert_bool(
			await _until(
				func() -> bool: return online.status.state == OnlineStatus.State.UNREACHABLE, 300
			)
		)
		. is_true()
	)
	assert_str(online.status.message()).is_equal("The server did not answer.")


func test_bot_plays_through_the_players_own_input() -> void:
	var rig := _start_rig()
	var online := _open("ws://127.0.0.1:%d" % rig.server.listener.port())
	var bot := online.add_bot(PlayerBot.Plan.ROUTE)
	assert_bool(await _until(func() -> bool: return online.client.is_seated())).is_true()
	assert_object(online.client.player.controller).is_instanceof(PlayerInput)
	var start := online.client.player.global_position
	await rig.wait(120)
	# The server's body moved as the predicted one did: the commands came from the keys pressed.
	var body := rig.server_body(online.client)
	assert_float(body.global_position.distance_to(start)).is_greater(1.5)
	assert_float(body.global_position.distance_to(online.client.player.global_position)).is_less(
		0.3
	)
	assert_int(bot.stage).is_greater_equal(0)
