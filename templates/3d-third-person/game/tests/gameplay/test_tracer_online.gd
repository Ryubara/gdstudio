# The hitscan tracer online (gdstudio #1270): a game server and two predicting clients over a real
# socket (`OnlineRig`), the shared pistol hitscan with a tracer. Ada fires at a target with her
# command: her own screen draws a streak from her muzzle, Bo's screen draws one from her puppet's
# muzzle along the SHOT's heading and ends it at the HIT's point, the server draws none, and the
# shot still costs Bo only its SHOT and HIT (nothing more on the wire).
extends GdUnitTestSuite

const PISTOL := "res://gameplay/weapon/pistol.tres"
const PISTOL_TRACER := "res://gameplay/weapon/pistol_tracer.tres"
## Where Ada stands on the open ground in front of the targets (`TargetB` at x = -3), Bo beside.
const ADA_AT := Vector3(-3.0, 0.3, -10.0)
const BO_AT := Vector3(1.0, 0.3, -10.0)
const BOARD_RISE := 0.9

var _rig: OnlineRig
var _ada: NetClient
var _bo: NetClient
var _aim_point := Vector3.ZERO
var _press_at := -1


func after_test() -> void:
	var pistol := load(PISTOL) as WeaponDef
	pistol.hitscan = false
	pistol.tracer = null
	_rig = null
	_ada = null
	_bo = null
	_press_at = -1


func test_each_screen_draws_the_tracer_and_the_wire_carries_only_shot_and_hit() -> void:
	var pistol := load(PISTOL) as WeaponDef
	pistol.hitscan = true
	pistol.tracer = load(PISTOL_TRACER) as TracerDef
	_rig = auto_free(OnlineRig.new(false))
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_ada = await _rig.join("Ada", 600)
	_bo = await _rig.join("Bo", 600)
	_rig.server_body(_ada).teleport(ADA_AT, PI)
	_ada.player.teleport(ADA_AT, PI)
	_rig.server_body(_bo).teleport(BO_AT, PI)
	_bo.player.teleport(BO_AT, PI)
	_rig.controllers[0].plan = _ada_plan
	await _rig.wait(40)
	var target := _target_in(_bo.get_viewport() as SubViewport, &"TargetB")
	_aim_point = target.global_position + Vector3.UP * BOARD_RISE
	var on_ada := TracerPool.find(_ada)
	var on_bo := TracerPool.find(_bo)
	var on_server := TracerPool.find(_rig.server)
	assert_object(on_ada).is_not_null()
	assert_object(on_bo).is_not_same(on_ada)
	var drawn := {"ada": [], "bo": [], "server": []}
	on_ada.tracer_drawn.connect(func(f: Vector3, t: Vector3) -> void: drawn["ada"].append([f, t]))
	on_bo.tracer_drawn.connect(func(f: Vector3, t: Vector3) -> void: drawn["bo"].append([f, t]))
	if on_server != null and on_server != on_ada and on_server != on_bo:
		on_server.tracer_drawn.connect(
			func(f: Vector3, t: Vector3) -> void: drawn["server"].append([f, t])
		)
	var puppet := _bo.remote_players.puppet_at(_ada.slot)
	var ended := {"end": Vector3.INF, "hit": Vector3.INF}
	_bo.combat.hit_played.connect(
		func(event: NetEvent, _collider: Object) -> void: ended["hit"] = event.point
	)
	var event_bytes := [0]
	var kinds: Array[int] = []
	_bo.link.packet_received.connect(
		func(data: PackedByteArray) -> void:
			if NetWire.type_of(data) != NetWire.Type.TICK:
				return
			var tick := SnapshotCodec.read_tick(data)
			if tick == null:
				return
			for event in tick.events:
				if event.kind == NetEvent.Kind.SHOT or event.kind == NetEvent.Kind.HIT:
					event_bytes[0] += SnapshotCodec.event_size(event)
					kinds.append(event.kind)
	)
	_press_at = _rig.controllers[0].ticks + 5
	# The server sends a hitscan shot's HIT before its SHOT, in the same TICK: Bo's streak is drawn
	# after the HIT and ends there at once (read the frame it shows, before it fades).
	var heard := func() -> bool:
		if _bo.combat.hits < 1 or drawn["bo"].is_empty():
			return false
		if on_bo.active_count() > 0:
			ended["end"] = on_bo.line_at(on_bo.active_count() - 1)[1]
		return true
	assert_bool(await _rig.until(heard, 180)).is_true()
	prints("tracers drawn:", drawn, "ended", ended)
	assert_int(drawn["ada"].size()).is_equal(1)
	assert_int(drawn["bo"].size()).is_equal(1)
	assert_int(drawn["server"].size()).is_equal(0)
	# Bo's streak leaves the puppet's muzzle and ends at the server's point.
	var puppet_muzzle := puppet.weapon.muzzle.global_position
	assert_float((drawn["bo"][0][0] as Vector3).distance_to(puppet_muzzle)).is_less(0.6)
	assert_vector(ended["end"]).is_equal_approx(ended["hit"], Vector3.ONE * 0.01)
	# Nothing more on the wire: the shot is its SHOT and its HIT.
	assert_int(event_bytes[0]).is_equal(30)
	assert_array(kinds).contains_exactly_in_any_order([NetEvent.Kind.SHOT, NetEvent.Kind.HIT])


func _ada_plan(tick: int) -> PlayerCommand:
	var command := PlayerCommand.new()
	if _aim_point == Vector3.ZERO:
		return command
	var body := _ada.player
	var eye := body.global_position + Vector3.UP * body.tuning.camera_height
	var angles := CommandCodec.direction_angles(_aim_point - eye)
	command.yaw = angles.x
	command.pitch = angles.y
	command.aim = true
	command.has_shot = true
	command.origin = eye
	command.shot_yaw = angles.x
	command.shot_pitch = angles.y
	command.fire_pressed = tick == _press_at
	return command


func _target_in(view: SubViewport, target_name: StringName) -> Target:
	for node in view.find_children(String(target_name), "", true, false):
		if node is Target:
			return node
	return null
