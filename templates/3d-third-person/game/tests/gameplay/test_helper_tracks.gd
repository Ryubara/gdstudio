# The helper bones' tracks (gdstudio #1438): our clips key the rig's `ik_` targets, which nothing
# drawn follows, and `HelperTracks` switches those tracks off so the tree no longer blends them.
# These hold that the bodies give the targets no say in the skin (no weight, no bone under them),
# that a character's libraries carry no helper track switched on, and that a body walked through
# the same commands beside one whose own copies of the clips keep the tracks on is drawn the same:
# every other bone, the targets at their rest.
extends GdUnitTestSuite

const TUNING := preload("res://gameplay/player/player_tuning.tres")
const TICKS := 150
## How far apart two drawn bones may be: a place (m) and a turn (radians). Two bodies side by side
## differ by single precision alone (`test_gait_lean.gd` reads the same).
const PLACE := 1e-5
const TURN := 1e-5

var _arena: PlayArena


func before_test() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)


# A player at `spot` taken over by commands and stepped by hand.
func _player(spot: Vector3) -> Player:
	var body := _arena.add_player(spot)
	body.tuning = (TUNING as CharacterTuning).duplicate()
	# The reversal at tick 60 plays over the steering, as the tree plays it for any body: moved
	# by its clip's root (#1442) each body is placed from its own spot, and a micrometre of
	# rounding apart turns the bones by more than this suite's limit.
	body.tuning.turn_root_motion = false
	CommandDriver.take(body)
	return body


# Gives `body`'s player copies of its libraries whose helper tracks are on, its own: the rest of
# the game keeps them off.
func _keep_helper_tracks(body: Player) -> void:
	var player := body.get_node("AnimationPlayer") as AnimationPlayer
	for library_name in player.get_animation_library_list():
		var library := player.get_animation_library(library_name)
		var copy := AnimationLibrary.new()
		for clip in library.get_animation_list():
			var animation := library.get_animation(clip).duplicate(true) as Animation
			for track in animation.get_track_count():
				if HelperTracks.is_helper(str(animation.track_get_path(track))):
					animation.track_set_enabled(track, true)
			copy.add_animation(clip, animation)
		player.remove_animation_library(library_name)
		player.add_animation_library(library_name, copy)


func _skeleton(body: Node) -> Skeleton3D:
	return body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D


# A walk that speeds up, turns both ways, sprints, brakes and stops: the gaits, their blends,
# a start and a stop, the lean and the momentum blend.
func _command(tick: int) -> PlayerCommand:
	var command := PlayerCommand.new()
	if tick < 110:
		command.move = Vector2(0.0, 1.0)
		command.yaw = 0.0 if tick < 20 else 0.03 * (tick - 20) * (1.0 if tick < 60 else -1.0)
		command.sprint = tick >= 40 and tick < 80
	return command


# The turn between two bones (radians), read through atan2: `Quaternion.angle_to` goes through an
# acos, which reads up to 0.08 degrees for two turns equal to single precision.
static func _turn(a: Basis, b: Basis) -> float:
	var d := a.get_rotation_quaternion().inverse() * b.get_rotation_quaternion()
	return 2.0 * atan2(Vector3(d.x, d.y, d.z).length(), absf(d.w))


# Records, each drawn frame, every bone's global pose as the last modifier left it (what the skin
# gets) into `into`.
func _record(skeleton: Skeleton3D, into: Array) -> Callable:
	var keep := func() -> void:
		var frame: Array[Transform3D] = []
		for bone in skeleton.get_bone_count():
			frame.append(skeleton.get_bone_global_pose(bone))
		into.append(frame)
	skeleton.skeleton_updated.connect(keep)
	return keep


func test_the_bodies_give_the_helper_bones_no_say_in_the_skin() -> void:
	for path in [CharacterBodies.FEMALE, CharacterBodies.MALE]:
		var rig := auto_free((load(path) as PackedScene).instantiate()) as Node3D
		var skeleton := _skeleton(rig)
		var helpers := PackedInt32Array()
		for bone in skeleton.get_bone_count():
			if HelperTracks.is_helper(skeleton.get_bone_name(bone)):
				helpers.append(bone)
		assert_int(helpers.size()).override_failure_message(path).is_equal(4)
		for bone in skeleton.get_bone_count():
			assert_bool(helpers.has(skeleton.get_bone_parent(bone))).is_false()
		var meshes := skeleton.find_children("*", "MeshInstance3D", true, false)
		assert_int(meshes.size()).is_greater(0)
		for mesh_instance: MeshInstance3D in meshes:
			var skin := mesh_instance.skin
			var helper_binds := {}
			for bind in skin.get_bind_count():
				if HelperTracks.is_helper(skin.get_bind_name(bind)):
					helper_binds[bind] = true
			for surface in mesh_instance.mesh.get_surface_count():
				var arrays := mesh_instance.mesh.surface_get_arrays(surface)
				var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				var weighted := 0
				for index in bones.size():
					if helper_binds.has(bones[index]) and weights[index] > 0.0:
						weighted += 1
				(
					assert_int(weighted)
					. override_failure_message(
						"%s %s: %d weights on helper bones" % [path, mesh_instance.name, weighted]
					)
					. is_equal(0)
				)


func test_a_character_blends_no_helper_track() -> void:
	var body := _arena.add_player(Vector3.ZERO)
	await get_tree().physics_frame
	var player := body.get_node("AnimationPlayer") as AnimationPlayer
	var helper_tracks := 0
	var switched_on := 0
	for library_name in player.get_animation_library_list():
		var library := player.get_animation_library(library_name)
		for clip in library.get_animation_list():
			var animation := library.get_animation(clip)
			for track in animation.get_track_count():
				if HelperTracks.is_helper(str(animation.track_get_path(track))):
					helper_tracks += 1
					if animation.track_is_enabled(track):
						switched_on += 1
	# Our clips key the four targets (place and turn), the library's do not.
	assert_int(helper_tracks).is_greater(0)
	assert_int(switched_on).is_equal(0)
	# Each library is looked through once.
	assert_int(HelperTracks.mute(player)).is_equal(0)


func test_a_body_is_drawn_the_same_with_the_helper_tracks_off() -> void:
	var muted := _player(Vector3(-3.0, 0.0, 0.0))
	var keyed := _player(Vector3(3.0, 0.0, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	_keep_helper_tracks(keyed)
	var bodies: Array[Player] = [muted, keyed]
	var drawn: Array[Array] = [[], []]
	var skeletons: Array[Skeleton3D] = []
	for index in bodies.size():
		var animation: CharacterAnimation = bodies[index].get_node("Animation")
		animation.set_throttled(true)
		skeletons.append(_skeleton(bodies[index]))
	var step := CommandDriver.tick_seconds()
	for tick in TICKS:
		await get_tree().physics_frame
		var command := _command(tick)
		for index in bodies.size():
			bodies[index].step(command.clone(), step)
			(bodies[index].get_node("Animation") as CharacterAnimation).advance(step)
			# Recorded inside the skeleton's update, here rather than at the frame's end.
			var keep := _record(skeletons[index], drawn[index])
			skeletons[index].notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
			skeletons[index].skeleton_updated.disconnect(keep)
	assert_int(drawn[0].size()).is_equal(TICKS)
	assert_int(drawn[1].size()).is_equal(TICKS)
	var rest := skeletons[0]
	var place := 0.0
	var turn := 0.0
	var worst := ""
	var off_rest := 0
	var targets_moved := 0
	for frame in TICKS:
		for bone in rest.get_bone_count():
			var a: Transform3D = drawn[0][frame][bone]
			var b: Transform3D = drawn[1][frame][bone]
			if HelperTracks.is_helper(rest.get_bone_name(bone)):
				# Off, a target stays at its rest; with its tracks on, the clips move it.
				if not a.is_equal_approx(rest.get_bone_global_rest(bone)):
					off_rest += 1
				if not a.is_equal_approx(b):
					targets_moved += 1
				continue
			var moved := a.origin.distance_to(b.origin)
			var turned := _turn(a.basis, b.basis)
			if moved > place or turned > turn:
				worst = "%s at tick %d" % [rest.get_bone_name(bone), frame]
			place = maxf(place, moved)
			turn = maxf(turn, turned)
	var message := "%.6f mm, %.6f degrees apart (%s)" % [place * 1000.0, rad_to_deg(turn), worst]
	print(message)
	assert_float(place).override_failure_message(message).is_less(PLACE)
	assert_float(turn).override_failure_message(message).is_less(TURN)
	assert_int(off_rest).is_equal(0)
	assert_int(targets_moved).is_greater(0)
