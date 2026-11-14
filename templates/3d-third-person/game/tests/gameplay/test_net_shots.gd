# Shots, hits and deaths online (gdstudio #906): a game server and two predicting clients, each in a
# world of its own and joined over a real socket on 127.0.0.1 (`OnlineRig`). The clients fire with
# their commands, as a player does, never with a call beside the step. Ada shoots a target: on
# Bo's screen her puppet fires (a cosmetic projectile, the flash, the sound), the impact plays and
# the target falls, and no client applies a hit itself. Ada shoots Bo three times: his health
# falls on both screens as the server's does, he dies into a ragdoll on both, and gets up where
# the server says. At 200 ms each way the server's rule decides: a shot at where a running Bo is
# drawn misses, and the same shot at a Bo who stands hits.
extends GdUnitTestSuite

## Where the two stand on the open ground in front of the targets (`Targets`, z = -15.2), Ada
## behind `TargetB` (x = -3) and Bo beside her.
const ADA_AT := Vector3(-3.0, 0.3, -10.0)
const BO_AT := Vector3(1.0, 0.3, -10.0)
## The middle of a target's board (a board of 0.8 m on its post).
const BOARD_RISE := 0.9
## The lane of the latency test: Bo runs along +X from its start (a wall stops him past x = 6.6),
## crossing Ada's view 4 m in front of her.
const LANE_START := Vector3(-8.0, 0.3, -10.0)
const LANE_ADA_AT := Vector3(-3.0, 0.3, -6.0)
## Where a body is aimed at, above its feet.
const CHEST := 1.15
## Ticks of aim held before the first press.
const AIM_TICKS := 30

var _rig: OnlineRig
var _ada: NetClient
var _bo: NetClient
## What Ada's controller does each tick: aim at `_aim_point.call()`, press fire on the ticks in
## `_presses`.
var _aim_point := Callable()
var _presses: Array[int] = []


func after_test() -> void:
	_rig = null
	_ada = null
	_bo = null
	_aim_point = Callable()
	_presses = []


func _start(delay := 0.0) -> void:
	_rig = auto_free(OnlineRig.new(false))
	_rig.delay = delay
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_rig.server.combat.revive_seconds = 1.5
	_ada = await _rig.join("Ada", 600)
	_bo = await _rig.join("Bo", 600)
	assert_object(_ada).is_not_null()
	assert_object(_bo).is_not_null()
	_put(_ada, ADA_AT, PI)
	_put(_bo, BO_AT, PI)
	_rig.controllers[0].plan = _ada_plan
	await _rig.wait(40)


func test_a_shot_at_a_target_is_seen_on_the_other_screen() -> void:
	await _start()
	var board := _board(_ada, &"TargetB")
	_aim_point = func() -> Vector3: return board
	var puppet := _bo.remote_players.puppet_at(_ada.slot)
	assert_object(puppet).is_not_null()
	var fired: Array[Projectile] = []
	var sounds := [0]
	var shot_sound := puppet.weapon.get_node("%ShotSound") as AudioStreamPlayer3D
	puppet.weapon.fired.connect(
		func(shot: Projectile) -> void:
			fired.append(shot)
			sounds[0] += 1 if shot_sound.playing else 0
	)
	var flashes := [0]
	var emitter := EffectEmitter.find(_bo)
	emitter.played.connect(func(_effect: EffectDef, _slot: EffectSlot) -> void: flashes[0] += 1)
	var impacts: Array[Object] = []
	Impacts.find(_bo).impact_made.connect(
		func(_surface: ImpactSurface, collider: Object, _p: Vector3, _n: Vector3) -> void:
			impacts.append(collider)
	)
	var taken := _count_client_hits()
	_presses = [_rig.controllers[0].ticks + 5]
	var target_on_bo := _target(_bo, &"TargetB")
	var target_on_ada := _target(_ada, &"TargetB")
	var target_on_server := _target_in(_rig.server_view, &"TargetB")
	var fell := func() -> bool: return target_on_bo.is_down() and target_on_ada.is_down()
	assert_bool(await _rig.until(fell, 180)).is_true()
	assert_bool(target_on_server.is_down()).is_true()
	assert_int(fired.size()).is_equal(1)
	assert_object(fired[0]).is_not_null()
	assert_bool(fired[0].authoritative).is_false()
	assert_int(sounds[0]).is_equal(1)
	assert_int(flashes[0]).is_greater_equal(1)
	assert_array(impacts).contains([target_on_bo])
	assert_int(_bo.combat.shots).is_equal(1)
	assert_int(_bo.combat.hits).is_equal(1)
	# No client took a hit itself: the targets fell by the server's health.
	assert_int(taken[0]).is_equal(0)


func test_ada_shoots_bo_and_both_screens_follow_the_server() -> void:
	await _start()
	var server_bo := _rig.server_body(_bo)
	var puppet_bo := _ada.remote_players.puppet_at(_bo.slot)
	_aim_point = func() -> Vector3: return puppet_bo.global_position + Vector3.UP * CHEST
	var taken := _count_client_hits()
	var seen: Array[Array] = []
	for shot in 3:
		_presses = [_rig.controllers[0].ticks + (5 if shot == 0 else 2)]
		var expected := server_bo.max_health - 34.0 * (shot + 1)
		var hurt := func() -> bool:
			var server_value := maxf(expected, 0.0)
			if server_bo.health != server_value:
				return false
			if expected <= 0.0:
				return _bo.player.is_dead() and puppet_bo.is_dead()
			return _bo.player.health == server_value and puppet_bo.health == server_value
		(
			assert_bool(await _rig.until(hurt, 120))
			. override_failure_message("shot %d" % shot)
			. is_true()
		)
		seen.append([server_bo.health, _bo.player.health, puppet_bo.health])
		await _rig.wait(20)
	prints("health (server, Bo's screen, Ada's screen):", seen)
	assert_bool(server_bo.is_dead()).is_true()
	assert_bool(_bo.player.ragdoll_body.is_limp()).is_true()
	assert_bool(puppet_bo.ragdoll_body.is_limp()).is_true()
	assert_int(taken[0]).is_equal(0)
	# Each screen's ragdoll is its own: no bone was sent.
	await _rig.wait(30)
	var own_hips := _bo.player.ragdoll_body.hips()
	var puppet_hips := puppet_bo.ragdoll_body.hips()
	prints("Bo's hips on his screen", own_hips, "and on Ada's", puppet_hips)
	assert_bool(own_hips.is_equal_approx(puppet_hips)).is_false()
	# The server gets him up where he died, and both screens stand him there.
	var up := func() -> bool:
		return not _bo.player.is_dead() and not puppet_bo.is_dead() and not server_bo.is_dead()
	assert_bool(await _rig.until(up, 180)).is_true()
	await _rig.wait(20)
	var spot := server_bo.global_position
	assert_vector(_bo.player.global_position).is_equal_approx(spot, Vector3.ONE * 0.05)
	assert_vector(puppet_bo.global_position).is_equal_approx(spot, Vector3.ONE * 0.05)
	assert_float(_bo.player.health).is_equal(_bo.player.max_health)
	assert_float(puppet_bo.health).is_equal(puppet_bo.max_health)


func test_a_spread_shot_leaves_the_puppet_the_way_the_server_fired_it() -> void:
	var pistol := load("res://gameplay/weapon/pistol.tres") as WeaponDef
	var spread := pistol.spread
	pistol.spread = 8.0
	pistol.first_shot_spread = 8.0
	await _start()
	var server_ada := _rig.server_body(_ada)
	var puppet := _bo.remote_players.puppet_at(_ada.slot)
	var board := _board(_ada, &"TargetC")
	_aim_point = func() -> Vector3: return board
	var server_shots: Array[Vector3] = []
	server_ada.weapon.fired.connect(
		func(_shot: Projectile) -> void: server_shots.append(server_ada.weapon.last_heading)
	)
	var puppet_shots: Array[Vector3] = []
	puppet.weapon.fired.connect(
		func(_shot: Projectile) -> void: puppet_shots.append(puppet.weapon.last_heading)
	)
	_presses = [_rig.controllers[0].ticks + 5, _rig.controllers[0].ticks + 40]
	var both := func() -> bool: return puppet_shots.size() == 2
	var arrived := await _rig.until(both, 180)
	pistol.spread = spread
	pistol.first_shot_spread = 0.0
	assert_bool(arrived).is_true()
	for index in 2:
		# The event carries the heading in steps of a 65536th of a turn.
		assert_vector(puppet_shots[index]).is_equal_approx(
			server_shots[index], Vector3.ONE * 0.0005
		)
	assert_bool(server_shots[0].is_equal_approx(server_shots[1])).is_false()


func test_at_200_ms_each_way_the_server_decides_what_a_shot_hit() -> void:
	await _start(0.2)
	var server_bo := _rig.server_body(_bo)
	var puppet_bo := _ada.remote_players.puppet_at(_bo.slot)
	_aim_point = func() -> Vector3: return puppet_bo.global_position + Vector3.UP * CHEST
	# Bo runs along +X across Ada's view; she fires at where her screen draws him.
	_rig.controllers[1].plan = func(_tick: int) -> PlayerCommand:
		var command := PlayerCommand.new()
		command.set_from_world(Vector3.RIGHT, Vector3.FORWARD)
		command.sprint = true
		return command
	_put(_ada, LANE_ADA_AT, PI)
	_put(_bo, LANE_START, PI)
	await _rig.wait(100)
	_presses = [_rig.controllers[0].ticks + 2]
	await _rig.wait(20)
	var drawn_behind := server_bo.global_position.x - puppet_bo.global_position.x
	await _rig.wait(100)
	assert_int(_rig.server.combat.shots).is_equal(1)
	prints("running at 200 ms: Ada's screen drew Bo", drawn_behind, "m behind the server")
	assert_float(drawn_behind).is_greater(1.0)
	assert_float(server_bo.health).is_equal(server_bo.max_health)
	assert_float(_bo.player.health).is_equal(server_bo.max_health)
	assert_float(puppet_bo.health).is_equal(server_bo.max_health)
	# He stops; once her screen has caught up, the same shot hits on every screen.
	_rig.controllers[1].plan = func(_tick: int) -> PlayerCommand: return PlayerCommand.new()
	await _rig.wait(90)
	_presses = [_rig.controllers[0].ticks + 2]
	var hurt := func() -> bool:
		return server_bo.health < server_bo.max_health and puppet_bo.health == server_bo.health
	assert_bool(await _rig.until(hurt, 150)).is_true()
	(
		assert_bool(
			await _rig.until(func() -> bool: return _bo.player.health == server_bo.health, 60)
		)
		. is_true()
	)


# --- Helpers ---


# Ada's controller: aim at the point, with the shot block from her eye, and press on the planned
# ticks.
func _ada_plan(tick: int) -> PlayerCommand:
	var command := PlayerCommand.new()
	if not _aim_point.is_valid():
		return command
	var body := _ada.player
	var eye := body.global_position + Vector3.UP * body.tuning.camera_height
	var angles := CommandCodec.direction_angles((_aim_point.call() as Vector3) - eye)
	command.yaw = angles.x
	command.pitch = angles.y
	command.aim = true
	command.has_shot = true
	command.origin = eye
	command.shot_yaw = angles.x
	command.shot_pitch = angles.y
	command.fire_pressed = _presses.has(tick)
	return command


func _put(client: NetClient, spot: Vector3, heading: float) -> void:
	_rig.server_body(client).teleport(spot, heading)
	client.player.teleport(spot, heading)


func _target(client: NetClient, target_name: StringName) -> Target:
	return _target_in(client.get_viewport() as SubViewport, target_name)


func _target_in(view: SubViewport, target_name: StringName) -> Target:
	for node in view.find_children(String(target_name), "", true, false):
		if node is Target:
			return node
	return null


func _board(client: NetClient, target_name: StringName) -> Vector3:
	return _target(client, target_name).global_position + Vector3.UP * BOARD_RISE


# Counts every hit a client's own `Health` takes through `apply` (a cosmetic shot that hit), on
# every client: it must stay zero.
func _count_client_hits() -> Array:
	var taken := [0]
	for view in _rig.views:
		for node in view.find_children("Health", "", true, false):
			if node is Health:
				(node as Health).hit_taken.connect(func(_hit: HitRecord) -> void: taken[0] += 1)
	return taken
