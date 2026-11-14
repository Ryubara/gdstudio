# A vault with the rifle in the hands (gdstudio #1409): the rifle's two-hand hold kept the left
# hand on the hand guard through the vault, so the low vault's planted hand never reached the
# top, and with the rifle put away for the high vault both arms still went to where it would
# be. On the live player, on each body, holding the rifle: each planted wrist is on the top
# where the clip puts it at the clip's contact frames, the rifle stays in the right hand for the
# low vault and is put away for the high one, and both hands are back on it after the landing.
extends GdUnitTestSuite

const FACE := 2.5
const DEPTH := 0.4
const RIFLE := "res://gameplay/weapon/rifle.tres"
const BODIES := {
	"female": CharacterBodies.FEMALE,
	"male": CharacterBodies.MALE,
}
## A low vault (the left hand on the top) and a high one (both hands).
const HEIGHTS: Array[float] = [0.9, 1.2]
## How far a planted wrist may be from where the clip puts it on the top, in metres: the empty
## hands' limits (`test_vault_contacts.gd`: 20 mm up, 30 mm along and across).
const WRIST_UP := 0.02
const WRIST_ALONG := 0.03
## How far a hand's bone may be from its place on the rifle once the hands are back, in metres.
const ON_PLACE := 0.01

var _arena: PlayArena
var _player: Player
var _skeleton: Skeleton3D
var _animation: CharacterAnimation
var _hold: TwoHandHold


func after_test() -> void:
	InputSim.release_all()
	if _arena != null:
		AudioDrain.stop_all(_arena)
		_arena.free()
		_arena = null


# A player on `model`'s body with the rifle up and ready in its hands.
func _player_with_rifle(model: String) -> void:
	after_test()
	_arena = PlayArena.new()
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	_player.tuning = (
		(load("res://gameplay/player/player_tuning.tres") as CharacterTuning).duplicate()
	)
	_player.vault_settings = _player.vault_settings.duplicate(true)
	_animation = _player.get_node("Animation") as CharacterAnimation
	await InputSim.ticks(get_tree(), 4)
	var slot := _player.model
	var old := slot.rig()
	slot.remove_child(old)
	old.free()
	var added := (load(BODIES[model]) as PackedScene).instantiate() as Node3D
	slot.add_child(added)
	added.owner = _player
	await InputSim.ticks(get_tree(), 4)
	var rifle := load(RIFLE) as WeaponDef
	var loadout := _player.loadout
	var index := -1
	for at in loadout.slots.size():
		if (loadout.slots[at] as WeaponDef).resource_path == RIFLE:
			index = at
	if index >= 0:
		loadout.select(index)
	else:
		loadout.give(rifle, 60)
	await InputSim.ticks(get_tree(), 70)
	assert_bool(loadout.is_switching()).is_false()
	_skeleton = _player.model.skeleton()
	_hold = _player.model.get_node(rifle.view) as TwoHandHold
	assert_object(_hold).is_not_null()


func _drawn(node: Node3D) -> Transform3D:
	if _player.model.top_level and (node == _player.model or _player.model.is_ancestor_of(node)):
		return node.global_transform
	return node.get_global_transform_interpolated()


func _bone(bone: StringName) -> Vector3:
	return (_drawn(_skeleton) * _skeleton.get_bone_global_pose(_skeleton.find_bone(bone))).origin


func _sample(into: Array[Dictionary]) -> void:
	if not _player.vault_motion.is_active():
		return
	var sample := {
		"time": float(_animation.tree.get(&"parameters/ActionClip/current_position")),
		"hand_l": _bone(&"hand_l"),
		"hand_r": _bone(&"hand_r"),
		"shown": _hold.is_visible_in_tree(),
		"frame": Engine.get_process_frames(),
	}
	if not into.is_empty() and into[-1].frame == sample.frame:
		into[-1] = sample
		return
	into.append(sample)


# Runs at a wall `height` high and presses jump 0.6 m before it; one sample a drawn frame.
func _vault(height: float) -> Array[Dictionary]:
	var wall := _arena.add_block(
		Vector2(0.0, -(FACE + DEPTH / 2.0)), Vector3(4.0, height, DEPTH), height
	)
	wall.add_child(Vaultable.new())
	var radius := _player.tuning.radius
	_player.teleport(Vector3(0.0, 0.0, -(FACE - radius - 0.6 - 1.2)), PI)
	await InputSim.ticks(get_tree(), 3)
	InputSim.key(KEY_W, true)
	for _tick in 240:
		await get_tree().physics_frame
		if -_player.global_position.z >= FACE - radius - 0.6:
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
		if motion.is_active():
			began = true
		elif began:
			break
	_skeleton.skeleton_updated.disconnect(take)
	InputSim.key(KEY_W, false)
	return samples


func test_each_planted_hand_reaches_the_top_with_the_rifle_held() -> void:
	for model: String in BODIES:
		for height in HEIGHTS:
			await _player_with_rifle(model)
			var samples := await _vault(height)
			var label := "%s %.2f m" % [model, height]
			assert_int(samples.size()).override_failure_message(label).is_greater(20)
			var clip := _player.vault_settings.clip_for(height >= 1.0)
			var planted := 0
			var worst := 0.0
			for hand: StringName in clip.planted_hands:
				var place: Vector3 = clip.planted_hands[hand]
				for sample in samples:
					var time: float = sample.time
					if time < clip.planted_from(height) or time > clip.hand_release[hand]:
						continue
					planted += 1
					var wrist: Vector3 = sample[hand]
					var off := Vector3(-wrist.x - place.x, wrist.y - height - place.y, 0.0)
					off.z = -FACE - wrist.z - place.z
					worst = maxf(worst, off.length())
					var at := (
						"%s %s at %.3f s: the wrist is %s m off its place"
						% [label, hand, time, off]
					)
					assert_float(absf(off.y)).override_failure_message(at).is_less(WRIST_UP)
					(
						assert_float(Vector2(off.x, off.z).length())
						. override_failure_message(at)
						. is_less(WRIST_ALONG * 1.42)
					)
			prints(label, "the planted wrist's farthest from its place: %.1f mm" % (worst * 1e3))
			assert_int(planted).override_failure_message(label).is_greater(3)


func test_the_rifle_stays_in_the_right_hand_low_and_is_put_away_high() -> void:
	for height in HEIGHTS:
		await _player_with_rifle("female")
		var samples := await _vault(height)
		var hidden := samples.any(func(sample: Dictionary) -> bool: return not sample.shown)
		assert_bool(hidden).override_failure_message("%.2f m" % height).is_equal(height >= 1.0)


func test_both_hands_are_back_on_the_rifle_after_the_landing() -> void:
	for model: String in BODIES:
		for height in HEIGHTS:
			await _player_with_rifle(model)
			await _vault(height)
			await InputSim.ticks(get_tree(), 60)
			var label := "%s %.2f m" % [model, height]
			assert_bool(_hold.is_visible_in_tree()).override_failure_message(label).is_true()
			assert_float(_hold.free_amount()).override_failure_message(label).is_equal(0.0)
			var short := _hold.shortfall()
			assert_float(short.x).override_failure_message(label).is_less(ON_PLACE)
			assert_float(short.y).override_failure_message(label).is_less(ON_PLACE)
