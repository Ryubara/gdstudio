# Running with the rifle is one pose however the character came to it (kit #1333): fresh from the
# pickup, after a switch from the pistol, after shots, after a reload and after going unarmed
# and back, on both bodies. Nothing a shot starts is left on the body once its own hold is over,
# so the run, the sprint and the slide after a burst are the ones before it; the pistol's run is
# the same after the rifle; and the head keeps the run clip's own facing under the rifle's chest
# turn. The player is driven with simulated input and read on every update of the skeleton: the
# weapon layer's weights (hold, aim, shot, reload, the aim's stance), the rifle hold's own
# (raised, reach) and the body (the trunk's lean, the right hand from the chest, the head's
# turn), each a mean over three whole strides of the gait.
extends GdUnitTestSuite

const RIFLE := "res://gameplay/weapon/rifle.tres"
## The strides of its clip a gait is read over, after `SETTLE` ticks for the blends to end: whole
## strides, so two means of the same gait do not differ by where in the stride they started.
const STRIDES := 3
const SETTLE := 40
## How far two means of the same gait may differ: degrees for a lean or a turn, metres for the
## hand. They are the same to a tenth of a degree and a millimetre; after a shot the trunk was 13
## degrees more upright and the hand 30 mm off.
const LEAN := 0.5
const HAND := 0.003
## How far the head's swing may differ between two readings of the same gait, in degrees.
const SAME_SWING := 2.0
## The same for a slide: its first ticks still hold some of the sprint's pose, and two slides do
## not leave the sprint at the same place in its stride (an 18-frame sprint read over whole
## strides and a 40-tick settle), which moved the swing 2.6 degrees with nothing else changed.
const SLIDE_SWING := 4.0
## The ticks from letting go of the fire button until nothing of the shot is on the body: the
## rifle stays at the shoulder `shot_hold_time` (0.6 s) and comes down in `raise_time` (0.15 s).
const AFTER_SHOT := 60
## How far the head may turn from side to side through a run with the rifle, in degrees, over
## what it does in the same run with empty hands.
const HEAD_SWING := 12.0

var _arena: PlayArena
var _player: Player
var _animation: CharacterAnimation
var _skeleton: Skeleton3D
var _sums: Dictionary[String, float] = {}
var _head_low := 0.0
var _head_high := 0.0
var _count := 0
var _shooting := 0


func before_test() -> void:
	InputSim.release_all()


func after_test() -> void:
	InputSim.release_all()
	if _arena != null:
		AudioDrain.stop_all(_arena)
	_arena = null


func test_the_rifle_run_is_the_same_after_a_switch_and_after_a_shot(
	body: String, _test_parameters := [["female"], ["male"]]
) -> void:
	await _player_running(body)
	await _tap(KEY_H)
	await InputSim.ticks(get_tree(), 60)
	var unarmed: Dictionary = await _gait("%s unarmed" % body)
	_player.loadout.give(load(RIFLE) as WeaponDef, 60)
	await InputSim.ticks(get_tree(), 60)
	assert_str(_player.weapon.definition.display_name).is_equal("Rifle")
	var fresh: Dictionary = await _gait("%s rifle fresh" % body)
	_assert_rifle_layers(fresh, "%s fresh" % body)
	# The head stays on the run clip under the chest's turn: it does not swing with the turn the
	# stance takes off the chest.
	(
		assert_float(fresh.head_swing)
		. override_failure_message(
			(
				"%s: the head turns %.0f degrees side to side in the rifle run, %.0f unarmed"
				% [body, fresh.head_swing, unarmed.head_swing]
			)
		)
		. is_less(unarmed.head_swing + HEAD_SWING)
	)
	# To the pistol and back, running all the while.
	await _tap(KEY_1)
	await InputSim.ticks(get_tree(), 60)
	assert_str(_player.weapon.definition.display_name).is_equal("Pistol")
	await _tap(KEY_2)
	await InputSim.ticks(get_tree(), 60)
	assert_str(_player.weapon.definition.display_name).is_equal("Rifle")
	_assert_same(await _gait("%s rifle after the pistol" % body), fresh)
	# A burst on the move, then the same run.
	await _burst()
	await InputSim.ticks(get_tree(), AFTER_SHOT)
	_assert_same(await _gait("%s rifle after a burst" % body), fresh)
	# A reload, then the same run.
	await _tap(KEY_R)
	await InputSim.ticks(get_tree(), roundi(_player.weapon.definition.reload_time * 60.0) + 30)
	assert_int(_player.weapon.ammo).is_equal(30)
	_assert_same(await _gait("%s rifle after a reload" % body), fresh)
	# Unarmed and back.
	await _tap(KEY_H)
	await InputSim.ticks(get_tree(), 60)
	_assert_same(await _gait("%s unarmed after the rifle" % body), unarmed)
	await _tap(KEY_H)
	await InputSim.ticks(get_tree(), 60)
	assert_str(_player.weapon.definition.display_name).is_equal("Rifle")
	_assert_same(await _gait("%s rifle after unarmed" % body), fresh)


func test_the_sprint_and_the_slide_after_a_burst_are_the_ones_before_it(
	body: String, _test_parameters := [["female"], ["male"]]
) -> void:
	await _player_running(body)
	_player.loadout.give(load(RIFLE) as WeaponDef, 60)
	await InputSim.ticks(get_tree(), 60)
	InputSim.key(KEY_SHIFT, true)
	var sprint: Dictionary = await _gait("%s sprint" % body)
	var slide: Dictionary = await _slide("%s slide" % body)
	await _burst()
	await InputSim.ticks(get_tree(), AFTER_SHOT)
	InputSim.key(KEY_SHIFT, true)
	_assert_same(await _gait("%s sprint after a burst" % body), sprint)
	_assert_same(await _slide("%s slide after a burst" % body), slide, SLIDE_SWING)


func test_the_pistol_run_is_the_same_after_the_rifle_and_after_a_shot(
	body: String, _test_parameters := [["female"], ["male"]]
) -> void:
	await _player_running(body)
	var fresh: Dictionary = await _gait("%s pistol fresh" % body)
	assert_float(fresh.armed).is_equal(1.0)
	_player.loadout.give(load(RIFLE) as WeaponDef, 60)
	await InputSim.ticks(get_tree(), 60)
	# A rifle burst, then the pistol at once: the rifle's shot is not on the pistol's arm.
	await _burst()
	await _tap(KEY_1)
	await InputSim.ticks(get_tree(), 60)
	assert_str(_player.weapon.definition.display_name).is_equal("Pistol")
	_assert_same(await _gait("%s pistol after the rifle" % body), fresh)
	# A pistol shot, then the rifle at once: the pistol's recoil is not on the rifle.
	await _burst()
	await _tap(KEY_2)
	var shown := 0
	for _tick in 60:
		await InputSim.ticks(get_tree(), 1)
		if _player.weapon.definition.display_name == "Rifle" and _animation.is_shooting():
			shown += 1
	assert_int(shown).override_failure_message("the pistol's shot plays on the rifle").is_equal(0)
	await _tap(KEY_1)
	await InputSim.ticks(get_tree(), 60)
	_assert_same(await _gait("%s pistol after a shot and the rifle" % body), fresh)
	# Unarmed, then the pistol.
	await _tap(KEY_H)
	await InputSim.ticks(get_tree(), 60)
	await _tap(KEY_H)
	await InputSim.ticks(get_tree(), 60)
	assert_str(_player.weapon.definition.display_name).is_equal("Pistol")
	_assert_same(await _gait("%s pistol after unarmed" % body), fresh)


# A player of `body` in an arena, running forward, read on every update of its skeleton.
func _player_running(body: String) -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	if body == "male":
		var slot := _player.model
		var old := slot.rig()
		slot.remove_child(old)
		old.free()
		slot.add_child((load(CharacterBodies.MALE) as PackedScene).instantiate())
	var view := Camera3D.new()
	view.position = Vector3(0.0, 1.3, 3.0)
	_arena.add_child(view)
	view.make_current()
	await InputSim.ticks(get_tree(), 10)
	_skeleton = _player.model.skeleton()
	_animation = _player.find_children("*", "CharacterAnimation", true, false)[0]
	_skeleton.skeleton_updated.connect(_read)
	InputSim.key(KEY_W, true)


func _tap(key: Key) -> void:
	InputSim.key(key, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(key, false)


# Holds the fire button for a third of a second; the weapon has fired by then.
func _burst() -> void:
	var rounds: int = _player.weapon.ammo
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await InputSim.ticks(get_tree(), 20)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
	assert_int(_player.weapon.ammo).override_failure_message("no shot was fired").is_less(rounds)


# The state of the gait the character is in, read over `STRIDES` strides of the clip it plays
# (the run's, or the sprint's while the sprint key is held): the body is brought back to the
# middle of the floor first, so a long run stays on it.
func _gait(tag: String) -> Dictionary:
	_player.position.x = 0.0
	_player.position.z = 0.0
	await InputSim.ticks(get_tree(), SETTLE)
	var sprinting := Input.is_action_pressed(&"sprint")
	var clip := _animation.sprint_clip if sprinting else _animation.run_clip
	var stride := _animation.animation_player.get_animation(clip).length
	return await _state(tag, roundi(stride * STRIDES * Engine.physics_ticks_per_second))


# A slide out of the sprint the character is in, read from its tenth tick to its fortieth; the
# character is running again after it.
func _slide(tag: String) -> Dictionary:
	_player.position.x = 0.0
	_player.position.z = 0.0
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 10)
	var state: Dictionary = await _state(tag, 30)
	assert_bool(_player.sliding).override_failure_message(tag + ": not sliding").is_true()
	InputSim.key(KEY_C, false)
	InputSim.key(KEY_SHIFT, false)
	await InputSim.ticks(get_tree(), 120)
	if _player.crouching:
		await _tap(KEY_C)
		await InputSim.ticks(get_tree(), 60)
	return state


func _state(tag: String, ticks: int) -> Dictionary:
	_sums.clear()
	_count = 0
	_shooting = 0
	await InputSim.ticks(get_tree(), ticks)
	var weights := _animation.pistol_weights()
	var hold := _player.model.get_node_or_null("RifleHeld") as TwoHandHold
	var out := hold != null and hold.visible
	var state := {
		"tag": tag,
		"armed": weights.x,
		"aim": weights.y,
		"shooting": _shooting,
		"reloading": _animation.is_reloading(),
		"acting": _animation.is_acting(),
		"stance": float(_animation.tree.get(AimStance.AMOUNT)),
		"raised": hold.raised_amount() if out else 0.0,
		"reach": hold.reach_amount() if hold != null else 0.0,
		"trunk_forward": _mean("trunk_forward"),
		"trunk_side": _mean("trunk_side"),
		"hand": Vector3(_mean("hand_x"), _mean("hand_y"), _mean("hand_z")),
		"head_swing": _head_high - _head_low,
	}
	print(
		(
			"STATE %-40s shot %3d trunk %5.1f/%5.1f hand (%.3f %.3f %.3f) head swing %5.1f"
			% [
				tag,
				_shooting,
				state.trunk_forward,
				state.trunk_side,
				state.hand.x,
				state.hand.y,
				state.hand.z,
				state.head_swing
			]
		)
	)
	return state


func _mean(key: String) -> float:
	return _sums.get(key, 0.0) / maxf(_count, 1)


# One update of the skeleton, after its modifiers: the trunk's lean (the line from the pelvis to
# the neck, forward and to the side, in degrees), the right hand from the chest and the head's
# turn about the up axis, in the model's space.
func _read() -> void:
	if _animation.is_shooting():
		_shooting += 1
	var hips := _place("pelvis")
	var trunk := (_place("neck_01") - hips).normalized()
	_add("trunk_forward", rad_to_deg(atan2(trunk.z, trunk.y)))
	_add("trunk_side", rad_to_deg(atan2(trunk.x, trunk.y)))
	var hand := _place("hand_r") - _place("spine_03")
	_add("hand_x", hand.x)
	_add("hand_y", hand.y)
	_add("hand_z", hand.z)
	var head := _skeleton.find_bone("Head")
	var turned := (
		_skeleton.get_bone_global_pose(head).basis.orthonormalized()
		* _skeleton.get_bone_global_rest(head).basis.orthonormalized().inverse()
	)
	var ahead := turned * Vector3.BACK
	var turn := rad_to_deg(atan2(ahead.x, ahead.z))
	_head_low = turn if _count == 0 else minf(_head_low, turn)
	_head_high = turn if _count == 0 else maxf(_head_high, turn)
	_count += 1


func _place(bone: String) -> Vector3:
	return _skeleton.get_bone_global_pose(_skeleton.find_bone(bone)).origin


func _add(key: String, value: float) -> void:
	_sums[key] = _sums.get(key, 0.0) + value


# With the rifle out and at the low ready, the weapon layer holds the rifle's own idle (its grip
# clip, kit #1267) in full and nothing else: no aim, no shot.
func _assert_rifle_layers(state: Dictionary, tag: String) -> void:
	var grip := 1.0 if (load(RIFLE) as WeaponDef).grip_clip != &"" else 0.0
	assert_float(state.armed).override_failure_message(tag + ": armed").is_equal_approx(grip, 0.001)
	assert_float(state.aim).override_failure_message(tag + ": aim").is_equal(0.0)
	assert_float(state.raised).override_failure_message(tag + ": raised").is_equal(0.0)
	assert_float(state.reach).override_failure_message(tag + ": reach").is_equal(1.0)
	assert_int(state.shooting).override_failure_message(tag + ": a shot's clip plays").is_equal(0)


# `state` is `wanted`: the same weights on every layer and the same body within the tolerances.
func _assert_same(state: Dictionary, wanted: Dictionary, swing := SAME_SWING) -> void:
	var tag := "%s against %s: " % [state.tag, wanted.tag]
	for key: String in ["armed", "aim", "stance", "raised", "reach"]:
		(
			assert_float(state[key])
			. override_failure_message("%s%s %.2f, not %.2f" % [tag, key, state[key], wanted[key]])
			. is_equal_approx(wanted[key], 0.001)
		)
	(
		assert_int(state.shooting)
		. override_failure_message("%sa shot's clip plays in %d updates" % [tag, state.shooting])
		. is_equal(wanted.shooting)
	)
	assert_bool(state.reloading).override_failure_message(tag + "reloading").is_false()
	assert_bool(state.acting).override_failure_message(tag + "an action plays").is_false()
	for key: String in ["trunk_forward", "trunk_side"]:
		(
			assert_float(state[key])
			. override_failure_message(
				"%s%s %.1f degrees, not %.1f" % [tag, key, state[key], wanted[key]]
			)
			. is_equal_approx(wanted[key], LEAN)
		)
	var off := (state.hand as Vector3).distance_to(wanted.hand)
	(
		assert_float(off)
		. override_failure_message(
			"%sthe right hand is %.0f mm from where it was" % [tag, off * 1e3]
		)
		. is_less(HAND)
	)
	(
		assert_float(state.head_swing)
		. override_failure_message(
			"%sthe head swings %.0f degrees, not %.0f" % [tag, state.head_swing, wanted.head_swing]
		)
		. is_equal_approx(wanted.head_swing, swing)
	)
