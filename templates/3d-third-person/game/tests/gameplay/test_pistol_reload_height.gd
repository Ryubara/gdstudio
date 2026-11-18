# The pistol's reload works in front of the chest (gdstudio #1584): the right hand brings the gun
# and the magazine no higher than the chin, upright and leaning left and right, on both bodies, so
# the reload reads right under a head the lean holds level (#1575). Measured along the world's up
# from the `Head` bone in every drawn frame of the reload (read in `skeleton_updated`): the right
# hand bone stays `HAND_DROP` under it all through, the pistol's muzzle (its highest point while
# the reload tilts it up) under the chin while the clip has the body (between the game's fades);
# upright, the head stays within `HEAD_TURN` of the level look it had aimed. The library's
# `Pistol_Reload` took the right hand 14 cm over the head bone on a left lean (the lean's roll
# lifts the right shoulder, and the clip took the gun further right and up) and turned the head
# 47 degrees off the aim upright.
extends GdUnitTestSuite

## How far under the head bone the chin is on both prototype bodies (11 and 12 mm), metres.
const CHIN := 0.012
## How far under the head bone the right hand bone stays all through, metres: the gun's grip and
## the hand round it are under the chin.
const HAND_DROP := 0.04
## The shares of the reload between the game's fades (`WeaponLayers.RELOAD_FADE_IN`, 0.15 s, and
## `RELOAD_FADE_OUT`, 0.2 s, of the pistol's 1.6 s), where the clip has the body.
const HELD := Vector2(0.1, 0.87)
## How far the head may turn off the level look it had aimed, upright, degrees.
const HEAD_TURN := 15.0
const SETTLE := 50
const WATCH := 150

var _arena: PlayArena
var _player: Player
var _skeleton: Skeleton3D
var _muzzle: Node3D
var _head := -1
var _hand := -1
var _frame := -1
var _reference := Basis.IDENTITY
## Each sample: the hand bone's and the muzzle's heights over the head bone (m), the head's turn
## off the reference (degrees), and the reload's share played.
var _samples: Array[Vector4] = []


func before_test() -> void:
	InputSim.release_all()


func after_test() -> void:
	InputSim.release_all()
	if _skeleton != null and _skeleton.skeleton_updated.is_connected(_on_updated):
		_skeleton.skeleton_updated.disconnect(_on_updated)
	if _arena != null:
		AudioDrain.stop_all(_arena)
	_arena = null


func test_the_reload_stays_under_the_chin(
	body: String,
	lean: String,
	_test_parameters := [
		["female", "none"],
		["female", "left"],
		["female", "right"],
		["male", "none"],
		["male", "left"],
		["male", "right"],
	]
) -> void:
	await _player_in_arena(body)
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	var key := KEY_Q if lean == "left" else KEY_E
	if lean != "none":
		InputSim.key(key, true)
	await InputSim.ticks(get_tree(), SETTLE)
	# A shot first, so the magazine is not full.
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
	await InputSim.ticks(get_tree(), 20)
	await _skeleton.skeleton_updated
	_reference = _head_basis()
	_samples.clear()
	_skeleton.skeleton_updated.connect(_on_updated)
	InputSim.key(KEY_R, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_R, false)
	await InputSim.ticks(get_tree(), 4)
	for _tick in WATCH:
		await get_tree().physics_frame
		if not _animation().is_reloading():
			break
	_skeleton.skeleton_updated.disconnect(_on_updated)
	InputSim.key(key, false)
	var tag := "%s lean %s" % [body, lean]
	var worst := _worst()
	prints(
		"reload height",
		tag,
		"hand mm",
		snappedf(worst.x * 1000.0, 0.1),
		"muzzle mm (held)",
		snappedf(worst.y * 1000.0, 0.1),
		"head deg",
		snappedf(worst.z, 0.1),
		"samples",
		_samples.size()
	)
	for index in range(0, _samples.size(), 4):
		var sample := _samples[index]
		prints(
			"  ",
			tag,
			snappedf(sample.w, 0.01),
			snappedf(sample.x * 1000.0, 1.0),
			snappedf(sample.y * 1000.0, 1.0),
			snappedf(sample.z, 0.1)
		)
	assert_int(_samples.size()).override_failure_message(tag + ": no reload").is_greater(60)
	(
		assert_float(worst.x)
		. override_failure_message(
			"%s: the right hand rose to %.0f mm from the head bone" % [tag, worst.x * 1000.0]
		)
		. is_less(-HAND_DROP)
	)
	(
		assert_float(worst.y)
		. override_failure_message(
			"%s: the muzzle rose to %.0f mm from the head bone" % [tag, worst.y * 1000.0]
		)
		. is_less(-CHIN)
	)
	if lean == "none":
		(
			assert_float(worst.z)
			. override_failure_message("%s: the head turned %.1f degrees" % [tag, worst.z])
			. is_less(HEAD_TURN)
		)


func _player_in_arena(body: String) -> void:
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
	await InputSim.ticks(get_tree(), 60)
	_skeleton = _player.model.skeleton()
	_head = _skeleton.find_bone(&"Head")
	_hand = _skeleton.find_bone(&"hand_r")
	_muzzle = _player.model.get_node(_player.weapon.definition.muzzle) as Node3D


func _animation() -> CharacterAnimation:
	return _player.get_node("Animation") as CharacterAnimation


func _head_basis() -> Basis:
	var head := _skeleton.global_transform * _skeleton.get_bone_global_pose(_head)
	return (_player.model.global_basis.inverse() * head.basis).orthonormalized()


# The highest hand all through, the highest muzzle between the fades and the head's widest turn.
func _worst() -> Vector3:
	var worst := Vector3(-INF, -INF, 0.0)
	for sample in _samples:
		worst.x = maxf(worst.x, sample.x)
		if sample.w >= HELD.x and sample.w <= HELD.y:
			worst.y = maxf(worst.y, sample.y)
		worst.z = maxf(worst.z, sample.z)
	return worst


func _on_updated() -> void:
	var head := _skeleton.global_transform * _skeleton.get_bone_global_pose(_head)
	var hand := _skeleton.global_transform * _skeleton.get_bone_global_pose(_hand)
	var turn := rad_to_deg(
		_head_basis().get_rotation_quaternion().angle_to(_reference.get_rotation_quaternion())
	)
	# The muzzle node follows the hand bone only when its attachment updates: work it out from the
	# drawn hand, as the attachment will place it.
	var attachment := _muzzle.get_parent()
	while attachment != null and not attachment is BoneAttachment3D:
		attachment = attachment.get_parent()
	var muzzle_y := _muzzle.global_position.y
	if attachment != null:
		var from_hand := (
			(attachment as Node3D).global_transform.affine_inverse() * _muzzle.global_position
		)
		muzzle_y = (hand * from_hand).y
	var sample := Vector4(
		hand.origin.y - head.origin.y,
		muzzle_y - head.origin.y,
		turn,
		_animation().reload_progress().y
	)
	# The drawn pose is the frame's last update.
	var frame := Engine.get_process_frames()
	if frame == _frame and not _samples.is_empty():
		_samples[-1] = sample
	else:
		_samples.append(sample)
	_frame = frame
