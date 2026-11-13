# A body let go from a jog or a sprint slows over its stop clip (gdstudio #1415): it covers the
# ground the clip's feet cover (the clip's travel in `clips.json`, times the body's leg length over
# the reference's) by the stop decelerations of `CharacterTuning`, the clip plays along that ground
# to its end, and a planted foot keeps its place in the world while it does. The body and its tree
# are stepped by hand, by commands.
#
# Before the fix the body stopped by the one `deceleration` (36 m/s²) in a tenth of the clip's
# travel and the clip played the rest in place, its feet sliding back under a body at rest.
extends GdUnitTestSuite

## How far the ground covered over a stop may be from the clip's travel, as a share of it.
const TRAVEL_SHARE := 0.04
## The furthest a planted foot may move over the floor in one contact of a stop, in metres.
const SLIDE := 0.010
## The share of a contact its foot takes to roll down onto the floor, left out of the measure.
const ROLL_ON := 0.25
## The longest a stop may take, in seconds.
const LONGEST := 4.0
## Below this ground speed the body is at rest (m/s).
const AT_REST := 0.005
## The runs: a name, the stick's push forward, the walk button, the sprint button, the stop
## clip it plays (the foot that lands next when the stick is let go) and the seconds it runs before
## (a steady speed, and half a cycle more for the other foot).
const RUNS: Array[Array] = [
	["walk", 1.0, true, false, "gds/Walk_Stop_L", 1.2],
	["jog", 1.0, false, false, "gds/Jog_Stop_L", 1.2],
	["jog", 1.0, false, false, "gds/Jog_Stop_R", 1.2 + 0.3333],
	["sprint", 1.0, false, true, "gds/Sprint_Stop_L", 1.2],
	["sprint", 1.0, false, true, "gds/Sprint_Stop_R", 1.2 + 0.3],
]

var _arena: PlayArena
var _player: Player
var _animation: CharacterAnimation


func before_test() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	_player.tuning = (
		(load("res://gameplay/player/player_tuning.tres") as CharacterTuning).duplicate()
	)
	_animation = _player.get_node("Animation")
	CommandDriver.take(_player)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_animation.set_throttled(true)


func after_test() -> void:
	InputSim.release_all()


func _command(run: Array) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.yaw = 0.0
	command.move = Vector2(0.0, run[1])
	command.walk = run[2]
	command.sprint = run[3]
	return command


# Runs `run` until steady, lets go and steps until the body is at rest. Returns what the stop did:
# the clip it played, the ground covered from letting go, the clip's travel for this body, the
# clip's time when the body came to rest and its travel's end, and the worst slide of a planted
# foot of the clip.
func _stop(run: Array) -> Dictionary:
	var skeleton := (_player.get_node("Model") as CharacterModel).skeleton()
	var balls := {"l": skeleton.find_bone(&"ball_l"), "r": skeleton.find_bone(&"ball_r")}
	var since := {"l": Vector3.INF, "r": Vector3.INF}
	var transitions := _animation.gait.transitions
	var step := CommandDriver.tick_seconds()
	var going := _command(run)
	_player.teleport(Vector3.ZERO, PI)
	for tick in roundi(run[5] / step):
		await get_tree().physics_frame
		_player.step(going, step)
		_animation.advance(step)
	var from := _player.global_position
	var forward := Vector3(_player.velocity.x, 0.0, _player.velocity.z).normalized()
	var let_go := PlayerCommand.new()
	let_go.yaw = 0.0
	var found := {"clip": &"", "slide": 0.0, "clip_time": 0.0, "speed": _player.ground_speed()}
	for tick in roundi(LONGEST / step):
		await get_tree().physics_frame
		_player.step(let_go, step)
		_animation.advance(step)
		var clip := transitions.clip
		if clip != &"" and found.clip == &"":
			found.clip = clip
		if clip == &"" or clip != found.clip:
			if _player.ground_speed() < AT_REST:
				break
			continue
		found.clip_time = transitions.time()
		var record := GaitClips.record(clip)
		var frame := transitions.time() * GaitClips.FPS
		for side: String in balls:
			var down := false
			for contact: Array in record.get("contacts", {}).get(side, []):
				var start: float = contact[0] + ROLL_ON * (contact[1] - contact[0])
				down = down or (frame >= start and frame <= contact[1])
			var place := (
				skeleton.global_transform * skeleton.get_bone_global_pose(balls[side]).origin
			)
			if not down:
				since[side] = Vector3.INF
				continue
			if since[side] == Vector3.INF:
				since[side] = place
			var moved: Vector3 = place - since[side]
			var slid := Vector2(moved.x, moved.z).length()
			if slid > found.slide:
				found.where = "the %s foot at frame %.1f" % [side, frame]
			found.slide = maxf(found.slide, slid)
		if _player.ground_speed() < AT_REST:
			break
	found.covered = (_player.global_position - from).dot(forward)
	found.leg = GaitClips.leg_scale(skeleton, _player)
	var travel: Array = GaitClips.record(found.clip).get("travel", [[0, 0.0]])
	found.travel = float(travel[-1][1]) * found.leg
	found.clip_travel = GaitClips.travel_at(found.clip, found.clip_time) * found.leg
	return found


func _line(run: Array, found: Dictionary) -> String:
	return (
		(
			"%s stop from %.2f m/s: %s, covered %.3f m of the clip's %.3f m, the clip at %.3f m"
			+ " of it when the body came to rest, a planted foot slid %.1f mm (%s)"
		)
		% [
			run[0],
			found.speed,
			found.clip,
			found.covered,
			found.travel,
			found.clip_travel,
			found.slide * 1000.0,
			found.get("where", "no contact"),
		]
	)


func test_a_jog_and_a_sprint_stop_cover_the_clip_s_travel() -> void:
	var failures: Array[String] = []
	for run in RUNS:
		var found := await _stop(run)
		var line := _line(run, found)
		print(line)
		if found.clip != StringName(run[4]):
			failures.append("no %s clip: %s" % [run[4], line])
			continue
		if absf(found.covered - found.travel) > found.travel * TRAVEL_SHARE:
			failures.append(line)
	assert_array(failures).override_failure_message("\n".join(failures)).is_empty()


func test_the_stop_clip_plays_along_the_ground_and_its_feet_hold_the_floor() -> void:
	var failures: Array[String] = []
	for run in RUNS:
		var found := await _stop(run)
		var line := _line(run, found)
		print(line)
		# At rest, the clip has played (by the ground covered) to where its own travel ends.
		var short: float = found.travel - found.clip_travel
		if short > found.travel * TRAVEL_SHARE or found.slide > SLIDE:
			failures.append(line)
	assert_array(failures).override_failure_message("\n".join(failures)).is_empty()


func test_the_stop_decelerations_come_from_the_tuning_live() -> void:
	# Each gait's speed band slows by its own setting: halving the sprint's doubles the ground the
	# sprint's band takes. Read by name, so the suite loads where the setting is missing.
	var tuning := _player.tuning
	var setting := &"sprint_stop_deceleration"
	assert_bool(setting in tuning).override_failure_message("no %s" % setting).is_true()
	if not setting in tuning:
		return
	var first := await _stop(RUNS[3])
	var rate: float = tuning.get(setting)
	tuning.set(setting, rate * 0.5)
	var second := await _stop(RUNS[3])
	var band := (pow(tuning.sprint_speed, 2.0) - pow(tuning.run_speed, 2.0)) / (2.0 * rate)
	assert_float(second.covered - first.covered).is_equal_approx(band, 0.06)
