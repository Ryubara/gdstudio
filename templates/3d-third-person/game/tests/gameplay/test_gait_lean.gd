# The lean's cost (gdstudio #1403): `GaitLean` takes the base off once an axis and blends trimmed
# clips (`LeanClips`) in place of one `AnimationNodeSub2` and four whole clips a way. These hold
# that it draws what the four differences drew, bone by bone, while the body walks, turns, speeds
# up and stops, and that it has no distance or visibility rule: a character far off and out of the
# camera's sight leans exactly as one beside it does (the maintainer's call: a far enemy leaning
# to peek has to read through a scope).
extends GdUnitTestSuite

const TUNING := preload("res://gameplay/player/player_tuning.tres")
const WAYS: Array[StringName] = [&"left", &"right", &"forward", &"back"]
## How far apart two drawn poses may be: a bone's place (m) and its turn (radians).
const PLACE := 1e-4
const TURN := 1e-4

var _arena: PlayArena


func before_test() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)


# A player taken over by commands and stepped by hand, its tree throttled (advanced here).
func _player_at(spot: Vector3, settings: GaitSettings = null) -> Player:
	var body := _arena.add_player(spot)
	body.tuning = (TUNING as CharacterTuning).duplicate()
	if settings != null:
		(body.get_node("Animation") as CharacterAnimation).gait_settings = settings
	CommandDriver.take(body)
	return body


func _skeleton(body: Player) -> Skeleton3D:
	return body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D


# The largest distance between two skeletons' drawn bones: [place (m), turn (radians), bone].
func _apart(a: Skeleton3D, b: Skeleton3D) -> Array:
	var place := 0.0
	var turn := 0.0
	var worst := ""
	for bone in a.get_bone_count():
		var pa := a.get_bone_global_pose(bone)
		var pb := b.get_bone_global_pose(bone)
		var moved := pa.origin.distance_to(pb.origin)
		var turned := _turn(pa.basis, pb.basis)
		if moved > place or turned > turn:
			worst = a.get_bone_name(bone)
		place = maxf(place, moved)
		turn = maxf(turn, turned)
	return [place, turn, worst]


# The turn between two bones (radians), read through atan2: `Quaternion.angle_to` goes through an
# acos, which reads 0.03 to 0.08 degrees for two turns equal to single precision.
static func _turn(a: Basis, b: Basis) -> float:
	var d := a.get_rotation_quaternion().inverse() * b.get_rotation_quaternion()
	return 2.0 * atan2(Vector3(d.x, d.y, d.z).length(), absf(d.w))


# The commands of a walk that speeds up, turns both ways, sprints, brakes and stops: every way
# of the lean, and both axes at once.
func _command(tick: int) -> PlayerCommand:
	var command := PlayerCommand.new()
	if tick < 150:
		command.move = Vector2(0.0, 1.0)
		command.yaw = 0.0 if tick < 30 else 0.03 * (tick - 30) * (1.0 if tick < 90 else -1.0)
		command.sprint = tick >= 60 and tick < 120
	return command


# The lean as it was built before gdstudio #1403: per way, its pose less the whole base clip (an
# `AnimationNodeSub2`), added by the way's amount.
func _build_reference(animation: CharacterAnimation) -> Array[StringName]:
	var root := animation.tree.tree_root as AnimationNodeBlendTree
	var settings := CharacterGait.settings_of(animation)
	root.disconnect_node(&"Armed", 0)
	var last := &"Locomotion"
	var params: Array[StringName] = []
	for way in WAYS:
		var node := StringName("Old" + String(way).capitalize())
		root.add_node(node + "Pose", _held(settings.lean_clips[way]))
		root.add_node(node + "Base", _held(animation.idle_clip))
		root.add_node(node + "Diff", AnimationNodeSub2.new())
		root.add_node(node, AnimationNodeAdd2.new())
		root.connect_node(node + "Diff", 0, node + "Pose")
		root.connect_node(node + "Diff", 1, node + "Base")
		root.connect_node(node, 0, last)
		root.connect_node(node, 1, node + "Diff")
		last = node
		params.append(StringName("parameters/%s/add_amount" % node))
	root.connect_node(&"Armed", 0, last)
	animation.tree.advance(0.0)
	for way in WAYS:
		animation.tree.set("parameters/Old%sDiff/sub_amount" % String(way).capitalize(), 1.0)
	return params


static func _held(clip: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	node.use_custom_timeline = true
	node.stretch_time_scale = false
	node.loop_mode = Animation.LOOP_NONE
	node.timeline_length = 0.0
	return node


func test_the_lean_draws_what_the_four_differences_drew() -> void:
	# One player has the lean; the other has none of its own and the old build in its place,
	# given the same amounts each tick. Both are stepped by the same commands.
	var no_lean := (CharacterGait.DEFAULTS as GaitSettings).duplicate(true) as GaitSettings
	no_lean.lean = false
	var leaning := _player_at(Vector3(-3.0, 0.0, 0.0))
	var reference := _player_at(Vector3(3.0, 0.0, 0.0), no_lean)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var new_animation: CharacterAnimation = leaning.get_node("Animation")
	var old_animation: CharacterAnimation = reference.get_node("Animation")
	assert_bool(new_animation.gait.lean.is_built()).is_true()
	assert_bool(old_animation.gait.lean.is_built()).is_false()
	new_animation.set_throttled(true)
	old_animation.set_throttled(true)
	var params := _build_reference(old_animation)
	var step := CommandDriver.tick_seconds()
	var worst := [0.0, 0.0, ""]
	var both_axes := 0
	var leaned := 0.0
	for tick in 210:
		await get_tree().physics_frame
		var command := _command(tick)
		leaning.step(command, step)
		reference.step(command.clone(), step)
		new_animation.advance(step)
		var lean := new_animation.gait.lean.amount
		for index in WAYS.size():
			var axis: Vector3 = GaitLean.WAYS[WAYS[index]]
			old_animation.tree.set(params[index], maxf(lean.x * axis.x + lean.y * axis.y, 0.0))
		old_animation.advance(step)
		var apart := _apart(_skeleton(leaning), _skeleton(reference))
		if apart[0] > worst[0] or apart[1] > worst[1]:
			worst = [maxf(apart[0], worst[0]), maxf(apart[1], worst[1]), apart[2]]
		if absf(lean.x) > 0.05 and absf(lean.y) > 0.05:
			both_axes += 1
		leaned = maxf(leaned, maxf(absf(lean.x), absf(lean.y)))
	var message := (
		(
			"the lean against the old build: %.4f mm, %.5f degrees at most (%s); "
			+ "%d ticks on both axes, %.2f the most"
		)
		% [worst[0] * 1000.0, rad_to_deg(worst[1]), worst[2], both_axes, leaned]
	)
	print(message)
	# The walk leaned well, and on both axes at once, or the comparison proves little.
	assert_float(leaned).override_failure_message(message).is_greater(0.3)
	assert_int(both_axes).override_failure_message(message).is_greater(10)
	assert_float(worst[0]).override_failure_message(message).is_less(PLACE)
	assert_float(worst[1]).override_failure_message(message).is_less(TURN)


func test_the_trimmed_clips_keep_only_the_tracks_a_pose_moves() -> void:
	var body := _player_at(Vector3.ZERO)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var player: AnimationPlayer = body.get_node("AnimationPlayer")
	var kept := LeanClips.kept_tracks(player)
	var whole := player.get_animation((body.get_node("Animation") as CharacterAnimation).idle_clip)
	print("the lean's clips keep ", kept, " of the base's ", whole.get_track_count(), " tracks")
	assert_array(kept.keys()).contains_exactly_in_any_order(
		[&"across", &"along", &"left", &"right", &"forward", &"back"]
	)
	for clip: StringName in kept:
		assert_int(kept[clip]).is_greater(0).is_less(whole.get_track_count())
	# Shared: a second character's player holds the same library, not a copy.
	var other := _player_at(Vector3(4.0, 0.0, 0.0))
	await get_tree().physics_frame
	var other_player: AnimationPlayer = other.get_node("AnimationPlayer")
	assert_object(other_player.get_animation_library(LeanClips.LIBRARY)).is_same(
		player.get_animation_library(LeanClips.LIBRARY)
	)
	# The tree has two bases, not four.
	var root := (
		(body.get_node("AnimationTree") as AnimationTree).tree_root as AnimationNodeBlendTree
	)
	assert_bool(root.has_node(&"LeanAcrossBase")).is_true()
	assert_bool(root.has_node(&"LeanAlongBase")).is_true()
	assert_bool(root.has_node(&"LeanLeftBase")).is_false()


func test_a_far_character_out_of_sight_leans_exactly_as_a_near_one() -> void:
	# No distance or visibility rule: the same player, at the same spot, through the same
	# commands, once with the camera 6 m off and looking at it, once with the camera 400 m off and
	# looking away. The body moves itself (not throttled); its lean and its bones match each tick.
	var near := await _seen_from(Vector3(0.0, 2.0, -6.0), Vector3(0.0, 1.0, 0.0), true)
	var far := await _seen_from(Vector3(0.0, 2.0, -400.0), Vector3(0.0, 2.0, -800.0), false)
	var amounts := 0.0
	var leaned := 0.0
	var worst := [0.0, 0.0]
	for tick in near.size():
		amounts = maxf(amounts, (near[tick][0] - far[tick][0]).length())
		leaned = maxf(leaned, (near[tick][0] as Vector2).length())
		for bone in (near[tick][1] as Array).size():
			var a: Transform3D = near[tick][1][bone]
			var b: Transform3D = far[tick][1][bone]
			worst[0] = maxf(worst[0], a.origin.distance_to(b.origin))
			worst[1] = maxf(worst[1], _turn(a.basis, b.basis))
	var message := (
		"near and far: the lean %.6f apart, the bones %.4f mm and %.5f degrees at most; %.2f the most"
		% [amounts, worst[0] * 1000.0, rad_to_deg(worst[1]), leaned]
	)
	print(message)
	assert_float(leaned).override_failure_message(message).is_greater(0.3)
	assert_float(amounts).override_failure_message(message).is_less(1e-6)
	assert_float(worst[0]).override_failure_message(message).is_less(PLACE)
	assert_float(worst[1]).override_failure_message(message).is_less(TURN)


# The player's lean and drawn bones each tick of `_command`, with the camera at `spot` looking at
# `target`; `in_sight`: whether the body is in the camera's view.
func _seen_from(spot: Vector3, target: Vector3, in_sight: bool) -> Array:
	var arena := PlayArena.new()
	add_child(arena)
	var body := arena.add_player(Vector3.ZERO)
	body.tuning = (TUNING as CharacterTuning).duplicate()
	CommandDriver.take(body)
	var camera := Camera3D.new()
	arena.add_child(camera)
	camera.position = spot
	camera.look_at(target)
	await get_tree().physics_frame
	camera.make_current()
	await get_tree().physics_frame
	var skeleton := _skeleton(body)
	assert_bool(camera.is_position_in_frustum(skeleton.global_position)).is_equal(in_sight)
	assert_float(camera.global_position.distance_to(body.global_position)).is_greater(
		spot.length() - 1.0
	)
	var lean := (body.get_node("Animation") as CharacterAnimation).gait.lean
	var frames := []
	for tick in 180:
		await get_tree().physics_frame
		body.step(_command(tick), CommandDriver.tick_seconds())
		await get_tree().process_frame
		var bones := []
		for bone in skeleton.get_bone_count():
			bones.append(skeleton.get_bone_global_pose(bone))
		frames.append([lean.amount, bones])
	arena.queue_free()
	await get_tree().process_frame
	return frames
