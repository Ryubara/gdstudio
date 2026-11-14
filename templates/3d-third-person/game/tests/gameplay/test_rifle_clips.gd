# The rifle clips (`assets/animation/rifle/rifle_clips.glb`, kit #1082): the library holds the seven
# clips at their lengths with the loops marked; every track finds its bone on both mannequins;
# a loop's last pose is its first, the shot starts and ends on the aim's first pose and the reload
# on the idle's; the arms the clips key are the hold's own on the mannequin they were keyed on (the
# build works the game's hold out in Python: this is the proof it is the same hold); and with a clip
# on the upper body over the standing or the crouched legs, both hands hold the rifle within the
# hold's limits on both mannequins through every clip (`RifleStage`, `HandContact`). The rifle
# definition names the clips, and the live player plays them: the idle on the upper body with the
# rifle out, the aim on top while aiming, the shot added on top of the aim, the reload by its key.
extends GdUnitTestSuite

const MODELS: Array[String] = ["female", "male"]
const LIBRARY := "res://assets/animation/rifle/rifle_clips.glb"
const RIFLE := "res://gameplay/weapon/rifle.tres"
## The build's data: each clip's length and loop, and the pose the clips were keyed over (`base`).
const DATA := "res://assets/animation/rifle/rifle_clips.json"
## Each clip's length in seconds and whether it loops.
const CLIPS: Dictionary[StringName, Array] = {
	&"Rifle_Idle": [3.0, true],
	&"Rifle_Aim_Neutral": [2.0, true],
	&"Rifle_Aim_Up": [2.0, true],
	&"Rifle_Aim_Down": [2.0, true],
	&"Rifle_Shoot": [0.4, false],
	&"Rifle_Reload": [2.2, false],
	&"Rifle_Reload_Empty": [2.2, false],
}
## What the hold is told while each clip plays: how far the rifle is up, the view's pitch in
## degrees, whether the clip's share is the reload's, and whether that reload pulls the charging
## handle (an empty magazine's, kit #1508).
const STATES: Dictionary[StringName, Array] = {
	&"Rifle_Idle": [0.0, 0.0, false, false],
	&"Rifle_Aim_Neutral": [1.0, 0.0, false, false],
	&"Rifle_Aim_Up": [1.0, 45.0, false, false],
	&"Rifle_Aim_Down": [1.0, -45.0, false, false],
	&"Rifle_Shoot": [1.0, 0.0, false, false],
	&"Rifle_Reload": [0.0, 0.0, true, false],
	&"Rifle_Reload_Empty": [0.0, 0.0, true, true],
}
## Where the two reloads part (the magazine seated) and where the empty one's bolt is let go, as
## shares of the reload (`build_rifle_clips.py`: `RELOAD_KEYS`, `RELOAD_EMPTY_JOLTS`).
const RELOADS_PART := 0.62
const BOLT_LET_GO := 0.86
## The legs the clips are tried over, each at its first frame.
const LEGS: Array[StringName] = [CharacterClips.IDLE, CharacterClips.CROUCH_IDLE]
## The bone the clips take the body from in the game (`CharacterAnimation.upper_body_bone`).
const UPPER := &"spine_01"
## How far the clip's own hand may be from the hold's place on the mannequin it was keyed on, in
## metres.
const OWN_ARMS := 0.003
## How far a hand's bone may be from its place on the rifle after the hold, in metres.
const REACH := 0.005
## Degrees two poses that should be one may differ by, a bone.
const SAME_POSE := 0.1

var _holder: Node3D
var _arena: PlayArena
var _player: Player


func before_test() -> void:
	InputSim.release_all()
	_holder = auto_free(Node3D.new())
	add_child(_holder)


func after_test() -> void:
	InputSim.release_all()
	if _arena != null:
		AudioDrain.stop_all(_arena)
	_arena = null


func test_the_library_holds_the_seven_clips_and_every_track_finds_its_bone() -> void:
	var library := load(LIBRARY) as AnimationLibrary
	assert_object(library).is_not_null()
	var names: Array[String] = []
	for clip_name in library.get_animation_list():
		names.append(String(clip_name))
	names.sort()
	var wanted: Array[String] = []
	for clip_name in CLIPS:
		wanted.append(String(clip_name))
	wanted.sort()
	assert_array(names).is_equal(wanted)
	for model in MODELS:
		var stage := RifleStage.make_rifle(_holder, model, false)
		for clip_name in CLIPS:
			var clip := library.get_animation(clip_name)
			assert_float(clip.length).is_equal_approx(CLIPS[clip_name][0], 0.001)
			var loops := clip.loop_mode == Animation.LOOP_LINEAR
			assert_bool(loops).override_failure_message("%s loop" % clip_name).is_equal(
				CLIPS[clip_name][1]
			)
			var turned := 0
			for track in clip.get_track_count():
				var bone := String(clip.track_get_path(track).get_concatenated_subnames())
				(
					assert_int(stage.skeleton.find_bone(bone))
					. override_failure_message(
						"%s: no bone %s on the %s" % [clip_name, bone, model]
					)
					. is_greater_equal(0)
				)
				turned += int(clip.track_get_type(track) == Animation.TYPE_ROTATION_3D)
			assert_int(turned).is_greater(40)
		stage.free()


func test_loops_close_and_the_shot_and_the_reload_join_the_poses_they_leave() -> void:
	var library := load(LIBRARY) as AnimationLibrary
	for clip_name in CLIPS:
		if CLIPS[clip_name][1]:
			var clip := library.get_animation(clip_name)
			_assert_same_pose(clip, 0.0, clip, clip.length, String(clip_name) + " loop")
	var shot := library.get_animation(&"Rifle_Shoot")
	var aim := library.get_animation(&"Rifle_Aim_Neutral")
	_assert_same_pose(shot, 0.0, aim, 0.0, "the shot's start")
	_assert_same_pose(shot, shot.length, aim, 0.0, "the shot's end")
	var reload := library.get_animation(&"Rifle_Reload")
	var idle := library.get_animation(&"Rifle_Idle")
	_assert_same_pose(reload, 0.0, idle, 0.0, "the reload's start")
	_assert_same_pose(reload, reload.length, idle, 0.0, "the reload's end")
	var empty := library.get_animation(&"Rifle_Reload_Empty")
	_assert_same_pose(empty, 0.0, idle, 0.0, "the empty reload's start")
	_assert_same_pose(empty, empty.length, idle, 0.0, "the empty reload's end")


# The two reloads are one up to the seated magazine; after it only the empty one's body has the
# beat for the charging handle: its chest jolts where the bolt is let go, the tactical's does not.
func test_only_the_empty_reload_has_the_bolts_beat() -> void:
	var library := load(LIBRARY) as AnimationLibrary
	var tactical := library.get_animation(&"Rifle_Reload")
	var empty := library.get_animation(&"Rifle_Reload_Empty")
	var frame := 1.0 / 30.0
	var at := 0.0
	while at <= RELOADS_PART * tactical.length + 0.0001:
		_assert_same_pose(tactical, at, empty, at, "the reloads at %.2f s" % at)
		at += frame
	var jolts := {}
	for clip: Animation in [tactical, empty]:
		# The chest's turn a frame against the straight way between its neighbours: a jolt is a
		# frame or two off that way.
		var track := _track(clip, "spine_03")
		var worst := 0.0
		var middle := roundf(BOLT_LET_GO * clip.length / frame) * frame
		for step in range(-3, 4):
			var t := middle + step * frame
			var before := clip.rotation_track_interpolate(track, t - frame)
			var after := clip.rotation_track_interpolate(track, t + frame)
			var here := clip.rotation_track_interpolate(track, t)
			worst = maxf(worst, rad_to_deg(here.angle_to(before.slerp(after, 0.5))))
		jolts[clip] = worst
	prints(
		(
			"RIFLE_CLIPS chest off its way by the bolt: tactical %.3f, empty %.3f degrees"
			% [jolts[tactical], jolts[empty]]
		)
	)
	assert_float(jolts[empty]).is_greater(0.3)
	assert_float(jolts[tactical]).is_less(jolts[empty] * 0.25)


func test_the_clips_own_arms_are_the_holds_on_the_mannequin_they_were_keyed_on() -> void:
	var stage := RifleStage.make_rifle(_holder, "female")
	var worst := 0.0
	# The clips key each bone in its parent, so their arms are the hold's over the pelvis they were
	# keyed on: the standing idle on its steadiest frame, which the game holds under an aim.
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA)).base
	assert_str(base.clip).is_equal(String(CharacterClips.IDLE))
	for clip_name in CLIPS:
		# The shot's kick is the hold's own and is not posed here: its first and last frames only.
		var shares: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0]
		if clip_name == &"Rifle_Shoot":
			shares = [0.0, 1.0]
		var frames: float = roundf(CLIPS[clip_name][0] * 30.0)
		for at in shares:
			# On a key of the clip: between two keys a fast hand is a chord off its arc.
			var share := roundf(at * frames) / frames
			_pose(stage, CharacterClips.IDLE, clip_name, share, base.seconds)
			await stage.settle()
			for side: String in ["r", "l"]:
				# The skeleton holds the clip's pose again once its modifiers have run.
				var bone := stage.skeleton.find_bone("hand_" + side)
				var own := (
					stage.skeleton.global_transform
					* HandPoseModifier.global_pose(stage.skeleton, bone).origin
				)
				var held := stage.bone_origin("hand_" + side)
				var off := own.distance_to(held)
				worst = maxf(worst, off)
				(
					assert_float(off)
					. override_failure_message(
						(
							"%s at %.2f: the clip's own hand_%s is %.1f mm from the hold's"
							% [clip_name, share, side, off * 1e3]
						)
					)
					. is_less(OWN_ARMS)
				)
	prints("RIFLE_CLIPS own arms, worst %.2f mm" % (worst * 1e3))
	stage.free()


func test_both_hands_hold_the_rifle_through_every_clip_on_both_mannequins() -> void:
	for model in MODELS:
		var stage := RifleStage.make_rifle(_holder, model)
		var hold := stage.hold as TwoHandHold
		for legs in LEGS:
			for clip_name in CLIPS:
				var share := 0.0
				while share <= 1.0001:
					_pose(stage, legs, clip_name, share)
					await stage.settle()
					var tag := "%s %s over %s at %.2f" % [model, clip_name, legs, share]
					_assert_hand(stage, "r", tag, RifleStage.RIFLE_RIGHT_CONTACTS)
					var away: bool = (
						STATES[clip_name][2]
						and share > hold.reload_leave.x
						and share < hold.reload_return.y
					)
					if away:
						# The left hand is on its way: its bone is where the hold takes it.
						var gap := stage.hand_gap("l")
						(
							assert_float(gap)
							. override_failure_message(
								"%s: the left hand is %.1f mm off its way" % [tag, gap * 1e3]
							)
							. is_less(REACH)
						)
					else:
						_assert_hand(stage, "l", tag, RifleStage.RIFLE_LEFT_CONTACTS)
					share += 0.125
		stage.free()


func test_the_rifle_names_its_clips_and_the_player_plays_them() -> void:
	var rifle := load(RIFLE) as WeaponDef
	assert_str(String(rifle.grip_clip)).is_equal(String(CharacterClips.RIFLE_IDLE))
	assert_str(String(rifle.aim_clip)).is_equal(String(CharacterClips.RIFLE_AIM))
	assert_str(String(rifle.aim_up_clip)).is_equal(String(CharacterClips.RIFLE_AIM_UP))
	assert_str(String(rifle.aim_down_clip)).is_equal(String(CharacterClips.RIFLE_AIM_DOWN))
	assert_str(String(rifle.reload_clip)).is_equal(String(CharacterClips.RIFLE_RELOAD))
	assert_str(String(rifle.empty_reload_clip)).is_equal(String(CharacterClips.RIFLE_RELOAD_EMPTY))
	assert_array(rifle.shoot_clips).contains_exactly([CharacterClips.RIFLE_SHOOT])
	assert_bool(rifle.shoot_additive).is_true()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	var view := Camera3D.new()
	view.position = Vector3(0.0, 1.3, 3.0)
	_arena.add_child(view)
	view.make_current()
	await InputSim.ticks(get_tree(), 10)
	_player.loadout.give(rifle, 60)
	await InputSim.ticks(get_tree(), 60)
	var animation := _player.get_node("Animation") as CharacterAnimation
	var skeleton := _player.model.skeleton()
	var library := load(LIBRARY) as AnimationLibrary
	# Standing with the rifle out: the upper body is the idle clip's (the head's turn in the
	# neck is the clip's own, which no locomotion clip has).
	assert_float(animation.pistol_weights().x).is_equal_approx(1.0, 0.01)
	assert_float(animation.pistol_weights().y).is_equal_approx(0.0, 0.01)
	var neck := skeleton.find_bone(&"neck_01")
	var idle := library.get_animation(&"Rifle_Idle")
	var idle_neck := idle.rotation_track_interpolate(_track(idle, "neck_01"), 0.0)
	assert_float(rad_to_deg(skeleton.get_bone_pose_rotation(neck).angle_to(idle_neck))).is_less(3.0)
	# Aiming: the aim clip on top.
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	await InputSim.ticks(get_tree(), 40)
	assert_float(animation.pistol_weights().y).is_equal_approx(1.0, 0.01)
	var aim := library.get_animation(&"Rifle_Aim_Neutral")
	var aim_neck := aim.rotation_track_interpolate(_track(aim, "neck_01"), 0.0)
	var aimed_neck := skeleton.get_bone_pose_rotation(neck)
	assert_float(rad_to_deg(aimed_neck.angle_to(aim_neck))).is_less(3.0)
	# A shot: added on top of the aim, so the chest rocks back from the aim's pose and the
	# aim's pose is under it again afterwards.
	var chest := skeleton.find_bone(&"spine_03")
	var still := skeleton.get_bone_pose_rotation(chest)
	var rocked := 0.0
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
	for tick in 8:
		await InputSim.ticks(get_tree(), 1)
		rocked = maxf(rocked, rad_to_deg(skeleton.get_bone_pose_rotation(chest).angle_to(still)))
	(
		assert_float(rocked)
		. override_failure_message("the shot rocked the chest %.2f degrees" % rocked)
		. is_between(0.3, 4.0)
	)
	await InputSim.ticks(get_tree(), 40)
	var settled := rad_to_deg(skeleton.get_bone_pose_rotation(chest).angle_to(still))
	(
		assert_float(settled)
		. override_failure_message("the chest is %.2f degrees off after the shot" % settled)
		. is_less(0.4)
	)
	assert_int(_player.weapon.ammo).is_less(30)
	# The reload by its key: the clip holds the upper body.
	InputSim.release_all()
	await InputSim.ticks(get_tree(), 30)
	InputSim.key(KEY_R, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_R, false)
	await InputSim.ticks(get_tree(), 40)
	assert_bool(animation.is_reloading()).is_true()
	assert_float(animation.reload_progress().x).is_equal_approx(1.0, 0.01)
	# Lying down: the clips stand the trunk from the pelvis, so the prone clips keep the body and
	# the hold alone carries the rifle, aimed or not, and a reload plays no clip.
	assert_bool(rifle.clips_upright).is_true()
	InputSim.release_all()
	await InputSim.ticks(get_tree(), 150)
	InputSim.key(KEY_Z, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_Z, false)
	await InputSim.ticks(get_tree(), 90)
	assert_float(_player.prone_amount).is_equal_approx(1.0, 0.01)
	assert_float(animation.pistol_weights().x).is_equal_approx(0.0, 0.01)
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	await InputSim.ticks(get_tree(), 40)
	assert_float(animation.pistol_weights().length()).is_equal_approx(0.0, 0.01)
	var holds := _player.model.find_children("*", "TwoHandHold", true, false)
	assert_float((holds[0] as TwoHandHold).weight()).is_equal_approx(1.0, 0.01)
	InputSim.key(KEY_R, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_R, false)
	await InputSim.ticks(get_tree(), 20)
	assert_bool(animation.is_reloading()).is_false()


# Puts `legs` at `legs_time` (its first frame unless said) on the whole body, then the rifle clip at
# `share` of its length on the upper body, and tells the hold what the game would while that clip
# plays.
func _pose(
	stage: RifleStage, legs: StringName, clip_name: StringName, share: float, legs_time := 0.0
) -> void:
	var held := stage.hold as TwoHandHold
	var state: Array = STATES[clip_name]
	held.posed_aim = state[0]
	held.posed_pitch = state[1]
	held.posed_reload = share if state[2] and share > 0.0 and share < 1.0 else -1.0
	held.charge_bolt.posed_pulls = state[3]
	held.posed_lowered = 0.0
	var kept := stage.hold
	stage.hold = null
	stage.pose(legs, legs_time)
	stage.hold = kept
	var clip := (load(LIBRARY) as AnimationLibrary).get_animation(clip_name)
	var start := stage.skeleton.find_bone(UPPER)
	for track in clip.get_track_count():
		if clip.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := stage.skeleton.find_bone(
			String(clip.track_get_path(track).get_concatenated_subnames())
		)
		var cursor := bone
		while cursor >= 0 and cursor != start:
			cursor = stage.skeleton.get_bone_parent(cursor)
		if cursor >= 0:
			stage.skeleton.set_bone_pose_rotation(
				bone, clip.rotation_track_interpolate(track, share * clip.length)
			)
	held.refresh()


func _track(clip: Animation, bone: String) -> int:
	for track in clip.get_track_count():
		if (
			clip.track_get_type(track) == Animation.TYPE_ROTATION_3D
			and String(clip.track_get_path(track).get_concatenated_subnames()) == bone
		):
			return track
	return -1


func _assert_same_pose(a: Animation, at_a: float, b: Animation, at_b: float, tag: String) -> void:
	var worst := 0.0
	var where := ""
	for track in a.get_track_count():
		if a.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := String(a.track_get_path(track).get_concatenated_subnames())
		var other := _track(b, bone)
		if other < 0:
			continue
		var off := rad_to_deg(
			a.rotation_track_interpolate(track, at_a).angle_to(
				b.rotation_track_interpolate(other, at_b)
			)
		)
		if off > worst:
			worst = off
			where = bone
	(
		assert_float(worst)
		. override_failure_message("%s: %s is %.3f degrees off" % [tag, where, worst])
		. is_less(SAME_POSE)
	)


# One hand: its bone on its place and its skin within the hold's limits.
func _assert_hand(stage: RifleStage, side: String, tag: String, contacts: Array[String]) -> void:
	var gap := stage.hand_gap(side)
	(
		assert_float(gap)
		. override_failure_message("%s: hand_%s is %.1f mm from its place" % [tag, side, gap * 1e3])
		. is_less(REACH)
	)
	var fails := HandContact.failures("%s %s:" % [tag, side], stage.contact.measure(side), contacts)
	assert_array(fails).override_failure_message("\n".join(fails)).is_empty()
