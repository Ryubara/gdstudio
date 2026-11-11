# Lag compensation for shots on the AI (gdstudio #1198): a game server and two predicting clients
# over a real socket on 127.0.0.1 at 150 ms each way (`OnlineRig`). The AI runs on the server and
# each client draws it behind (the playout buffer and a send's glide), so the server meets a
# player's shot with each character where the shooter's screen drew it (`AiHitHistory`,
# `ShotRewind`): a shot Ada's screen draws on a running guard's chest hits on the server and on
# Bo's screen, and one led to where the server will have it misses; with the rewind off it is the
# other way round. The guard's brain, senses and navigation are never rewound: only the volume
# the shot meets.
extends GdUnitTestSuite

## Open ground west of the push cubes (`test_net_ai_online.gd`'s), facing north.
const GROUND := Vector3(-9.0, 0.3, 19.0)
const FACING_NORTH := PI
## The guard's lane: it runs along +X, 6 m in front of Ada.
const LANE_START := Vector3(-14.0, 0.3, 13.0)
## Where Ada aims, above the drawn guard's feet.
const CHEST := 1.2
## The one-way delay of each client's link (a 300 ms round trip).
const DELAY := 0.15
## The pistol's round, m/s (`WeaponDef.projectile_speed`).
const ROUND_SPEED := 45.0
## About the round's flight to the lane (6 m at 45 m/s) and a server step's wait for the command.
const LEAD_FLIGHT := 0.15
## How far the drawn guard may be from the history at the tick a shot is met at: a tick of its
## run (about 6 cm) on average, a send's at worst (the clock's pull moves the drawn tick).
const MAX_MEAN_GAP := 0.1
const MAX_WORST_GAP := 0.2

var _rig: OnlineRig
var _ada: NetClient
var _bo: NetClient
var _aim_point := Callable()
var _presses: Array[int] = []


func after_test() -> void:
	_rig = null
	_ada = null
	_bo = null
	_aim_point = Callable()
	_presses = []


func test_at_150_ms_each_way_a_shot_drawn_on_a_running_guards_chest_hits() -> void:
	var runner := await _run_guard()
	var bo_hits := [0]
	_bo.ai_replica.puppet_of(_id_of(runner)).hit_received.connect(
		func(_record: HitRecord) -> void: bo_hits[0] += 1
	)
	assert_bool(await _shoot(runner, _drawn_chest.bind(runner))).is_true()
	assert_bool(await _rig.until(func() -> bool: return bo_hits[0] > 0, 60)).is_true()


func test_with_the_rewind_off_the_shot_drawn_on_the_chest_misses() -> void:
	var runner := await _run_guard(0.0)
	assert_bool(await _shoot(runner, _drawn_chest.bind(runner))).is_false()


func test_at_150_ms_each_way_a_shot_led_to_where_the_server_will_have_the_guard_misses() -> void:
	var runner := await _run_guard()
	assert_bool(await _shoot(runner, _server_chest.bind(runner))).is_false()


func test_with_the_rewind_off_the_shot_led_to_the_server_hits() -> void:
	var runner := await _run_guard(0.0)
	assert_bool(await _shoot(runner, _server_chest.bind(runner))).is_true()


func test_the_drawn_guard_is_where_the_history_has_it_at_the_shots_tick() -> void:
	var runner := await _run_guard()
	var id := _id_of(runner)
	var puppet := _ada.ai_replica.puppet_of(id)
	var history := _rig.server.ai_history
	var server_ada := _rig.server_body(_ada)
	var worst := 0.0
	var total := 0.0
	var frames := 0
	for _frame in 60:
		await get_tree().physics_frame
		var command := PlayerCommand.new()
		command.has_shot = true
		command.view_tick = _ada.view_tick() & 0xFFFF
		var rewind := _rig.server.rewind_for(server_ada, command)
		var from := puppet.global_position + Vector3(0.0, 1.0, 3.0)
		var shot := rewind.for_shot(from, Vector3.FORWARD, 10.0)
		var tick := shot.tick_of(runner)
		var gap := _flat(history.position_at(id, tick) - puppet.global_position)
		worst = maxf(worst, gap)
		total += gap
		frames += 1
	prints("drawn guard against the history: mean", total / frames, "worst", worst)
	assert_float(total / frames).is_less(MAX_MEAN_GAP)
	assert_float(worst).is_less(MAX_WORST_GAP)


# --- Helpers ---


# Ada fires once at `aim` (a point she aims at each tick) at the running guard; true when the
# server hit it.
func _shoot(runner: AiCharacter, aim: Callable) -> bool:
	var puppet := _ada.ai_replica.puppet_of(_id_of(runner))
	var health := Health.of(runner)
	var full := health.value
	_aim_point = aim
	_presses = [_rig.controllers[0].ticks + 2]
	await _rig.wait(20)
	var drawn_behind := runner.global_position.x - puppet.global_position.x
	await _rig.wait(60)
	prints(
		(
			"rewind %.2f s: drawn %.2f m behind the server, hit %s"
			% [_rig.server.ai_rewind_seconds, drawn_behind, health.value < full]
		)
	)
	assert_int(_rig.server.combat.shots).is_equal(1)
	assert_float(drawn_behind).is_greater(0.8)
	# The lane was clear: it ran the whole time.
	assert_float(runner.global_position.x - LANE_START.x).is_greater(6.0)
	return health.value < full


# The drawn guard's chest, led by the round's flight as a player leads a runner on the screen.
func _drawn_chest(runner: AiCharacter) -> Vector3:
	var puppet := _ada.ai_replica.puppet_of(_id_of(runner))
	var chest := puppet.global_position + Vector3.UP * CHEST
	var flight := _ada.player.global_position.distance_to(chest) / ROUND_SPEED
	return chest + puppet.velocity * flight


# Where the server will have the guard's chest when the command and the round get there (a test
# may read the server): with no rewind that hits; met where Ada's screen drew the guard, it passes
# in front of it.
func _server_chest(runner: AiCharacter) -> Vector3:
	return runner.global_position + runner.velocity * (DELAY + LEAD_FLIGHT) + Vector3.UP * CHEST


# Starts the rig at `DELAY` each way (the server meeting shots up to `rewind_seconds` back), seats
# Ada facing the lane, and sends a guard running across it; returns the guard once both screens
# draw it mid-lane.
func _run_guard(rewind_seconds := 0.6) -> AiCharacter:
	_rig = auto_free(OnlineRig.new(false))
	_rig.delay = DELAY
	_rig.prepare_server = func(server: NetServer) -> void: server.ai_rewind_seconds = rewind_seconds
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_ada = await _rig.join("Ada", 600)
	_bo = await _rig.join("Bo", 600)
	assert_object(_ada).is_not_null()
	assert_object(_bo).is_not_null()
	_put(_ada, GROUND, FACING_NORTH)
	_put(_bo, GROUND + Vector3(4.0, 0.0, 0.0), FACING_NORTH)
	_rig.controllers[0].plan = _ada_plan
	var runner := AiNetStage.walker(LANE_START, Vector3.RIGHT, 1.0)
	AiNetStage.server_map(_rig.server).add_child(runner)
	var drawn := func() -> bool:
		var id := _id_of(runner)
		for client in [_ada, _bo]:
			var puppet := (client as NetClient).ai_replica.puppet_of(id)
			if puppet == null or not puppet.visible:
				return false
		return true
	assert_bool(await _rig.until(drawn, 120)).is_true()
	# Up to speed and in front of Ada.
	var mid := func() -> bool: return runner.global_position.x > LANE_START.x + 3.0
	assert_bool(await _rig.until(mid, 240)).is_true()
	return runner


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


func _put(client: NetClient, spot: Vector3, facing: float) -> void:
	_rig.server_body(client).teleport(spot, facing)
	client.player.teleport(spot, facing)


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


static func _id_of(walker: AiCharacter) -> int:
	return int(walker.get_meta(NetHits.AI_META, -1))
