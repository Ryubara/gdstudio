# The gait's per-frame shortcuts (gdstudio #1569): each skips or packs work whose result is the
# same, and each is held here against the work it replaced. The travel curves are read packed and
# by halves (`GaitClips.time_at_travel`), the crouch space is not set while nothing draws it
# (`GaitBlend.set_undrawn` off), and a moving body that goes about its way asks for no turn from a
# dot product (`GaitTransitions._pick_moving`).
extends GdUnitTestSuite

const TUNING := preload("res://gameplay/player/player_tuning.tres")
const TICKS := 260
## How far apart two drawn bones may be: a place (m) and a turn (radians), as
## `test_helper_tracks.gd` reads two bodies side by side.
const PLACE := 1e-5
const TURN := 1e-5

var _arena: PlayArena


func before() -> void:
	# The first player of a run draws its first frames a little apart from the next one: with both
	# setting every space the first pair read 0.12 mm apart at an upper arm (0.07 at the pelvis,
	# dying away in 16 ticks) and every later pair 0. One made and dropped first.
	var arena := PlayArena.new()
	add_child(arena)
	arena.add_player(Vector3.ZERO)
	for _frame in 3:
		await get_tree().physics_frame
	arena.queue_free()


func before_test() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)


# The travel curve read as it was before #1569: the record's nested arrays, point by point.
static func _old_time_at_travel(clip: StringName, distance: float) -> float:
	var curve: Array = GaitClips.record(clip).get("travel", [])
	if curve.size() < 2 or is_zero_approx(curve[-1][1] - curve[0][1]):
		return -1.0
	if distance >= curve[-1][1] - GaitClips.REST_TRAVEL:
		return _old_travel_end(clip)
	for index in range(curve.size() - 1):
		var a: Array = curve[index]
		var b: Array = curve[index + 1]
		if distance <= b[1] or index == curve.size() - 2:
			var share := clampf((distance - a[1]) / maxf(b[1] - a[1], 0.0001), 0.0, 1.0)
			return lerpf(a[0], b[0], share) / GaitClips.FPS
	return float(curve[-1][0]) / GaitClips.FPS


static func _old_travel_end(clip: StringName) -> float:
	var curve: Array = GaitClips.record(clip).get("travel", [])
	if curve.is_empty():
		return 0.0
	for point: Array in curve:
		if point[1] >= curve[-1][1] - GaitClips.REST_TRAVEL:
			return float(point[0]) / GaitClips.FPS
	return float(curve[-1][0]) / GaitClips.FPS


func test_the_packed_travel_reads_as_the_record() -> void:
	var data: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/animation/own/locomotion.json")
	)
	var clips: Dictionary = (data as Dictionary).get("clips", {})
	var read := 0
	for clip_name: String in clips:
		var clip := StringName("gds/" + clip_name)
		var curve: Array = GaitClips.record(clip).get("travel", [])
		assert_float(GaitClips.travel_end(clip)).is_equal(_old_travel_end(clip))
		if curve.size() < 2:
			continue
		var low: float = curve[0][1] - 0.1
		var high: float = curve[-1][1] + 0.1
		for step in 401:
			var distance := lerpf(low, high, step / 400.0)
			var now := GaitClips.time_at_travel(clip, distance)
			var was := _old_time_at_travel(clip, distance)
			(
				assert_float(now)
				. override_failure_message("%s at %.4f m: %f, was %f" % [clip, distance, now, was])
				. is_equal(was)
			)
			read += 1
		# On each point exactly, where a lower bound and a first match could part.
		for point: Array in curve:
			assert_float(GaitClips.time_at_travel(clip, point[1])).is_equal(
				_old_time_at_travel(clip, point[1])
			)
	assert_int(read).is_greater(4000)


func test_a_curve_that_goes_back_is_read_point_by_point() -> void:
	var clip := &"gds/Test_Travel_Back"
	GaitClips.register(
		clip,
		{"travel": [[0, 0.0, 0.0], [5, 0.4, 0.0], [10, 0.3, 0.0], [15, 0.9, 0.0], [20, 1.0, 0.0]]}
	)
	for step in 121:
		var distance := step / 100.0
		assert_float(GaitClips.time_at_travel(clip, distance)).is_equal(
			_old_time_at_travel(clip, distance)
		)
	GaitClips.forget(clip)
	assert_float(GaitClips.time_at_travel(clip, 0.5)).is_equal(-1.0)


func _player(spot: Vector3) -> Player:
	var body := _arena.add_player(spot)
	body.tuning = (TUNING as CharacterTuning).duplicate()
	body.tuning.turn_root_motion = false
	CommandDriver.take(body)
	return body


func _skeleton(body: Node) -> Skeleton3D:
	return body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D


# A jog, a crouched walk and a stand, a sprint, a stop, a crouch from rest, a stand and a jog
# that turns about: the crouch space set and left, the stop, the start and the reversal.
func _command(tick: int) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.move = Vector2(0.0, 1.0)
	if tick < 40:
		pass
	elif tick < 90:
		command.crouch = true
	elif tick < 140:
		command.sprint = tick >= 100
	elif tick < 175:
		command.move = Vector2.ZERO
	elif tick < 205:
		command.move = Vector2.ZERO
		command.crouch = true
	elif tick < 220:
		command.move = Vector2.ZERO
	else:
		command.yaw = PI if tick >= 240 else 0.0
	return command


static func _turn(a: Basis, b: Basis) -> float:
	var d := a.get_rotation_quaternion().inverse() * b.get_rotation_quaternion()
	return 2.0 * atan2(Vector3(d.x, d.y, d.z).length(), absf(d.w))


func _record(skeleton: Skeleton3D, into: Array) -> Callable:
	var keep := func() -> void:
		var frame: Array[Transform3D] = []
		for bone in skeleton.get_bone_count():
			frame.append(skeleton.get_bone_global_pose(bone))
		into.append(frame)
	skeleton.skeleton_updated.connect(keep)
	return keep


# Two bodies through the same commands, one setting every space every frame: the poses drawn,
# and how many frames the other left its crouch space unset.
func _side_by_side(momentum: bool) -> Dictionary:
	var shortcut := _player(Vector3(-3.0, 0.0, 0.0))
	var full := _player(Vector3(3.0, 0.0, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var bodies: Array[Player] = [shortcut, full]
	var drawn: Array[Array] = [[], []]
	var skeletons: Array[Skeleton3D] = []
	var settings := (CharacterGait.DEFAULTS as GaitSettings).duplicate() as GaitSettings
	settings.momentum_blend = momentum
	for index in bodies.size():
		var animation: CharacterAnimation = bodies[index].get_node("Animation")
		# The settings changed: each tree is built again, and both are held through it.
		animation.gait_settings = settings
		animation.gait.blend.set_undrawn = index == 1
		animation.set_throttled(true)
		skeletons.append(_skeleton(bodies[index]))
	await get_tree().physics_frame
	var crouch_at := &"parameters/Locomotion/crouch/blend_position"
	var stale := 0
	var crouched := 0
	var step := CommandDriver.tick_seconds()
	for tick in TICKS:
		await get_tree().physics_frame
		var command := _command(tick)
		for index in bodies.size():
			bodies[index].step(command.clone(), step)
			(bodies[index].get_node("Animation") as CharacterAnimation).advance(step)
			var keep := _record(skeletons[index], drawn[index])
			skeletons[index].notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
			skeletons[index].skeleton_updated.disconnect(keep)
		var trees: Array[AnimationTree] = [
			(shortcut.get_node("Animation") as CharacterAnimation).tree,
			(full.get_node("Animation") as CharacterAnimation).tree,
		]
		if not is_equal_approx(trees[0].get(crouch_at), trees[1].get(crouch_at)):
			stale += 1
		if shortcut.crouching:
			crouched += 1
	var rest := skeletons[0]
	var place := 0.0
	var turn := 0.0
	var worst := ""
	for frame in TICKS:
		for bone in rest.get_bone_count():
			var a: Transform3D = drawn[0][frame][bone]
			var b: Transform3D = drawn[1][frame][bone]
			var moved := a.origin.distance_to(b.origin)
			var turned := _turn(a.basis, b.basis)
			if moved > place or turned > turn:
				worst = "%s at tick %d" % [rest.get_bone_name(bone), frame]
			place = maxf(place, moved)
			turn = maxf(turn, turned)
	return {"place": place, "turn": turn, "worst": worst, "stale": stale, "crouched": crouched}


func _assert_same(found: Dictionary) -> void:
	var message := (
		"%.6f mm, %.6f degrees apart (%s); crouch space unset on %d frames, crouched %d"
		% [
			found.place * 1000.0,
			rad_to_deg(found.turn),
			found.worst,
			found.stale,
			found.crouched,
		]
	)
	print(message)
	assert_float(found.place).override_failure_message(message).is_less(PLACE)
	assert_float(found.turn).override_failure_message(message).is_less(TURN)
	# The shortcut did skip work, and the commands did crouch twice.
	assert_int(found.stale).override_failure_message(message).is_greater(20)
	assert_int(found.crouched).override_failure_message(message).is_greater(40)


func test_the_crouch_space_left_unset_draws_the_same() -> void:
	_assert_same(await _side_by_side(true))


func test_the_crouch_space_left_unset_draws_the_same_cross_faded() -> void:
	# With the momentum blend off the machine cross-fades out of the crouch over `blend_time`, and
	# the crouch space is drawn while it does.
	_assert_same(await _side_by_side(false))


func test_a_turn_is_picked_from_the_angle_near_it() -> void:
	var body := _player(Vector3.ZERO)
	await get_tree().physics_frame
	var animation: CharacterAnimation = body.get_node("Animation")
	var transitions := animation.gait.transitions
	var settings := transitions.settings
	# Running along +z at a jog; the stick at angles either side of the pivot and the reversal.
	for degrees: float in [
		0.0,
		30.0,
		settings.pivot_angle - 0.05,
		settings.pivot_angle + 0.05,
		settings.reversal_angle - 0.05,
		settings.reversal_angle + 0.05,
		179.0
	]:
		body.velocity = Vector3(0.0, 0.0, 4.0)
		var wish := Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, deg_to_rad(degrees))
		var command := PlayerCommand.new()
		# `world_move()` turns the push by the yaw: forward is (-sin, -cos) of it.
		command.move = Vector2(0.0, 1.0)
		command.yaw = atan2(-wish.x, -wish.z)
		body.last_command = command
		var asked := body.move_goal.direction(body).normalized()
		var angle := rad_to_deg(Vector3(0.0, 0.0, 1.0).angle_to(asked))
		transitions._speed_now = 4.0
		transitions._speed_before = 4.0
		transitions._goal = 4.0
		transitions._since_standing = 100
		var picked := transitions.pick(animation, animation.gait.blend)
		var expected := -1
		if angle >= settings.reversal_angle:
			expected = GaitTransitions.Kind.REVERSAL
		elif angle >= settings.pivot_angle:
			expected = GaitTransitions.Kind.PIVOT
		var got: int = picked.get("kind", -1)
		assert_int(got).override_failure_message("%.2f degrees: %s" % [angle, picked]).is_equal(
			expected
		)
