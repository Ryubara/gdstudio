# The vault clips in the game itself (kit #1037): the real player, on each mannequin, runs at walls
# of the vault's heights and presses jump, and the pose that is drawn is measured on every frame of
# the crossing: each planted hand sits on the obstacle's top where the clip put it and stays there
# until it lets go, no foot or knee goes into the wall or under the floor, the model starts and
# lands on the capsule, and the landing step follows the vault. The clips alone, over their own
# reference boxes, are `tests/assets/test_vault_clips.gd`.
extends GdUnitTestSuite

const FACE := 2.5
const DEPTH := 0.4
const MALE := "res://assets/characters/mannequin/mannequin_male.glb"
const CLIPS := "res://assets/animation/vault/vault_clips.json"
## The heights run: the course's walls, the clips' own boxes and the ends of each clip's range.
const HEIGHTS: Array[float] = [0.5, 0.8, 0.9, 1.05, 1.2, 1.27]
## How far the planted wrist may sit from the height the clip rests it at over the top, and from
## where the clip puts it along and across the top, in metres. The male mannequin's arms are
## 0.05 m longer than the female's the clips were keyed on, so its wrist sits lower.
const WRIST_UP := {"female": 0.02, "male": 0.06}
const WRIST_ALONG := {"female": 0.03, "male": 0.075}
## How far a planted wrist may move while it is planted.
const WRIST_DRIFT := {"female": 0.025, "male": 0.08}
## How far a foot or knee bone may come to the wall's box, and to the floor (the bones sit inside
## the leg: an ankle is 0.06 m over the sole).
const LEG_BONES: Array[StringName] = [
	&"foot_l", &"foot_r", &"ball_l", &"ball_r", &"calf_l", &"calf_r"
]
const FLOOR_SLACK := 0.02
## How far a joint's middle may be inside the wall. `Vault_Low` carries the left knee past the
## front edge between two of its 24 keys a second, and the frames drawn between them cut the
## corner by 0.05 m (the clip's own, gdstudio #1221).
const KNEE_CUT := 0.055

var _arena: PlayArena
var _player: Player
var _skeleton: Skeleton3D
var _animation: CharacterAnimation


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	_player.tuning = (
		(load("res://gameplay/player/player_tuning.tres") as CharacterTuning).duplicate()
	)
	# Its own copy of the settings: the file is shared by every suite of the run.
	_player.vault_settings = _player.vault_settings.duplicate(true)
	_animation = _player.get_node("Animation") as CharacterAnimation
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


func _reset(model: String) -> void:
	after_test()
	_arena.free()
	await before_test()
	if model == "male":
		var slot := _player.model
		var old := slot.rig()
		slot.remove_child(old)
		old.free()
		var added := (load(MALE) as PackedScene).instantiate() as Node3D
		slot.add_child(added)
		added.owner = _player
		await InputSim.ticks(get_tree(), 4)
	_skeleton = _player.model.skeleton()


# Where a node is drawn: between its last two ticks, or where the vault holds it this frame (the
# model and what is under it are outside the physics interpolation then).
func _drawn(node: Node3D) -> Transform3D:
	if _player.model.top_level and (node == _player.model or _player.model.is_ancestor_of(node)):
		return node.global_transform
	return node.get_global_transform_interpolated()


func _bone(bone: StringName) -> Vector3:
	var index := _skeleton.find_bone(bone)
	return (_drawn(_skeleton) * _skeleton.get_bone_global_pose(index)).origin


# One sample of the crossing as it is drawn this frame, taken when the skeleton has its pose
# (the clip and every modifier after it): the clip time of the pose, each bone of `LEG_BONES`
# and each wrist, the model's root and the capsule's feet.
func _sample(into: Array[Dictionary]) -> void:
	if not _player.vault_motion.is_active():
		return
	var tree := _animation.tree
	var sample := {
		"time": float(tree.get(&"parameters/ActionClip/current_position")),
		"root": _drawn(_player.model).origin,
		"feet": _drawn(_player).origin,
		"hand_l": _bone(&"hand_l"),
		"hand_r": _bone(&"hand_r"),
	}
	for bone in LEG_BONES:
		sample[bone] = _bone(bone)
	# The skeleton may say it updated more than once in a frame (another modifier's own update):
	# the last one is the pose that is drawn.
	sample["frame"] = Engine.get_process_frames()
	if not into.is_empty() and into[-1].frame == sample.frame:
		into[-1] = sample
		return
	into.append(sample)


# Runs at a wall `height` high from a standing start `run` metres before pressing jump `gap`
# before the face, and returns one sample a drawn frame of the crossing. With `keep_running` off
# the move key is let go as the vault starts.
func _vault(height: float, run: float, gap: float, keep_running := true) -> Array[Dictionary]:
	var wall := _arena.add_block(
		Vector2(0.0, -(FACE + DEPTH / 2.0)), Vector3(4.0, height, DEPTH), height
	)
	wall.add_child(Vaultable.new())
	var radius := _player.tuning.radius
	_player.teleport(Vector3(0.0, 0.0, -(FACE - radius - gap - run)), PI)
	await InputSim.ticks(get_tree(), 3)
	InputSim.key(KEY_W, true)
	for _tick in 240:
		await get_tree().physics_frame
		if -_player.global_position.z >= FACE - radius - gap:
			break
	InputSim.key(KEY_SPACE, true)
	var samples: Array[Dictionary] = []
	var take := _sample.bind(samples)
	_skeleton.skeleton_updated.connect(take)
	var motion := _player.vault_motion
	var began := false
	for frame in 150:
		await get_tree().process_frame
		if frame == 4:
			InputSim.key(KEY_SPACE, false)
		if motion.is_active() and not began:
			began = true
			if not keep_running:
				InputSim.key(KEY_W, false)
		if began and not motion.is_active():
			break
	_skeleton.skeleton_updated.disconnect(take)
	InputSim.key(KEY_W, false)
	return samples


func test_the_settings_clips_carry_the_numbers_the_clips_were_built_with() -> void:
	var built: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CLIPS))
	var settings := load("res://gameplay/character/vault_settings.tres") as VaultSettings
	var pairs := {"Vault_Low": settings.low_clip, "Vault_High": settings.high_clip}
	for clip_name: String in pairs:
		var clip := pairs[clip_name] as VaultClip
		var spec: Dictionary = built.clips[clip_name]
		assert_object(clip).override_failure_message(clip_name).is_not_null()
		var pinned := {
			"obstacle_height": spec.obstacle.height,
			"obstacle_depth": spec.obstacle.depth,
			"speed": spec.speed,
			"root_start": spec.root_start,
			"takeoff": spec.events.takeoff,
			"hand_plant": spec.events.hand_plant,
			"push_off": spec.events.push_off,
			"land": spec.events.land,
		}
		for property: String in pinned:
			(
				assert_float(float(clip.get(property)))
				. override_failure_message("%s.%s" % [clip_name, property])
				. is_equal_approx(float(pinned[property]), 0.0001)
			)
		assert_float(clip.hand_release[&"hand_l"]).is_equal_approx(spec.events.hand_release, 0.0001)
		var left := clip.planted_hands[&"hand_l"] as Vector3
		assert_vector(left).override_failure_message(clip_name).is_equal_approx(
			Vector3(spec.hand_place.left, spec.hand_place.wrist_above_top, spec.hand_place.forward),
			Vector3.ONE * 0.0001
		)
		# The landing the settings ask for is the clip's own, so the body keeps the clip's speed.
		var keyed := clip.keyed_landing() - _player.tuning.radius
		assert_float(settings.landing_margin).override_failure_message(clip_name).is_equal_approx(
			keyed, 0.03
		)
	assert_bool(settings.high_clip.puts_weapon_away).is_true()
	assert_bool(settings.low_clip.puts_weapon_away).is_false()
	assert_str(str(_animation.vault_clip)).is_equal(str(CharacterClips.VAULT_LOW))
	assert_str(str(_animation.vault_high_clip)).is_equal(str(CharacterClips.VAULT_HIGH))
	assert_str(str(_animation.vault_land_clip)).is_equal(str(CharacterClips.VAULT_LAND))


func test_each_planted_hand_sits_on_the_top_and_stays_there() -> void:
	for model: String in ["female", "male"]:
		for height in HEIGHTS:
			await _reset(model)
			var samples := await _vault(height, 1.2, 0.6)
			var label := "%s %.2f m" % [model, height]
			assert_int(samples.size()).override_failure_message(label).is_greater(20)
			if samples.is_empty():
				continue
			var clip := _player.vault_settings.clip_for(height >= 1.0)
			var planted := 0
			for hand: StringName in clip.planted_hands:
				var place: Vector3 = clip.planted_hands[hand]
				var first := Vector3.INF
				for sample in samples:
					var time: float = sample.time
					if time < clip.planted_from(height) or time > clip.hand_release[hand]:
						continue
					var wrist: Vector3 = sample[hand]
					var at := "%s %s at %.3f s" % [label, hand, time]
					planted += 1
					(
						assert_float(wrist.y - height)
						. override_failure_message(
							"%s: the wrist is %.3f m over the top" % [at, wrist.y - height]
						)
						. is_equal_approx(place.y, WRIST_UP[model])
					)
					# The body runs along -Z: past the front edge is a smaller z, its left is -X.
					(
						assert_float(-FACE - wrist.z)
						. override_failure_message(
							"%s: the wrist is %.3f m in from the edge" % [at, -FACE - wrist.z]
						)
						. is_equal_approx(place.z, WRIST_ALONG[model])
					)
					(
						assert_float(-wrist.x)
						. override_failure_message("%s: the wrist is %.3f m left" % [at, -wrist.x])
						. is_equal_approx(place.x, WRIST_ALONG[model])
					)
					if first == Vector3.INF:
						first = wrist
					(
						assert_float(wrist.distance_to(first))
						. override_failure_message(
							"%s: the wrist moved %.3f m" % [at, wrist.distance_to(first)]
						)
						. is_less(WRIST_DRIFT[model])
					)
			assert_int(planted).override_failure_message(label).is_greater(4)


func test_no_leg_goes_into_the_wall_or_under_the_floor() -> void:
	for model: String in ["female", "male"]:
		for height in HEIGHTS:
			await _reset(model)
			var samples := await _vault(height, 1.2, 0.6)
			var label := "%s %.2f m" % [model, height]
			var deepest := 0.0
			var lowest := 9.0
			var where := ""
			for sample in samples:
				for bone in LEG_BONES:
					var at: Vector3 = sample[bone]
					lowest = minf(lowest, at.y)
					# How far inside the wall's box the joint is: under the top and past both faces.
					var inside := minf(height - at.y, minf(-FACE - at.z, at.z + FACE + DEPTH))
					if inside > deepest:
						deepest = inside
						where = "%s at %.3f s" % [bone, sample.time]
			(
				assert_float(deepest)
				. override_failure_message(
					"%s: %s is %.3f m inside the wall" % [label, where, deepest]
				)
				. is_less(KNEE_CUT)
			)
			(
				assert_float(lowest)
				. override_failure_message("%s: a leg bone is at %.3f m" % [label, lowest])
				. is_greater(-FLOOR_SLACK)
			)


func test_the_model_leaves_and_lands_on_the_capsule_and_never_rises_with_it() -> void:
	await _reset("female")
	var samples := await _vault(0.9, 1.2, 0.6)
	assert_int(samples.size()).is_greater(20)
	var first: Dictionary = samples[0]
	var apart: Vector3 = first.root - first.feet
	assert_float(Vector2(apart.x, apart.z).length()).is_less(0.08)
	assert_float((first.root as Vector3).y).is_less(0.03)
	var highest_root := 0.0
	var highest_feet := 0.0
	for sample in samples:
		highest_root = maxf(highest_root, (sample.root as Vector3).y)
		highest_feet = maxf(highest_feet, (sample.feet as Vector3).y)
	# The capsule goes over the top; the clip carries the body, so its root is lifted only by the
	# difference to the clip's box (0.9 - 0.8 m).
	assert_float(highest_feet).is_greater(0.9)
	assert_float(highest_root).is_equal_approx(0.1, 0.01)
	await InputSim.ticks(get_tree(), 2)
	assert_vector(_player.model.position).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.001)
	assert_float(_player.global_position.y).is_equal_approx(0.0, 0.02)
	# The camera's target is back at the eye's own height.
	assert_float(_player.get_node("%CameraTarget").position.y).is_equal_approx(
		_player.tuning.camera_height, 0.001
	)


func test_the_cameras_target_stays_level_while_the_capsule_goes_over() -> void:
	await _reset("female")
	var target := _player.get_node("%CameraTarget") as Node3D
	var eye := _player.tuning.camera_height
	var heights: Array[float] = []
	var watch := func() -> void:
		if _player.vault_motion.is_active():
			heights.append(target.global_position.y)
	get_tree().physics_frame.connect(watch)
	await _vault(0.8, 1.2, 0.6)
	get_tree().physics_frame.disconnect(watch)
	assert_int(heights.size()).is_greater(20)
	# Over the clip's own box the root is level, and so is the eye.
	assert_float(heights.max()).is_less(eye + 0.02)
	assert_float(heights.min()).is_greater(eye - 0.02)


func test_the_landing_step_follows_the_vault_and_a_standing_body_drops_it() -> void:
	await _reset("female")
	var samples := await _vault(0.9, 1.2, 0.6)
	assert_int(samples.size()).is_greater(20)
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 4)
	# Still the same action: the vault clip joined to its landing step.
	assert_bool(_animation.is_acting()).is_true()
	assert_str(str(_animation.last_action())).contains("Vault_Low")
	assert_str(str(_animation.last_action())).contains("Vault_Land")
	InputSim.key(KEY_W, false)
	await _reset("female")
	samples = await _vault(0.9, 1.2, 0.6, false)
	assert_int(samples.size()).is_greater(20)
	await InputSim.ticks(get_tree(), 14)
	assert_bool(_animation.is_acting()).is_false()


# What the pistol's two-hand hold weighs and whether the pistol shows, on each drawn frame of a
# vault over a wall `height` high.
func _held_through(height: float) -> Dictionary:
	await _reset("female")
	var seen := {"weights": [], "shown": []}
	var view := _player.model.get_node_or_null(_animation.held_definition().view) as Node3D
	assert_object(view).is_not_null()
	var watch := func() -> void:
		if _player.vault_motion.is_active() and is_instance_valid(view):
			seen.weights.append(_animation.pistol_weights().x)
			seen.shown.append(view.visible)
	get_tree().process_frame.connect(watch)
	await _vault(height, 1.2, 0.6)
	get_tree().process_frame.disconnect(watch)
	seen["view"] = view
	return seen


func test_the_weapon_hold_lets_go_and_the_high_vault_puts_the_pistol_away() -> void:
	# The low vault keeps the pistol in the right fist; the left hand is the vault's.
	var low := await _held_through(0.9)
	assert_float((low.weights as Array).min()).is_equal(0.0)
	assert_bool((low.shown as Array).has(false)).is_false()
	# The high vault needs both hands open: the pistol is put away, and comes back after.
	var high := await _held_through(1.2)
	assert_bool((high.shown as Array).has(false)).is_true()
	await InputSim.ticks(get_tree(), 60)
	assert_bool((high.view as Node3D).visible).is_true()
	assert_float(_animation.pistol_weights().x).is_greater(0.9)
