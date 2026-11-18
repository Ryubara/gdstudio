class_name BodyMachine
extends RefCounted
## The body's state machine of the `CharacterAnimation`'s tree (its `Locomotion` node): a state for
## each of `CharacterAnimation.GROUND`, `JUMP`, `FALL`, `LAND`, `PUSH`, `CROUCH`, `PRONE`,
## `SLIDE_START`, `SLIDE` and `SLIDE_EXIT`, each joined to every other by a cross-fade of
## `blend_time` (`CharacterGait.xfade()`), the slide's start and exit going on by themselves at
## their end. `state_for()` says which state a `Character.State` travels to. The animation owns one
## and builds it again with the tree.

## Steps over the slide's exit at which its pelvis height is read for `seek_exit()`.
const EXIT_SAMPLES := 40
## Metres over the exit's lowest pelvis under which a body counts as lying: its exit starts at the
## first frame.
const EXIT_LYING := 0.15
## The share of the slide's exit over which its body rises from lying to the run.
const EXIT_RISE := Vector2(0.2, 0.85)
const _P_EXIT_SEEK := &"parameters/Locomotion/slide_exit/Seek/seek_request"
const _P_EXIT_AT := &"parameters/Locomotion/slide_exit/Clip/current_position"
const _P_EXIT_LENGTH := &"parameters/Locomotion/slide_exit/Clip/current_length"

## The machine last built.
var machine: AnimationNodeStateMachine


## Which state of the machine a character in `state` travels to, `current` the one it is in (a
## character standing up from a slide plays the slide's exit first). Empty for `DEAD`.
static func state_for(state: Character.State, current: StringName) -> StringName:
	match state:
		Character.State.IDLE, Character.State.WALK, Character.State.RUN:
			var sliding := current == CharacterAnimation.SLIDE
			sliding = sliding or current == CharacterAnimation.SLIDE_START
			return CharacterAnimation.SLIDE_EXIT if sliding else CharacterAnimation.GROUND
		Character.State.JUMP:
			return CharacterAnimation.JUMP
		Character.State.FALL:
			return CharacterAnimation.FALL
		Character.State.LAND:
			return CharacterAnimation.LAND
		Character.State.PUSH:
			return CharacterAnimation.PUSH
		Character.State.CROUCH:
			return CharacterAnimation.CROUCH
		Character.State.SLIDE:
			return CharacterAnimation.SLIDE_START
		Character.State.PRONE:
			return CharacterAnimation.PRONE
	return &""


## Builds the machine from `animation`'s clips; `brace` gives the ground state its idle point.
func build(animation: CharacterAnimation, brace: AimBrace.Driver) -> AnimationNodeStateMachine:
	machine = AnimationNodeStateMachine.new()
	var ground := animation.gait.build_ground(
		animation, brace.stance.idle_point(animation, animation.idle_clip)
	)
	machine.add_node(CharacterAnimation.GROUND, ground, Vector2(200, 0))
	animation.gait.add_jump(animation, machine)  # the jump: `JumpAnimation`
	_add(CharacterAnimation.PUSH, animation.push_clip, Vector2(200, 160))
	var crouch := animation.gait.build_crouch(animation)
	machine.add_node(CharacterAnimation.CROUCH, crouch, Vector2(0, 160))
	var upper := TreeParts.bone_paths(animation.animation_player, [animation.upper_body_bone])
	var prone := ProneAnimation.build(
		animation.prone_idle_clip, animation.crawl_clip, animation.held_definition(), upper
	)
	machine.add_node(CharacterAnimation.PRONE, prone, Vector2(0, 320))
	_add(CharacterAnimation.SLIDE_START, animation.slide_start_clip, Vector2(-200, 0))
	_add(CharacterAnimation.SLIDE, animation.slide_clip, Vector2(-200, 160))
	machine.add_node(CharacterAnimation.SLIDE_EXIT, _exit(animation), Vector2(-200, -100))
	var start := AnimationNodeStateMachineTransition.new()
	start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	machine.add_transition(&"Start", CharacterAnimation.GROUND, start)
	# A clip that plays once and goes on by itself: the slide's start into its loop, its exit
	# into the ground.
	var ends := {
		CharacterAnimation.SLIDE_START: CharacterAnimation.SLIDE,
		CharacterAnimation.SLIDE_EXIT: CharacterAnimation.GROUND,
	}
	var states := [
		CharacterAnimation.GROUND,
		CharacterAnimation.JUMP,
		CharacterAnimation.FALL,
		CharacterAnimation.LAND,
		CharacterAnimation.PUSH,
		CharacterAnimation.CROUCH,
		CharacterAnimation.PRONE,
		CharacterAnimation.SLIDE_START,
		CharacterAnimation.SLIDE,
		CharacterAnimation.SLIDE_EXIT,
	]
	var xfade := animation.gait.xfade(animation)
	for from: StringName in states:
		for to: StringName in states:
			if from != to:
				_link(from, to, xfade, ends.get(from, &"") == to)
	return machine


func _add(state: StringName, clip: StringName, at: Vector2) -> void:
	machine.add_node(state, TreeParts.clip(clip), at)


## Starts the slide's exit (just travelled to) where its pelvis is as high as the drawn one, past
## its lowest: an exit from a slide that had not yet laid the body down played from lying, so the
## body dropped to the floor and rose again, the trunk 0.15 m a tick (gdstudio #1577). From lying
## (`EXIT_LYING`) it starts at its first frame.
static func seek_exit(animation: CharacterAnimation) -> void:
	var skeleton := animation.model.skeleton() if is_instance_valid(animation.model) else null
	var player := animation.animation_player
	if skeleton == null or not player.has_animation(animation.slide_exit_clip):
		return
	var pelvis := skeleton.find_bone(&"pelvis")
	var clip := player.get_animation(animation.slide_exit_clip)
	var track := -1
	for index in clip.get_track_count():
		var path := clip.track_get_path(index)
		if (
			clip.track_get_type(index) == Animation.TYPE_POSITION_3D
			and path.get_concatenated_subnames() == "pelvis"
		):
			track = index
	if pelvis < 0 or track < 0 or clip.length <= 0.0:
		return
	# Heights in the skeleton's space: the pelvis's own place is in its parent's (the root's) axes.
	var parent := skeleton.get_bone_parent(pelvis)
	var base := skeleton.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
	var drawn := (base * skeleton.get_bone_pose_position(pelvis)).y
	var steps := EXIT_SAMPLES
	var lowest := 0
	var heights := PackedFloat32Array()
	for step in steps + 1:
		var place := clip.position_track_interpolate(track, clip.length * step / steps)
		heights.append((base * place).y)
		if heights[step] < heights[lowest]:
			lowest = step
	# Within `EXIT_LYING` of the exit's lowest the body lies as the exit begins, and its first frame
	# meets the slide (a seek on the pelvis alone landed in another pose: 0.12 m a tick).
	if drawn < heights[lowest] + EXIT_LYING:
		return
	var at := lowest
	while at < steps and heights[at] < drawn:
		at += 1
	var share := float(at) / steps
	var stretched := animation.slide_exit_time if animation.slide_exit_time > 0.0 else clip.length
	animation.tree.set(_P_EXIT_SEEK, share * stretched)


## How far the drawn body still lies in the slide's exit, 0 to 1 (0 out of it): 1 at the exit's
## first frame, eased to 0 over its rise (`EXIT_RISE`, shares of the clip).
static func exit_lying(animation: CharacterAnimation) -> float:
	if animation.body_state() != CharacterAnimation.SLIDE_EXIT or animation.tree == null:
		return 0.0
	var length: float = animation.tree.get(_P_EXIT_LENGTH)
	var at: float = animation.tree.get(_P_EXIT_AT)
	return 1.0 - smoothstep(EXIT_RISE.x, EXIT_RISE.y, at / length if length > 0.0 else 1.0)


# The slide's exit: its clip, stretched to `CharacterAnimation.slide_exit_time` (its rise from
# lying took a quarter of a second at its own pace and read as a pop, gdstudio #1577), behind a
# seek (`seek_exit()`).
func _exit(animation: CharacterAnimation) -> AnimationNodeBlendTree:
	var clip := TreeParts.clip(animation.slide_exit_clip)
	if animation.slide_exit_time > 0.0:
		clip.use_custom_timeline = true
		clip.timeline_length = animation.slide_exit_time
		clip.stretch_time_scale = true
		clip.loop_mode = Animation.LOOP_NONE
	var exit := AnimationNodeBlendTree.new()
	exit.add_node(&"Clip", clip, Vector2(0, 0))
	exit.add_node(&"Seek", AnimationNodeTimeSeek.new(), Vector2(200, 0))
	exit.connect_node(&"Seek", 0, &"Clip")
	exit.connect_node(&"output", 0, &"Seek")
	return exit


# A cross-fade of `xfade` seconds from `from` to `to`; `at_end` waits for `from`'s clip to end and
# goes on by itself.
func _link(from: StringName, to: StringName, xfade: float, at_end: bool) -> void:
	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = xfade
	if at_end:
		transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
		transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	machine.add_transition(from, to, transition)
