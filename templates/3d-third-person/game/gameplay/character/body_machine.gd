class_name BodyMachine
extends RefCounted
## The body's state machine of the `CharacterAnimation`'s tree (its `Locomotion` node): a state for
## each of `CharacterAnimation.GROUND`, `JUMP`, `FALL`, `LAND`, `PUSH`, `CROUCH`, `PRONE`,
## `SLIDE_START`, `SLIDE` and `SLIDE_EXIT`, each joined to every other by a cross-fade of
## `blend_time` (`CharacterGait.xfade()`), the slide's start and exit going on by themselves at
## their end. `state_for()` says which state a `Character.State` travels to. The animation owns one
## and builds it again with the tree.

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
	_add(CharacterAnimation.JUMP, animation.jump_clip, Vector2(400, -100))
	_add(CharacterAnimation.FALL, animation.air_clip, Vector2(600, 0))
	_add(CharacterAnimation.LAND, animation.land_clip, Vector2(400, 100))
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
	_add(CharacterAnimation.SLIDE_EXIT, animation.slide_exit_clip, Vector2(-200, -100))
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


# A cross-fade of `xfade` seconds from `from` to `to`; `at_end` waits for `from`'s clip to end and
# goes on by itself.
func _link(from: StringName, to: StringName, xfade: float, at_end: bool) -> void:
	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = xfade
	if at_end:
		transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
		transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	machine.add_transition(from, to, transition)
