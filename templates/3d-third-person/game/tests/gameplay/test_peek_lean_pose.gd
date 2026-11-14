# The peek lean as drawn and hit (gdstudio #1400): on the dressed player the `PeekLayer` bends the
# spine and the neck so the head bone goes where the step put the eye, the pelvis staying; aiming
# while leaning, the aim layer keeps the muzzle on the aim and the hold keeps both hands on the
# pistol and on the rifle; a shot from the front at the leaning head meets the head's hit zone,
# where the upright body has none; and the camera moves to the lean's shoulder.
extends GdUnitTestSuite

const RIFLE := "res://gameplay/weapon/rifle.tres"
## How far the head bone may be from where the step put the eye's shift, metres.
const HEAD_SLACK := 0.03
## How far a hand may be from its place on the weapon, metres (the hold's own 5 mm off).
const HAND_GAP := 0.005
## The most the muzzle may point off the aim, degrees.
const MISS := 3.0

var _arena: PlayArena
var _player: Player
var _skeleton: Skeleton3D


func before_test() -> void:
	InputSim.release_all()


func after_test() -> void:
	InputSim.release_all()
	if _arena != null:
		AudioDrain.stop_all(_arena)
	_arena = null


func _player_in_arena() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	# The model shows the facing the arena gave (a lean, as an aim, turns it to the view).
	_player._present_facing()
	var view := Camera3D.new()
	view.position = Vector3(0.0, 1.3, 3.0)
	_arena.add_child(view)
	view.make_current()
	# The idle's first blend has settled by then.
	await InputSim.ticks(get_tree(), 90)
	_skeleton = _player.model.skeleton()


func _bone(bone_name: StringName) -> Vector3:
	var pose := _skeleton.get_bone_global_pose(_skeleton.find_bone(bone_name))
	return (_skeleton.global_transform * pose).origin


# The bone's place on the skeleton's next update.
func _bone_after_update(bone_name: StringName) -> Vector3:
	await _skeleton.skeleton_updated
	return _bone(bone_name)


func test_the_bend_puts_the_head_where_the_eye_went_and_keeps_the_pelvis() -> void:
	await _player_in_arena()
	var head := await _bone_after_update(&"Head")
	var pelvis := _bone(&"pelvis")
	var foot := _bone(&"foot_l")
	InputSim.key(KEY_E, true)
	await InputSim.ticks(get_tree(), 30)
	var eye := CharacterCapsule.eye_height(_player)
	var wanted := _player.peek_motion.eye_shift(_player, eye, 1.0)
	var leaned := await _bone_after_update(&"Head")
	var moved := leaned - head
	prints("peek head moved", moved, "wanted", wanted)
	assert_float(moved.x).is_equal_approx(wanted.x, HEAD_SLACK)
	assert_float(absf(moved.z)).is_less(HEAD_SLACK)
	assert_float(_bone(&"pelvis").distance_to(pelvis)).is_less(0.01)
	assert_float(_bone(&"foot_l").distance_to(foot)).is_less(0.01)
	# The upper body tilts from the hips: about 34 degrees on this body, whose hips are 0.91 m up
	# and its head 0.61 m above them, for the 0.35 m to the side.
	var tilt := rad_to_deg((head - pelvis).angle_to(leaned - _bone(&"pelvis")))
	prints("peek tilt", tilt)
	assert_float(tilt).is_between(22.0, 38.0)
	InputSim.key(KEY_E, false)
	InputSim.key(KEY_Q, true)
	await InputSim.ticks(get_tree(), 40)
	moved = await _bone_after_update(&"Head") - head
	assert_float(moved.x).is_equal_approx(-wanted.x, HEAD_SLACK)


func test_aiming_while_leaning_keeps_the_pistol_on_target_and_in_both_hands() -> void:
	await _player_in_arena()
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	await InputSim.ticks(get_tree(), 40)
	var upright := await _pistol_hands()
	for key: Key in [KEY_E, KEY_Q]:
		InputSim.key(key, true)
		await InputSim.ticks(get_tree(), 40)
		var leaning := await _pistol_hands()
		var tag := "lean %s" % OS.get_keycode_string(key)
		prints("peek pistol", tag, leaning, "upright", upright)
		assert_float(leaning.miss).override_failure_message(tag).is_less(MISS)
		assert_float(leaning.left).override_failure_message(tag).is_less(upright.left + HAND_GAP)
		assert_float(leaning.right).override_failure_message(tag).is_less(upright.right + HAND_GAP)
		InputSim.key(key, false)


# The muzzle's miss and each hand's distance from its place on the pistol on the next update.
func _pistol_hands() -> Dictionary:
	await _skeleton.skeleton_updated
	var aim := (_player.get_node("AimLayer") as AimLayer).modifier()
	var pistol := _player.model.get_node("PistolHeld/Pistol") as Node3D
	var support := pistol.get_node("SupportHand") as Node3D
	var seat := _player.model.get_node("PistolHeld") as Node3D
	return {
		"miss": aim.miss,
		"left": _bone(&"hand_l").distance_to(support.global_position),
		"right": _bone(&"hand_r").distance_to(seat.global_position),
	}


func test_aiming_the_rifle_while_leaning_keeps_both_hands_on_it() -> void:
	await _player_in_arena()
	_player.loadout.give(load(RIFLE) as WeaponDef, 60)
	await InputSim.ticks(get_tree(), 60)
	assert_str(_player.weapon.definition.display_name).is_equal("Rifle")
	var hold := _player.model.get_node("RifleHeld") as TwoHandHold
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	for key: Key in [KEY_E, KEY_Q]:
		InputSim.key(key, true)
		await InputSim.ticks(get_tree(), 50)
		await _skeleton.skeleton_updated
		var tag := "rifle lean %s" % OS.get_keycode_string(key)
		var aim := (_player.get_node("AimLayer") as AimLayer).modifier()
		var right := _bone(&"hand_r").distance_to(_marker(hold, "RightHandTarget"))
		var left := _bone(&"hand_l").distance_to(_marker(hold, "LeftHandTarget"))
		prints("peek rifle", tag, "miss", aim.miss, "hands", right, left)
		assert_float(absf(_player.peek_motion.amount)).is_equal(1.0)
		assert_float(aim.miss).override_failure_message(tag).is_less(MISS)
		assert_float(right).override_failure_message(tag).is_less(HAND_GAP)
		assert_float(left).override_failure_message(tag).is_less(HAND_GAP)
		InputSim.key(key, false)


func _marker(hold: Node, marker: String) -> Vector3:
	return (hold.find_child(marker, true, false) as Node3D).global_position


func test_a_shot_at_the_leaning_head_meets_the_head_zone() -> void:
	await _player_in_arena()
	await _skeleton.skeleton_updated
	var zones := _player.get_node("HitZones") as HitZones
	zones.follow_bones()
	var upright_head := zones.zone(&"head").global_position
	InputSim.key(KEY_E, true)
	await InputSim.ticks(get_tree(), 30)
	await _skeleton.skeleton_updated
	zones.follow_bones()
	var head := zones.zone(&"head").global_position
	# Past the upright capsule's side: only the lean puts a part of the body there.
	assert_float(head.x).is_greater(_player.tuning.radius)
	var from := Vector3(head.x, head.y, -4.0)
	var to := Vector3(head.x, head.y, 4.0)
	assert_str(String(_zone_on(from, to))).is_equal("head")
	InputSim.key(KEY_E, false)
	await InputSim.ticks(get_tree(), 30)
	await _skeleton.skeleton_updated
	assert_str(String(_zone_on(from, to))).is_equal("-")
	# Upright, the head is where it was before the lean.
	zones.follow_bones()
	var back := zones.zone(&"head").global_position
	assert_float(back.distance_to(upright_head)).is_less(0.02)


# The zone a shot along `from`-`to` meets on the player, `&"-"` when it meets no part of it.
func _zone_on(from: Vector3, to: Vector3) -> StringName:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	# As a shot sees it: the player's shot hull gives the part on the line (kit #1431).
	var space := _arena.get_world_3d().direct_space_state
	var hit := ShotHull.ray_as_shot(space, query, (to - from).normalized())
	if hit.is_empty() or hit.collider != _player:
		return &"-"
	var zones := HitZones.of(hit.collider)
	var record := zones.shot(hit.collider, hit.position, to - from, 10.0, 1.0)
	return record.zone if record != null else &"-"


func test_the_camera_moves_to_the_lean_shoulder() -> void:
	var scene := scene_runner("res://main.tscn").scene()
	var rig := scene.get_node("PlayerRig/PlayerCamera") as PlayerCamera
	await InputSim.ticks(get_tree(), 8)
	for _tick in 60:
		rig.advance(1.0 / 60.0)
	assert_float(rig.current_view_offset().x).is_greater(0.4)
	InputSim.key(KEY_Q, true)
	await InputSim.ticks(get_tree(), 30)
	for _tick in 60:
		rig.advance(1.0 / 60.0)
	assert_float(rig.current_view_offset().x).is_less(-0.4)
	InputSim.key(KEY_Q, false)
	await InputSim.ticks(get_tree(), 30)
	for _tick in 60:
		rig.advance(1.0 / 60.0)
	assert_float(rig.current_view_offset().x).is_greater(0.4)
	AudioDrain.stop_all(scene)
