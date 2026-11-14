# The bandage online (gdstudio #1386). Over a real socket with clients driven by hand
# (`NetServerRig`): a press is the command's hotbar place; the server's body starts the use, heals
# once after the apply share of its time and takes one bandage, and says so in 8-byte USE events
# (STARTED to the others, APPLIED to everyone with the health and the count); a second press
# during the use does nothing; a hit on the server cuts it on every screen with nothing used; a
# press at full health is refused to its sender alone. Then with two predicting clients in
# lockstep (`OnlineRig`): Ada's screen starts the use at the press, her health and count follow the
# server's, Bo's screen plays the clip on her puppet from the event alone, a sprint cuts it
# everywhere, and the bytes a use adds are its events: the uplink does not change.
extends GdUnitTestSuite

const HEAL := 25.0
const HURT := 40
## The research's budgets a client (online-client.md): down 5 KB/s, up 2 KB/s.
const DOWN_BUDGET := 5000.0
const UP_BUDGET := 2000.0

var _rig: Node


func after_test() -> void:
	_rig = null


# --- The server's word (hand-driven clients) ---


func test_a_press_heals_once_on_the_server_and_the_events_carry_it() -> void:
	var rig := await _hand_rig()
	var ada: HandClient = rig.clients[0]
	var bo: HandClient = rig.clients[1]
	var body := rig.server.body_at(0)
	var health := Health.of(body)
	health.set_wire_value(HURT)
	var bandage := Hotbar.of(body).item_at(0)
	assert_int(Hotbar.of(body).count_at(0)).is_equal(3)
	var press := _press(0)
	ada.send_command(press)
	var started := func() -> bool: return not bo.heard(NetEvent.Kind.USE).is_empty()
	assert_bool(await rig.until(started, 30)).is_true()
	var first: NetEvent = bo.heard(NetEvent.Kind.USE)[0]
	assert_int(first.code).is_equal(NetEvent.UseCode.STARTED)
	assert_int(first.slot).is_equal(0)
	assert_int(first.id).is_equal(0)
	assert_int(first.seq).is_equal(press.seq & 0xFFFF)
	assert_int(SnapshotCodec.event_size(first)).is_equal(8)
	# The sender's own screen began it at the press: no STARTED back to Ada.
	assert_array(ada.heard(NetEvent.Kind.USE)).is_empty()
	assert_bool(rig.server.items.use_of(0).is_using()).is_true()
	# A second press during the use uses nothing and says nothing.
	await rig.wait(10)
	ada.send_command(_press(0))
	var applied := func() -> bool: return _codes(ada).has(NetEvent.UseCode.APPLIED)
	assert_bool(await rig.until(applied, roundi(bandage.use_time * 60.0) + 30)).is_true()
	await rig.wait(roundi(bandage.use_time * 60.0 * (1.0 - bandage.use_apply_share)) + 10)
	assert_float(health.value).is_equal(HURT + HEAL)
	assert_int(Hotbar.of(body).count_at(0)).is_equal(2)
	assert_array(_codes(ada)).contains_exactly([NetEvent.UseCode.APPLIED])
	assert_array(_codes(bo)).contains_exactly([NetEvent.UseCode.STARTED, NetEvent.UseCode.APPLIED])
	for event: NetEvent in ada.heard(NetEvent.Kind.USE):
		assert_int(event.amount).is_equal(HURT + int(HEAL))
		assert_int(event.detail).is_equal(2)
		assert_int(event.seq).is_equal(press.seq & 0xFFFF)
	assert_int(rig.server.items.started).is_equal(1)
	assert_int(rig.server.items.applied).is_equal(1)


func test_a_hit_on_the_server_cuts_the_use_on_every_screen_and_uses_nothing() -> void:
	var rig := await _hand_rig()
	var ada: HandClient = rig.clients[0]
	var bo: HandClient = rig.clients[1]
	var body := rig.server.body_at(0)
	Health.of(body).set_wire_value(70)
	ada.send_command(_press(0))
	await rig.until(func() -> bool: return rig.server.items.use_of(0).is_using(), 30)
	await rig.wait(20)
	body.hit(5.0)
	var cut := func() -> bool:
		return (
			_codes(ada).has(NetEvent.UseCode.CANCELLED)
			and _codes(bo).has(NetEvent.UseCode.CANCELLED)
		)
	assert_bool(await rig.until(cut, 30)).is_true()
	await rig.wait(120)
	var event: NetEvent = ada.heard(NetEvent.Kind.USE)[-1]
	assert_str(String(ItemUse.reason_of(event.detail))).is_equal("hit")
	assert_int(Hotbar.of(body).count_at(0)).is_equal(3)
	assert_float(Health.of(body).value).is_equal(65.0)
	assert_bool(_codes(bo).has(NetEvent.UseCode.APPLIED)).is_false()


func test_a_press_at_full_health_is_refused_to_its_sender_alone() -> void:
	var rig := await _hand_rig()
	var ada: HandClient = rig.clients[0]
	var bo: HandClient = rig.clients[1]
	var press := _press(0)
	ada.send_command(press)
	var refused := func() -> bool: return _codes(ada).has(NetEvent.UseCode.REFUSED)
	assert_bool(await rig.until(refused, 30)).is_true()
	await rig.wait(10)
	assert_int(ada.heard(NetEvent.Kind.USE)[0].seq).is_equal(press.seq & 0xFFFF)
	assert_array(bo.heard(NetEvent.Kind.USE)).is_empty()
	assert_bool(rig.server.items.use_of(0).is_using()).is_false()
	assert_int(Hotbar.of(rig.server.body_at(0)).count_at(0)).is_equal(3)


# --- Two screens (predicting clients) ---


func test_on_two_screens_the_use_plays_and_the_health_and_count_follow_the_server() -> void:
	var rig := await _online_rig()
	var ada := rig.clients[0]
	var bo := rig.clients[1]
	var server_body := rig.server_body(ada)
	_hurt(rig, ada, HURT)
	var own_use := ItemUse.of(ada.player)
	var puppet := bo.remote_players.puppet_at(ada.slot)
	var puppet_use := ItemUse.of(puppet)
	assert_int(own_use.role).is_equal(ItemUse.Role.PREDICT)
	assert_int(puppet_use.role).is_equal(ItemUse.Role.PUPPET)
	# The bytes of a window as long as the use and a little more, then of one with nothing
	# happening.
	var window := roundi(Hotbar.of(ada.player).item_at(0).use_time * NetLimits.TICK_RATE) + 40
	var down_before := _down(rig)
	var up_before := _up(rig)
	var pressed_at := Engine.get_physics_frames()
	rig.controllers[0].next.use_place = 0
	await rig.wait(1)
	# Ada's screen began it at the press, before any word from the server.
	assert_bool(own_use.is_using()).is_true()
	assert_bool(ada.player.hands_busy).is_true()
	var puppet_playing := func() -> bool: return puppet_use.is_using()
	assert_bool(await rig.until(puppet_playing, 30)).is_true()
	var animation := puppet.get_node("Animation") as CharacterAnimation
	assert_bool(animation.is_acting()).is_true()
	# The puppet's own sound, at the puppet, and the left hand off the weapon, all from the event.
	assert_bool(puppet_use.sound.playing).is_true()
	assert_float(puppet_use.sound.global_position.distance_to(puppet.global_position)).is_less(2.0)
	assert_bool(puppet.hands_busy).is_true()
	await rig.wait(window - (Engine.get_physics_frames() - pressed_at))
	assert_bool(puppet_use.is_using()).is_false()
	var use_down := _down(rig) - down_before
	var use_up := _up(rig) - up_before
	down_before = _down(rig)
	up_before = _up(rig)
	await rig.wait(window)
	var quiet_down := _down(rig) - down_before
	var quiet_up := _up(rig) - up_before
	var seconds := float(window) / NetLimits.TICK_RATE
	var clients := rig.clients.size()
	var line := (
		"bandage online, a client: quiet down %.0f B/s up %.0f B/s; "
		% [quiet_down / seconds / clients, quiet_up / seconds / clients]
	)
	line += (
		"using down %.0f B/s up %.0f B/s; the use added %d B down, %d B up in all"
		% [
			use_down / seconds / clients,
			use_up / seconds / clients,
			use_down - quiet_down,
			use_up - quiet_up
		]
	)
	prints(line)
	assert_float(use_down / seconds / clients).is_less(DOWN_BUDGET)
	assert_float(use_up / seconds / clients).is_less(UP_BUDGET)
	# The use's own bytes: a STARTED to Bo and an APPLIED to both, 8 bytes each, and nothing else
	# about it (the clip, the sound and the sign are each screen's). The commands are the same 15
	# bytes with or without a press: the uplink of the use is the quiet one's.
	var codes := NetEvent.UseCode
	assert_dict(ada.combat.items.played).is_equal({codes.APPLIED: 1})
	assert_dict(bo.combat.items.played).is_equal({codes.STARTED: 1, codes.APPLIED: 1})
	assert_int(SnapshotCodec.event_size(NetEvent.use(0, codes.APPLIED, 0, 1, 2, 65))).is_equal(8)
	assert_int(use_up).is_equal(quiet_up)
	assert_float(Health.of(server_body).value).is_equal(HURT + HEAL)
	assert_float(Health.of(ada.player).value).is_equal(HURT + HEAL)
	assert_float(Health.of(puppet).value).is_equal(HURT + HEAL)
	assert_int(Hotbar.of(server_body).count_at(0)).is_equal(2)
	assert_int(Hotbar.of(ada.player).count_at(0)).is_equal(2)
	# The puppet's bag is not on the wire: only its health is.
	assert_int(rig.server.items.applied).is_equal(1)
	assert_bool(own_use.is_using() or puppet_use.is_using()).is_false()


func test_a_sprint_cuts_the_use_on_every_screen_and_uses_nothing() -> void:
	var rig := await _online_rig()
	var ada := rig.clients[0]
	var bo := rig.clients[1]
	_hurt(rig, ada, 60)
	var own_use := ItemUse.of(ada.player)
	var puppet_use := ItemUse.of(bo.remote_players.puppet_at(ada.slot))
	var server_use := rig.server.items.use_of(ada.slot)
	var cuts: Array[StringName] = []
	own_use.cancelled.connect(func(_p: int, _i: ItemDef, why: StringName) -> void: cuts.append(why))
	rig.controllers[0].next.use_place = 0
	await rig.until(func() -> bool: return puppet_use.is_using(), 30)
	assert_bool(server_use.is_using()).is_true()
	rig.controllers[0].next.move = Vector2(0.0, 1.0)
	rig.controllers[0].next.sprint = true
	var all_cut := func() -> bool:
		return not (own_use.is_using() or server_use.is_using() or puppet_use.is_using())
	assert_bool(await rig.until(all_cut, 40)).is_true()
	rig.controllers[0].next.sprint = false
	rig.controllers[0].next.move = Vector2.ZERO
	await rig.wait(120)
	assert_array(cuts).contains_exactly([&"sprint"])
	assert_int(rig.server.items.applied).is_equal(0)
	assert_int(Hotbar.of(rig.server_body(ada)).count_at(0)).is_equal(3)
	assert_int(Hotbar.of(ada.player).count_at(0)).is_equal(3)
	assert_float(Health.of(ada.player).value).is_equal(60.0)


func test_a_use_the_server_refuses_is_taken_back_on_the_user_s_screen() -> void:
	var rig := await _online_rig()
	var ada := rig.clients[0]
	# Ada's screen thinks she is hurt, the server knows she is not (a heal it already applied).
	Health.of(ada.player).set_wire_value(50)
	var own_use := ItemUse.of(ada.player)
	var cuts: Array[StringName] = []
	own_use.cancelled.connect(func(_p: int, _i: ItemDef, why: StringName) -> void: cuts.append(why))
	rig.controllers[0].next.use_place = 0
	await rig.wait(1)
	assert_bool(own_use.is_using()).is_true()
	assert_bool(await rig.until(func() -> bool: return not own_use.is_using(), 30)).is_true()
	assert_array(cuts).contains_exactly([&"refused"])
	assert_int(Hotbar.of(ada.player).count_at(0)).is_equal(3)


func test_the_server_s_bodies_carry_the_player_s_bag_and_hotbar() -> void:
	var player := (load("res://gameplay/player/player.tscn") as PackedScene).instantiate()
	var body := (load("res://gameplay/character/character.tscn") as PackedScene).instantiate()
	ServerItems.equip(body, load("res://gameplay/net/body_items.tscn") as PackedScene)
	add_child(player)
	add_child(body)
	var mine := Hotbar.of(player)
	var served := Hotbar.of(body)
	assert_object(served).is_not_null()
	assert_object(ItemUse.of(body)).is_not_null()
	assert_int(served.place_count).is_equal(mine.place_count)
	for place in mine.place_count:
		assert_object(served.item_at(place)).is_same(mine.item_at(place))
		assert_int(served.count_at(place)).is_equal(mine.count_at(place))
	assert_object(served.inventory.get_parent()).is_same(body)
	assert_object(ItemUse.of(body).character).is_same(body)
	player.free()
	body.free()


# --- Helpers ---


func _hand_rig() -> NetServerRig:
	var rig := auto_free(NetServerRig.new()) as NetServerRig
	_rig = rig
	add_child(rig)
	assert_bool(rig.start()).is_true()
	await rig.join("Ada")
	await rig.join("Bo")
	await rig.wait(4)
	return rig


func _online_rig() -> OnlineRig:
	var rig := auto_free(OnlineRig.new()) as OnlineRig
	_rig = rig
	add_child(rig)
	assert_bool(rig.start()).is_true()
	var ada := await rig.join("Ada")
	var bo := await rig.join("Bo")
	assert_object(ada).is_not_null()
	assert_object(bo).is_not_null()
	var seen := func() -> bool:
		return (
			bo.remote_players.puppet_at(ada.slot) != null
			and ada.remote_players.puppet_at(bo.slot) != null
		)
	assert_bool(await rig.until(seen, 120)).is_true()
	await rig.wait(10)
	return rig


# Ada is hurt to `value` on the server and on her screen, as a HIT would leave her.
static func _hurt(rig: OnlineRig, client: NetClient, value: int) -> void:
	Health.of(rig.server_body(client)).set_wire_value(value)
	Health.of(client.player).set_wire_value(value)


static func _press(place: int) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.use_place = place
	return command


static func _codes(client: HandClient) -> Array:
	return client.heard(NetEvent.Kind.USE).map(func(event: NetEvent) -> int: return event.code)


static func _down(rig: OnlineRig) -> int:
	var total := 0
	for client in rig.clients:
		total += client.link.bytes_in
	return total


static func _up(rig: OnlineRig) -> int:
	var total := 0
	for client in rig.clients:
		total += client.link.bytes_out
	return total
