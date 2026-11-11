# The map's pushed props and shooting targets in an online game (gdstudio #1073): a game server and
# two predicting clients, each with a map of its own, joined over a real socket on 127.0.0.1
# (`OnlineRig`). Ada pushes a 5 kg crate and a 60 kg cube with her commands, as a player does: the
# server's body pushes the server's prop, and on Bo's screen each prop is where the server has it
# at the same tick; a late joiner sees it there at once; Ada's own body is corrected a little while
# she pushes (logged, the worst pinned under 0.5 m), also at 100 ms each way. A target falls and
# stands on every screen when the server's does, a late joiner sees it down.
extends GdUnitTestSuite

## `PushCubes/PushCube2`, moved on every peer to open ground west of the push cubes and made a
## 5 kg crate with no push speed of its own (the character's push gives it its share).
const CRATE := "PushCube2"
const CRATE_AT := Vector3(-9.0, 0.5, 19.0)
const CRATE_WEIGHT := 5.0
## `PushCubes/PushCube1`: 60 kg, pushed at its own 1.2 m/s.
const CUBE := "PushCube1"
## Ada starts this far south of a prop's centre (its half, a gap and her capsule), facing north.
const BEHIND := 1.3
const FACING_NORTH := PI
const PUSH_TICKS := 150
const SETTLE_TICKS := 150
## The worst correction a push may cost the pusher, metres (the issue's pin).
const MAX_PUSH_ERROR := 0.5
## How far Bo's copy may be from the server's prop at the same tick while it moves, and at rest.
const MAX_MOVING_GAP := 0.35
const MAX_RESTING_GAP := 0.02

var _rig: OnlineRig
var _ada: NetClient
var _bo: NetClient


func after_test() -> void:
	_rig = null
	_ada = null
	_bo = null


func test_a_5_kg_crate_ada_pushes_moves_on_bos_screen_where_the_server_has_it() -> void:
	await _start()
	var run := await _push(CRATE)
	assert_float(run.moved).is_greater(1.0)
	assert_float(run.bo_moved).is_greater(1.0)
	assert_float(run.bo_worst).is_less(MAX_MOVING_GAP)
	assert_float(run.bo_rest_gap).is_less(MAX_RESTING_GAP)
	assert_float(run.ada_worst).is_less(MAX_PUSH_ERROR)


func test_a_60_kg_cube_ada_pushes_moves_on_bos_screen_where_the_server_has_it() -> void:
	await _start()
	var run := await _push(CUBE)
	assert_float(run.moved).is_greater(1.0)
	assert_float(run.bo_moved).is_greater(1.0)
	assert_float(run.bo_worst).is_less(MAX_MOVING_GAP)
	assert_float(run.bo_rest_gap).is_less(MAX_RESTING_GAP)
	assert_float(run.ada_worst).is_less(MAX_PUSH_ERROR)


func test_pushing_at_100_ms_each_way_costs_the_pusher_less_than_half_a_metre() -> void:
	await _start(0.1, 0.01)
	for prop_name in [CRATE, CUBE]:
		var run := await _push(prop_name)
		assert_float(run.moved).is_greater(1.0)
		assert_float(run.ada_worst).is_less(MAX_PUSH_ERROR)
		assert_float(run.bo_rest_gap).is_less(MAX_RESTING_GAP)


func test_a_player_who_joins_late_sees_the_pushed_crate_where_it_is_at_once() -> void:
	await _start()
	await _push(CRATE)
	var server_crate := _prop(_rig.server_view, CRATE)
	var cy := await _rig.join("Cy")
	assert_object(cy).is_not_null()
	# The first frame after the WELCOME: where the server has it, not at the map's start.
	var cys_crate := _prop(_rig.views[2], CRATE)
	assert_float(cys_crate.global_position.distance_to(server_crate.global_position)).is_less(
		MAX_RESTING_GAP
	)
	assert_float(cys_crate.global_position.distance_to(CRATE_AT)).is_greater(1.0)


func test_a_prop_that_falls_out_of_the_map_is_back_at_its_start_on_every_screen() -> void:
	await _start()
	var server_crate := _prop(_rig.server_view, CRATE)
	var bos_crate := _prop(_rig.views[1], CRATE)
	var jumps := [0]
	bos_crate.returned.connect(func() -> void: jumps[0] += 1)
	server_crate.global_position = Vector3(-9.0, server_crate.fall_limit - 5.0, 19.0)
	var home := func() -> bool:
		return (
			jumps[0] > 0
			and bos_crate.global_position.distance_to(CRATE_AT) < MAX_RESTING_GAP
			and server_crate.global_position.distance_to(CRATE_AT) < MAX_RESTING_GAP
		)
	assert_bool(await _rig.until(home, 120)).is_true()


func test_a_target_ada_shoots_falls_on_bos_screen_and_stands_when_the_server_says() -> void:
	await _start()
	var server_target := _target(_rig.server_view, "TargetB")
	var bos_target := _target(_rig.views[1], "TargetB")
	# Bo's copy would stand after half a second by its own clock; the server's stands after two.
	server_target.reset_time = 2.0
	bos_target.reset_time = 0.5
	_put(_ada, Vector3(-3.0, 0.3, -10.0), FACING_NORTH)
	await _rig.wait(20)
	var board := server_target.global_position + Vector3.UP * 0.9
	var presses: Array[int] = [_rig.controllers[0].ticks + 20]
	_rig.controllers[0].plan = func(tick: int) -> PlayerCommand:
		return _aimed(_ada.player, board, presses.has(tick))
	assert_bool(await _rig.until(bos_target.is_down, 180)).is_true()
	assert_bool(server_target.is_down()).is_true()
	await _rig.wait(60)
	assert_bool(bos_target.is_down()).is_true()
	assert_bool(await _rig.until(func() -> bool: return not server_target.is_down(), 120)).is_true()
	assert_bool(await _rig.until(func() -> bool: return not bos_target.is_down(), 60)).is_true()


func test_a_target_the_server_knocks_down_is_down_everywhere_and_for_a_late_joiner() -> void:
	await _start()
	var server_target := _target(_rig.server_view, "TargetC")
	server_target.reset_time = 0.0
	# No shot: the server's own rule (an AI's hit, a script) knocks it down.
	Health.of(server_target).kill()
	var bos_target := _target(_rig.views[1], "TargetC")
	assert_bool(await _rig.until(bos_target.is_down, 60)).is_true()
	var cy := await _rig.join("Cy")
	assert_object(cy).is_not_null()
	assert_bool(_target(_rig.views[2], "TargetC").is_down()).is_true()
	assert_bool(_target(_rig.views[2], "TargetB").is_down()).is_false()


# --- Helpers ---


func _start(delay := 0.0, jitter := 0.0) -> void:
	_rig = auto_free(OnlineRig.new(false))
	_rig.delay = delay
	_rig.jitter = jitter
	_rig.prepare_server = func(server: Node) -> void: _make_crate(server)
	_rig.prepare_arena = func(arena: Node) -> void: _make_crate(arena)
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_ada = await _rig.join("Ada", 600)
	_bo = await _rig.join("Bo", 600)
	assert_object(_ada).is_not_null()
	assert_object(_bo).is_not_null()
	await _rig.wait(30)


# The same 5 kg crate in every peer's map (a map with one, as a game would make it).
static func _make_crate(scene: Node) -> void:
	var crate := scene.find_child(CRATE, true, false) as PhysicsProp
	crate.position = CRATE_AT
	crate.weight = CRATE_WEIGHT
	crate.push_speed = 0.0


# Ada walks north into the prop for `PUSH_TICKS`, then stands; answers what was measured.
func _push(prop_name: String) -> Dictionary:
	var server_prop := _prop(_rig.server_view, prop_name)
	var bos_prop := _prop(_rig.views[1], prop_name)
	var start := server_prop.global_position
	var spot := Vector3(start.x, 0.0, start.z + BEHIND)
	_put(_ada, spot, FACING_NORTH)
	_rig.controllers[0].plan = func(_tick: int) -> PlayerCommand: return PlayerCommand.new()
	await _rig.wait(30)
	var reconciler := _ada.reconciler
	var corrections := reconciler.corrections
	reconciler.worst_error = 0.0
	var walking := [true]
	_rig.controllers[0].plan = func(_tick: int) -> PlayerCommand:
		var command := PlayerCommand.new()
		command.yaw = 0.0
		command.move = Vector2(0.0, 1.0) if walking[0] else Vector2.ZERO
		return command
	var server_at := {}
	var bo_at: Array[Array] = []
	var bo_start := bos_prop.global_position
	for index in PUSH_TICKS + SETTLE_TICKS:
		if index == PUSH_TICKS:
			walking[0] = false
		await get_tree().physics_frame
		server_at[_rig.server.server_tick] = server_prop.global_position
		bo_at.append([_bo.seq, bos_prop.global_position])
	var bo_worst := 0.0
	for entry in bo_at:
		if server_at.has(entry[0]):
			bo_worst = maxf(bo_worst, (entry[1] as Vector3).distance_to(server_at[entry[0]]))
	var run := {
		"moved": server_prop.global_position.distance_to(start),
		"bo_moved": bos_prop.global_position.distance_to(bo_start),
		"bo_worst": bo_worst,
		"bo_rest_gap": bos_prop.global_position.distance_to(server_prop.global_position),
		"ada_worst": reconciler.worst_error,
		"corrections": reconciler.corrections - corrections,
	}
	prints(
		(
			"push %s (%.0f kg), %.0f ms each way: moved %.2f m (Bo saw %.2f m), %d corrections,"
			% [
				prop_name,
				server_prop.mass,
				_rig.delay * 1000.0,
				run.moved,
				run.bo_moved,
				run.corrections
			]
		),
		(
			"worst error %.3f m; Bo's copy worst %.3f m off the server's at a tick, %.4f m at rest"
			% [run.ada_worst, run.bo_worst, run.bo_rest_gap]
		)
	)
	return run


# A command that aims at `point` from the body's eye with a shot block, pressing fire if `press`.
static func _aimed(body: Character, point: Vector3, press: bool) -> PlayerCommand:
	var command := PlayerCommand.new()
	var eye := body.global_position + Vector3.UP * body.tuning.camera_height
	var angles := CommandCodec.direction_angles(point - eye)
	command.yaw = angles.x
	command.pitch = angles.y
	command.aim = true
	command.has_shot = true
	command.origin = eye
	command.shot_yaw = angles.x
	command.shot_pitch = angles.y
	command.fire_pressed = press
	return command


func _put(client: NetClient, spot: Vector3, facing: float) -> void:
	_rig.server_body(client).teleport(spot, facing)
	client.player.teleport(spot, facing)


static func _prop(view: Node, prop_name: String) -> PhysicsProp:
	return view.find_child(prop_name, true, false) as PhysicsProp


static func _target(view: Node, target_name: String) -> Target:
	return view.find_child(target_name, true, false) as Target
