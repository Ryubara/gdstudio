# The online game hands its puppets to a `CharacterAnimationThrottle` (gdstudio #1138): a puppet
# near the camera animates every frame as the player does, one far behind the camera holds its pose
# (its tree does not move on), and a player who leaves is taken back. The online scene wires its
# `RemotePlayers` to one.
extends GdUnitTestSuite

const ONLINE := "res://online_main.tscn"
const NEAR_SLOT := 1
const FAR_SLOT := 2

var _camera: Camera3D
var _remote: RemotePlayers
var _throttle: CharacterAnimationThrottle


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
	_remote = RemotePlayers.new()
	_remote.animation_throttle = _throttle
	stage.add_child(_remote)
	# Placing from the tracks is the network's part; here the puppets stand where they joined.
	_remote.set_physics_process(false)
	var welcome := SnapshotCodec.Welcome.new()
	welcome.slot = 0
	welcome.players = [_entry(NEAR_SLOT, Vector3.ZERO), _entry(FAR_SLOT, Vector3(0.0, 0.0, 60.0))]
	_remote.on_welcome(welcome)


func _entry(slot: int, at: Vector3) -> PlayerEntry:
	var entry := PlayerEntry.new()
	entry.slot = slot
	entry.position = at
	return entry


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _clip_time(puppet: Player) -> float:
	var tree := puppet.get_node("AnimationTree") as AnimationTree
	var playback := tree.get(&"parameters/Locomotion/playback") as AnimationNodeStateMachinePlayback
	return playback.get_current_play_position()


func test_a_near_puppet_animates_and_one_behind_the_camera_holds_its_pose() -> void:
	await _frames(CharacterAnimationThrottle.FIRST_FRAMES + _throttle.recheck_frames + 1)
	var near := _remote.puppet_at(NEAR_SLOT)
	var far := _remote.puppet_at(FAR_SLOT)
	assert_int(_throttle.count()).is_equal(2)
	assert_int(_throttle.period_of(near)).is_equal(1)
	assert_int(_throttle.period_of(far)).is_equal(0)
	var near_before := _clip_time(near)
	var far_before := _clip_time(far)
	await _frames(10)
	assert_float(_clip_time(near)).is_not_equal(near_before)
	assert_float(_clip_time(far)).is_equal(far_before)


func test_a_player_who_leaves_is_taken_back() -> void:
	var far := _remote.puppet_at(FAR_SLOT)
	_remote.on_left(FAR_SLOT)
	assert_int(_throttle.count()).is_equal(1)
	assert_int(_throttle.period_of(far)).is_equal(-1)
	_remote.clear()
	assert_int(_throttle.count()).is_equal(0)


func test_the_online_scene_gives_its_puppets_a_throttle() -> void:
	var online := auto_free((load(ONLINE) as PackedScene).instantiate()) as OnlineMain
	var throttle := online.remote_players.animation_throttle
	assert_object(throttle).is_not_null()
	assert_object(throttle).is_same(online.get_node("PuppetAnimationThrottle"))
