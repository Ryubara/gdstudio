# Upper-body actions while leaning keep the head where the lean holds it (gdstudio #1575). A peek
# is for looking past cover, so the head stays on the lean's line and level whatever the hands do:
# aimed and leaning left, then right, each action (the reload, a shot, a melee blow or a punch, a
# bandage, a switch; the pistol, the rifle and the fists, both bodies) runs over the upper body,
# and in every drawn frame (read in `skeleton_updated`) the head bone stays within `HEAD_SLACK` of
# where it was just before, from the pelvis in the model's frame, turned no more than `HEAD_TURN`.
# A switch ends on the other weapon's stance, so it is held to the straight way between the two.
# On main the pistol's reload dropped the head 3 to 4 cm and turned it 70 degrees to the gun.
extends GdUnitTestSuite

const RIFLE := "res://gameplay/weapon/rifle.tres"
## How far the head bone may move off where the lean held it before the action, metres.
const HEAD_SLACK := 0.006
## How far a switch's head may leave the straight way between the two weapons' stances, metres:
## the old weapon's pose is held while it goes down and eased into the new one's as it comes up.
const SWITCH_SLACK := 0.012
## How far the head may turn off where the lean held it before the action, degrees.
const HEAD_TURN := 1.5
## Ticks for the lean and the aim to settle before the action.
const SETTLE := 50
## The most ticks an action is watched for.
const WATCH := 150

var _arena: PlayArena
var _player: Player
var _skeleton: Skeleton3D
var _head := -1
var _pelvis := -1
var _frame := -1
var _reference := Transform3D.IDENTITY
var _samples: Array[Transform3D] = []


func before_test() -> void:
	InputSim.release_all()


func after_test() -> void:
	InputSim.release_all()
	if _skeleton != null and _skeleton.skeleton_updated.is_connected(_on_updated):
		_skeleton.skeleton_updated.disconnect(_on_updated)
	if _arena != null:
		AudioDrain.stop_all(_arena)
	_arena = null


func test_the_head_stays_on_the_lean_through_each_action(
	body: String,
	weapon: String,
	action: String,
	_test_parameters := [
		["female", "pistol", "reload"],
		["female", "pistol", "fire"],
		["female", "pistol", "melee"],
		["female", "pistol", "switch"],
		["female", "pistol", "use"],
		["female", "rifle", "reload"],
		["female", "rifle", "fire"],
		["female", "rifle", "melee"],
		["female", "rifle", "use"],
		["female", "fists", "melee"],
		["female", "fists", "use"],
		["male", "pistol", "reload"],
		["male", "pistol", "melee"],
		["male", "rifle", "reload"],
		["male", "rifle", "melee"],
		["male", "fists", "melee"],
	]
) -> void:
	await _player_in_arena(body, weapon)
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	for key: Key in [KEY_Q, KEY_E]:
		var tag := "%s %s %s lean %s" % [body, weapon, action, OS.get_keycode_string(key)]
		InputSim.key(key, true)
		await InputSim.ticks(get_tree(), SETTLE)
		assert_float(absf(_player.peek_motion.amount)).override_failure_message(tag).is_equal(1.0)
		# Read only in the update: outside it the skeleton shows the clips' pose, no modifier.
		await _skeleton.skeleton_updated
		_reference = _head_pose()
		_samples.clear()
		_skeleton.skeleton_updated.connect(_on_updated)
		await _run(action, weapon)
		_skeleton.skeleton_updated.disconnect(_on_updated)
		var worst := _worst(action == "switch")
		prints("lean action head", tag, "moved mm", worst.x * 1000.0, "turned", worst.y)
		(
			assert_float(worst.x)
			. override_failure_message(
				"%s: the head moved %.1f mm off the lean" % [tag, worst.x * 1000.0]
			)
			. is_less(SWITCH_SLACK if action == "switch" else HEAD_SLACK)
		)
		(
			assert_float(worst.y)
			. override_failure_message("%s: the head turned %.1f degrees" % [tag, worst.y])
			. is_less(HEAD_TURN)
		)
		InputSim.key(key, false)
		await InputSim.ticks(get_tree(), SETTLE)


func _player_in_arena(body: String, weapon: String) -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	_player._present_facing()
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
	await InputSim.ticks(get_tree(), 30)
	if weapon == "rifle":
		_player.loadout.give(load(RIFLE) as WeaponDef, 60)
		await InputSim.ticks(get_tree(), 60)
	elif weapon == "fists":
		await _tap(KEY_H)
		await InputSim.ticks(get_tree(), 30)
	# Hurt, so a bandage works, long before the action: taking health plays a hit's reaction.
	Health.of(_player).value = 30.0
	await InputSim.ticks(get_tree(), 60)
	_skeleton = _player.model.skeleton()
	_head = _skeleton.find_bone(&"Head")
	_pelvis = _skeleton.find_bone(&"pelvis")


# Runs `action` and waits until it is over (or `WATCH` ticks).
func _run(action: String, weapon: String) -> void:
	match action:
		"reload":
			# A shot first, so the magazine is not full.
			InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
			await InputSim.ticks(get_tree(), 2)
			InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
			await InputSim.ticks(get_tree(), 20)
			await _skeleton.skeleton_updated
			_reference = _head_pose()
			_samples.clear()
			await _tap(KEY_R)
		"fire":
			InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
			await InputSim.ticks(get_tree(), 12 if weapon == "rifle" else 2)
			InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
		"melee":
			await _tap(KEY_V)
		"switch":
			await _tap(KEY_H)
		"use":
			await _tap(KEY_3)
	for _tick in WATCH:
		await get_tree().physics_frame
		if not _busy():
			break
	await InputSim.ticks(get_tree(), 10)


func _busy() -> bool:
	var animation := _player.get_node("Animation") as CharacterAnimation
	var weapon := _player.weapon
	return (
		animation.is_reloading()
		or animation.melee.share(animation.tree) > 0.0
		or (weapon != null and weapon.meleeing)
		or ItemUse.of(_player).is_using()
		or _player.loadout.lowered_amount() > 0.0
	)


func _tap(code: Key) -> void:
	InputSim.key(code, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(code, false)
	await InputSim.ticks(get_tree(), 2)


# The head bone as drawn, its place from the pelvis, in the model's frame (a turn or a step of the
# whole body is not the head's).
func _head_pose() -> Transform3D:
	var global := _skeleton.global_transform * _skeleton.get_bone_global_pose(_head)
	var pelvis := _skeleton.global_transform * _skeleton.get_bone_global_pose(_pelvis)
	var pose := _player.model.global_transform.affine_inverse() * global
	pose.origin = _player.model.global_basis.inverse() * (global.origin - pelvis.origin)
	return pose


# The worst sample (metres off, degrees turned): off the place before the action, or for a switch
# off the straight way from the place before to the place after it.
func _worst(between: bool) -> Vector2:
	var end := _samples[-1] if between and not _samples.is_empty() else _reference
	var start_turn := _reference.basis.get_rotation_quaternion()
	var end_turn := end.basis.get_rotation_quaternion()
	var way := rad_to_deg(start_turn.angle_to(end_turn))
	var worst := Vector2.ZERO
	for pose in _samples:
		var at := Geometry3D.get_closest_point_to_segment(
			pose.origin, _reference.origin, end.origin
		)
		var turn := pose.basis.get_rotation_quaternion()
		var off_way := rad_to_deg(turn.angle_to(start_turn))
		if between:
			off_way += rad_to_deg(turn.angle_to(end_turn)) - way
		worst = Vector2(maxf(worst.x, pose.origin.distance_to(at)), maxf(worst.y, off_way))
	return worst


func _on_updated() -> void:
	var pose := _head_pose()
	# The drawn pose is the frame's last update: a node that reads a bone in a physics tick updates
	# the skeleton once more in between.
	var frame := Engine.get_process_frames()
	if frame == _frame and not _samples.is_empty():
		_samples[-1] = pose
	else:
		_samples.append(pose)
	_frame = frame
