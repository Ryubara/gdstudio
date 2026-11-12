# The animation throttle tells a character's rifle hold when the camera is past the hold's
# `fingers_far_distance` (kit #1178): the hold reads no camera itself (the character and its
# weapon read none, `test_player_step.gd`), and a character given back rests no fingers.
extends GdUnitTestSuite

const PLAYER := "res://gameplay/player/player.tscn"
const RIFLE := "res://gameplay/weapon/rifle.tres"

var _camera: Camera3D
var _throttle: CharacterAnimationThrottle
var _player: Player


func before_test() -> void:
	var stage := auto_free(Node3D.new()) as Node3D
	add_child(stage)
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 1.6, 4.0)
	stage.add_child(_camera)
	_camera.make_current()
	_throttle = CharacterAnimationThrottle.new()
	_throttle.camera = _camera
	stage.add_child(_throttle)
	_player = (load(PLAYER) as PackedScene).instantiate() as Player
	_player.start_at_spawn = false
	var slots: Array[Resource] = [_player.loadout.slots[0], load(RIFLE)]
	_player.loadout.slots = slots
	stage.add_child(_player)
	_player.set_physics_process(false)
	_player.loadout.equip_now(1)
	_throttle.add(_player)


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _hold() -> TwoHandHold:
	for child in _player.loadout.model.get_children():
		if child is TwoHandHold:
			return child
	return null


func test_the_throttle_rests_the_fingers_only_past_the_holds_distance() -> void:
	var settle := CharacterAnimationThrottle.FIRST_FRAMES + _throttle.recheck_frames + 1
	await _frames(settle)
	var hold := _hold()
	assert_object(hold).is_not_null()
	assert_bool(hold.fingers_far).override_failure_message("near: resting").is_false()
	_camera.position = Vector3(0.0, 1.6, hold.fingers_far_distance + 5.0)
	await _frames(_throttle.recheck_frames + 1)
	assert_bool(hold.fingers_far).override_failure_message("far: still posed").is_true()
	_camera.position = Vector3(0.0, 1.6, hold.fingers_far_distance - 5.0)
	await _frames(_throttle.recheck_frames + 1)
	assert_bool(hold.fingers_far).override_failure_message("near again: resting").is_false()
	_camera.position = Vector3(0.0, 1.6, hold.fingers_far_distance + 5.0)
	await _frames(_throttle.recheck_frames + 1)
	_throttle.remove(_player)
	assert_bool(hold.fingers_far).override_failure_message("given back: resting").is_false()
