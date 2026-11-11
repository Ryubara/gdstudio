# The character lying down and crawling plays the template's own prone clips (kit #1009),
# through simulated input in the real physics world: the going-down and getting-up clips play over
# the body, the prone idle and the crawl play with no pose offset, the crawl plays at the pace of
# the ground (backwards when backing up), the planted elbows and feet keep their place on the
# floor at the slow end, the default and the fast end of the crawl speed, the weapon is put away
# while the fists carry the body, and a model can have prone clips of its own.
extends GdUnitTestSuite

## The crawl clip's length and the share of its cycle a joint stays planted (the clips' README).
const CRAWL_SECONDS := 28.0 / 30.0
const ELBOW_PLANTED := 0.52
const FOOT_PLANTED := 0.30
## The planted joints, with the share of the cycle each stays down.
const JOINTS := {
	&"lowerarm_r": ELBOW_PLANTED,
	&"lowerarm_l": ELBOW_PLANTED,
	&"foot_l": FOOT_PLANTED,
	&"foot_r": FOOT_PLANTED,
}
const FEMALE := "res://assets/characters/mannequin/mannequin_female.glb"

var _arena: PlayArena
var _player: Player
var _prone: ProneTuning
var _animation: CharacterAnimation
var _actions: Array[StringName] = []


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	_player.prone_tuning = (
		(load("res://gameplay/player/prone_tuning.tres") as ProneTuning).duplicate()
	)
	_prone = _player.prone_tuning
	_animation = _player.get_node("Animation")
	_actions.clear()
	_animation.action_started.connect(_on_action_started)
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


func _on_action_started(clip: StringName) -> void:
	_actions.append(clip)


func _ticks(seconds: float) -> int:
	return ceili(seconds * Engine.physics_ticks_per_second) + 2


func _tap(code: Key) -> void:
	InputSim.key(code, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(code, false)
	await InputSim.ticks(get_tree(), 1)


func _lie_down() -> void:
	await _tap(KEY_Z)
	await InputSim.ticks(get_tree(), _ticks(_prone.enter_time))


func test_going_down_and_up_play_the_prone_clips_over_the_body() -> void:
	await _tap(KEY_Z)
	assert_array(_actions).contains([CharacterClips.TO_PRONE])
	await InputSim.ticks(get_tree(), _ticks(_prone.enter_time))
	assert_str(String(_animation.body_state())).is_equal(String(CharacterAnimation.PRONE))
	assert_str(String(_animation.prone_idle_clip)).is_equal(String(CharacterClips.PRONE_IDLE))
	assert_str(String(_animation.crawl_clip)).is_equal(String(CharacterClips.CRAWL))
	await _tap(KEY_Z)
	assert_array(_actions).contains([CharacterClips.TO_CROUCH])
	# Each transition is played to the stance's own time.
	var player: AnimationPlayer = _player.get_node("AnimationPlayer")
	for clip: StringName in [CharacterClips.TO_PRONE, CharacterClips.TO_CROUCH]:
		assert_bool(player.has_animation(clip)).override_failure_message(clip).is_true()


func test_no_pose_offset_moves_the_model_while_it_lies() -> void:
	var rig := (_player.get_node("Model") as CharacterModel).rig()
	await _lie_down()
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 30)
	assert_vector(rig.position).is_equal(Vector3.ZERO)
	assert_vector(rig.rotation).is_equal(Vector3.ZERO)
	for property in _animation.get_property_list():
		assert_bool(String(property["name"]).begins_with("prone_pose")).is_false()


func test_the_crawl_plays_at_the_pace_of_the_ground_and_backwards_backing_up() -> void:
	await _lie_down()
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), _ticks(1.5))
	var speed := _player.ground_speed()
	assert_float(speed).is_equal_approx(_prone.crawl_speed, 0.02)
	assert_float(_animation.crawl_pace()).is_equal_approx(speed / 0.618, 0.01)
	InputSim.key(KEY_W, false)
	# Aiming holds the body to the camera's heading, so pulling back crawls backwards.
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	InputSim.key(KEY_S, true)
	await InputSim.ticks(get_tree(), _ticks(1.0))
	assert_bool(_player.aiming).is_true()
	speed = _player.ground_speed()
	assert_float(speed).is_greater(0.1)
	assert_float(_animation.crawl_pace()).is_equal_approx(-speed / 0.618, 0.01)


# The planted joints keep their place on the floor at the slowest crawl the tuning allows, the
# default and the fastest: the tree is stepped by hand by the same time as the body, and the
# joint's best planted stretch (most of its planted share of the cycle) drifts under a centimetre.
func test_planted_elbows_and_feet_do_not_slide_at_any_crawl_speed() -> void:
	await _lie_down()
	var skeleton := (_player.get_node("Model") as CharacterModel).skeleton()
	_animation.set_throttled(true)
	for crawl_speed: float in [0.1, 1.0, 3.0]:
		_prone.crawl_speed = crawl_speed
		InputSim.key(KEY_W, true)
		var cycle := CRAWL_SECONDS * _animation.crawl_clip_speed / crawl_speed
		var samples: Dictionary = {}
		for joint: StringName in JOINTS:
			samples[joint] = []
		var settle := _ticks(1.5)
		var record := _ticks(cycle * 1.6)
		var step := 1.0 / Engine.physics_ticks_per_second
		for tick in settle + record:
			await get_tree().physics_frame
			_animation.advance(step)
			if tick < settle:
				continue
			for joint: StringName in JOINTS:
				var pose := skeleton.get_bone_global_pose(skeleton.find_bone(joint))
				(samples[joint] as Array).append(skeleton.global_transform * pose.origin)
		assert_float(_player.ground_speed()).is_equal_approx(crawl_speed, 0.02)
		for joint: StringName in JOINTS:
			var window := ceili(JOINTS[joint] * 0.7 * cycle / step)
			var drift := _best_stretch(samples[joint], window)
			(
				assert_float(drift)
				. override_failure_message(
					"%s slides %.4f m at %.1f m/s" % [joint, drift, crawl_speed]
				)
				. is_less(0.01)
			)
	_animation.set_throttled(false)


# The least a joint moves over the floor in any run of `window` samples: the largest flat
# distance from the run's first place.
func _best_stretch(places: Array, window: int) -> float:
	var best := INF
	for start in places.size() - window:
		var first: Vector3 = places[start]
		var drift := 0.0
		for index in range(start + 1, start + window + 1):
			var place: Vector3 = places[index]
			drift = maxf(drift, Vector2(place.x - first.x, place.z - first.z).length())
		best = minf(best, drift)
	return best


func test_the_weapon_is_put_away_lying_and_comes_back_to_aim() -> void:
	var hold := _animation.held_definition()
	var view := (_player.get_node("Model") as Node3D).get_node(hold.view) as Node3D
	assert_bool(view.visible).is_true()
	await _lie_down()
	await InputSim.ticks(get_tree(), 2)
	assert_bool(view.visible).is_false()
	assert_float(_animation.pistol_weights().x).is_equal_approx(0.0, 0.001)
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	await InputSim.ticks(get_tree(), _ticks(0.5))
	assert_bool(view.visible).is_true()
	assert_float(_animation.pistol_weights().x).is_greater(0.9)
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, false)
	await InputSim.ticks(get_tree(), _ticks(0.5))
	assert_bool(view.visible).is_false()
	await _tap(KEY_Z)
	await InputSim.ticks(get_tree(), _ticks(_prone.exit_time + 0.2))
	assert_bool(view.visible).is_true()


func test_a_model_can_play_prone_clips_of_its_own() -> void:
	var player: AnimationPlayer = _player.get_node("AnimationPlayer")
	var model := _player.get_node("Model") as CharacterModel
	var shared := player.get_animation_library(CharacterClips.LIBRARY_PRONE)
	var own := shared.duplicate() as AnimationLibrary
	assert_str(model.rig().scene_file_path).is_equal(FEMALE)
	_animation.prone_libraries = {FEMALE: own}
	model.rig_changed.emit(model.rig())
	assert_object(player.get_animation_library(CharacterClips.LIBRARY_PRONE)).is_same(own)
	assert_bool(player.has_animation(CharacterClips.CRAWL)).is_true()
	_animation.prone_libraries = {}
	model.rig_changed.emit(model.rig())
	assert_object(player.get_animation_library(CharacterClips.LIBRARY_PRONE)).is_same(shared)
