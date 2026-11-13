class_name GaitTransitions
extends RefCounted
## The starts, stops, reversals, pivots and turns on the spot of `CharacterAnimation` (gdstudio
## #1158), chosen by code from the controller's own numbers and played along their travel.
##
## Every frame on the ground it reads the body: its ground speed, the speed its last command heads
## for (`Character.goal_speed`), the angle between where it moves and where it is asked to go,
## and, aiming while standing, how far its facing is asked to turn. A body that stands and is
## asked to move starts; one that moves and is asked to stop stops; one asked to go back the way
## it came reverses, or pivots at a smaller angle; one that stands and aims away turns on the
## spot. The clip is the `GaitTransitionSet`'s for the gait (the ground blend space's point the
## body is in, or heads for) and the side: the foot that lands next in the gait's phase for a stop,
## the foot on the side it turns to for a reversal, the way the body turns for a pivot and a turn.
## With no such clip in the libraries nothing happens and the states blend as before.
##
## A clip plays in the machine's `gait_transition` state behind a seek and a time scale of 0, so
## only the seek moves it: to the time at which its travel curve (`GaitClips`) has covered the
## ground the body really covered since it began, and for a turn on the spot the time at which its
## turn curve has turned as far as the body. A reversal or a pivot of a body that steps is the
## body's own (`CharacterTurnMotion`, gdstudio #1442): the step starts it and moves the body by the
## clip's root, and the clip is shown at the step's time into it; one picked here (a body drawn
## from the network, or `CharacterTuning.turn_root_motion` off) plays at its own pace. The
## controller stays the authority: a body that is asked to go on, or to do something else, leaves
## the clip at once (the momentum blend smooths the cut), and a clip whose body has finished its
## part plays on to its end at its own pace. Ending,
## it hands over to the gait at the phase its record names (`exit_phase`, or the foot it ends
## on). Nothing here is sent: each machine works it out from the body it draws.

enum Kind { NONE, START, STOP, REVERSAL, PIVOT, TURN }

## The state in the body machine.
const STATE := &"gait_transition"
const CLIP := &"Clip"
const SEEK := &"Seek"
const HOLD := &"Hold"
const _P_SEEK := &"parameters/Locomotion/gait_transition/Seek/seek_request"
const _P_HOLD := &"parameters/Locomotion/gait_transition/Hold/scale"
## Degrees of turn left before a turning body counts as done with its part.
const TURN_DONE := 5.0

var settings: GaitSettings
## What plays now, and its clip.
var kind := Kind.NONE
var clip: StringName = &""
## Rises by one each time a transition begins or ends (the momentum blend starts from it).
var serial := 0

var _node: AnimationNodeAnimation
var _any := false
var _time := 0.0
var _length := 0.0
var _from := Vector3.ZERO
var _along := Vector3.FORWARD
var _facing := 0.0
var _turn_to := 0.0
var _pending := false
var _motion_serial := 0


## The state's node: the clip behind a seek and a time scale of 0.
func build_state() -> AnimationNodeBlendTree:
	var node := AnimationNodeBlendTree.new()
	_node = AnimationNodeAnimation.new()
	_node.loop_mode = Animation.LOOP_NONE
	node.add_node(CLIP, _node, Vector2(0, 0))
	node.add_node(SEEK, AnimationNodeTimeSeek.new(), Vector2(200, 0))
	node.add_node(HOLD, AnimationNodeTimeScale.new(), Vector2(400, 0))
	node.connect_node(SEEK, 0, CLIP)
	node.connect_node(HOLD, 0, SEEK)
	node.connect_node(&"output", 0, HOLD)
	return node


## Holds the state's clip still but for the seek, and notes whether `player` holds any of the
## set's clips (with none, a frame asks nothing of the body): once, after the tree is built.
func hold(tree: AnimationTree, player: AnimationPlayer) -> void:
	tree.set(_P_HOLD, 0.0)
	_any = false
	var clips := settings.transition_clips if settings != null else null
	if clips == null or player == null:
		return
	var bases: Array[StringName] = [clips.turn_quarter, clips.turn_half]
	for table: Dictionary[StringName, StringName] in [
		clips.starts, clips.stops, clips.reversals, clips.pivots
	]:
		bases.append_array(table.values())
	for base in bases:
		for side in ["", "l", "r"]:
			_any = _any or GaitTransitionSet.pick(player, base, side) != &""


## True while a transition clip plays.
func is_playing() -> bool:
	return kind != Kind.NONE


## The state the machine goes to when `CharacterAnimation` asks for `state`: a transition that
## plays keeps the body while the ground is asked for (it hands over by itself); anything else
## ends it.
func route(state: StringName) -> StringName:
	if not is_playing():
		return state
	if state == CharacterAnimation.GROUND:
		return STATE
	_end()
	return state


## One frame: goes on with the clip that plays, or starts one the body calls for.
func step(
	animation: CharacterAnimation,
	blend: GaitBlend,
	playback: AnimationNodeStateMachinePlayback,
	delta: float
) -> void:
	if _began_by_step(animation, playback) or _went_on(animation, blend, playback, delta):
		return
	var current := playback.get_current_node()
	if current == STATE:
		playback.travel(CharacterAnimation.GROUND)  # Left there by a rebuild of the tree.
		return
	if (
		not _any
		or settings == null
		or not settings.transitions
		or settings.transition_clips == null
	):
		return
	# The cheap checks first: reading the tree's action parameter costs more than the rest.
	if current != CharacterAnimation.GROUND or not on_foot(animation.character):
		return
	if animation.is_acting():
		return
	var picked := pick(animation, blend)
	if picked.is_empty():
		return
	_begin(animation, picked, playback)


## True while the body stands, walks or runs: a push, a vault or a hit begins on a frame the
## machine is still in the ground state, and a start picked then would take the body from it.
static func on_foot(body: Character) -> bool:
	return (
		body.state == Character.State.IDLE
		or body.state == Character.State.WALK
		or body.state == Character.State.RUN
	)


## The transition the body calls for now, as `{kind, clip}`, or empty: what `step()` would start.
func pick(animation: CharacterAnimation, blend: GaitBlend) -> Dictionary:
	var body := animation.character
	if body.ground_speed() < settings.standing_speed:
		return _pick_standing(animation, blend)
	return _pick_moving(animation, blend)


# A start, or aiming away while standing, a turn on the spot.
func _pick_standing(animation: CharacterAnimation, blend: GaitBlend) -> Dictionary:
	var body := animation.character
	var clips := settings.transition_clips
	var player := animation.animation_player
	var goal := body.goal_speed
	var picked := {}
	if goal > settings.standing_speed:
		var wish := body.last_command.world_move()
		var forward := Vector3.BACK.rotated(Vector3.UP, body.facing)
		var gait := blend.main_point(CharacterAnimation.GROUND, goal)
		var side := "r" if forward.cross(wish).y < 0.0 else "l"
		picked = _found(Kind.START, GaitTransitionSet.pick_in(player, clips.starts, gait, side))
	elif body.aiming:
		var turn := rad_to_deg(wrapf(body.view_yaw + PI - body.facing, -PI, PI))
		if absf(turn) >= settings.turn_angle:
			var base := clips.turn_half if absf(turn) >= 135.0 else clips.turn_quarter
			var side := "l" if turn > 0.0 else "r"
			picked = _found(Kind.TURN, GaitTransitionSet.pick(player, base, side))
	return picked


# A stop, a reversal or a pivot of a moving body. A body going on its way (most frames of a
# walking crowd) asks for none, so the gait and the foot are looked up only once one is called for
# (gdstudio #1360: looked up first, they were a third of a walking character's animation script).
func _pick_moving(animation: CharacterAnimation, blend: GaitBlend) -> Dictionary:
	var body := animation.character
	var clips := settings.transition_clips
	var player := animation.animation_player
	var speed := body.ground_speed()
	if body.goal_speed <= settings.standing_speed:
		var stop_point := blend.main_point(CharacterAnimation.GROUND, speed)
		var stop_foot := _foot(animation, blend, speed)
		return _found(
			Kind.STOP, GaitTransitionSet.pick_in(player, clips.stops, stop_point, stop_foot)
		)
	if body.turn_motion.follows(body):
		return {}  # The step starts its reversals and pivots (`step()` follows them).
	var wish := body.last_command.world_move()
	var moving := Vector3(body.velocity.x, 0.0, body.velocity.z).normalized()
	var angle := rad_to_deg(moving.angle_to(wish))
	if angle < settings.reversal_angle and angle < settings.pivot_angle:
		return {}
	var point := blend.main_point(CharacterAnimation.GROUND, speed)
	if angle >= settings.reversal_angle:
		# A reversal turns over the foot it plants (#1157: planting the left foot it turns to the
		# left), so the clip that turns the body's way is the one for the foot on that side.
		var plant := "r" if moving.cross(wish).y < 0.0 else "l"
		return _found(
			Kind.REVERSAL, GaitTransitionSet.pick_in(player, clips.reversals, point, plant)
		)
	var side := "r" if moving.cross(wish).y < 0.0 else "l"
	return _found(Kind.PIVOT, GaitTransitionSet.pick_in(player, clips.pivots, point, side))


# The foot that lands next in the ground gait that weighs most at `speed`.
func _foot(animation: CharacterAnimation, blend: GaitBlend, speed: float) -> String:
	var gait_clip := blend.main_gait(CharacterAnimation.GROUND, speed)
	return next_foot(gait_clip, blend.phase(animation.tree, CharacterAnimation.GROUND))


## The foot that lands next at `phase` (0 to 1) of `gait`'s cycle: the one whose contact begins
## soonest after it. `"l"` without a record.
static func next_foot(gait: StringName, phase: float) -> String:
	var best := "l"
	var soonest := INF
	for foot: String in ["l", "r"]:
		for window: Array in GaitClips.contacts(gait, foot):
			var ahead := fposmod(float(window[0]) - phase, 1.0)
			if ahead > 0.0001 and ahead < soonest:
				soonest = ahead
				best = foot
	return best


## Where the clip is now, in seconds.
func time() -> float:
	return _time


func _found(found: Kind, picked: StringName) -> Dictionary:
	return {} if picked == &"" else {"kind": found, "clip": picked}


func _begin(
	animation: CharacterAnimation, picked: Dictionary, playback: AnimationNodeStateMachinePlayback
) -> void:
	var body := animation.character
	kind = picked.kind
	clip = picked.clip
	serial += 1
	_node.animation = clip
	_length = animation.animation_player.get_animation(clip).length
	_time = 0.0
	_from = body.global_position
	_facing = body.facing
	var moving := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var wish := body.last_command.world_move()
	_along = moving.normalized() if kind == Kind.STOP else wish.normalized()
	if _along.is_zero_approx():
		_along = Vector3.BACK.rotated(Vector3.UP, body.facing)
	_turn_to = _turn_asked(body)
	animation.tree.set(_P_SEEK, 0.0)
	playback.travel(STATE)


func _go_on(
	animation: CharacterAnimation,
	blend: GaitBlend,
	playback: AnimationNodeStateMachinePlayback,
	delta: float
) -> void:
	var body := animation.character
	if (
		playback.get_current_node() != STATE
		and playback.get_travel_path().is_empty()
		and _time > 0.0
	):
		_end()  # Something else took the body (a jump, a hit's state).
		return
	if not on_foot(body):
		_hand_over(animation, blend, playback, true)  # A state the machine has no node for (a vault).
		return
	var goal := body.goal_speed
	var standing := settings.standing_speed
	var cancelled := (
		(kind == Kind.START and goal <= standing)
		or (kind == Kind.STOP and goal > standing)
		or (kind == Kind.TURN and goal > standing)
		or ((kind == Kind.REVERSAL or kind == Kind.PIVOT) and goal <= standing)
	)
	if kind == Kind.REVERSAL or kind == Kind.PIVOT:
		# At the step's time into the clip while the step follows it, then at its own pace: the
		# body moves by the clip's root, so its feet hold the floor (gdstudio #1442).
		var motion := body.turn_motion
		var at := motion.elapsed if motion.clip == clip and motion.is_active() else _time + delta
		_time = minf(maxf(at, _time), _length)
	else:
		var progress := _progress(body, blend.leg)
		if progress >= 0.0 and kind == Kind.TURN:
			progress = minf(progress, _time + delta * settings.transition_pace)
		var done := _body_done(body)
		_time = minf(maxf(progress, _time + (delta if done or progress < 0.0 else 0.0)), _length)
	animation.tree.set(_P_SEEK, _time)
	if cancelled or _time >= _length:
		_hand_over(animation, blend, playback, cancelled)


# The clip's time for what the body has done since it began: the ground covered along the way it
# set off, or the turn made, through the record's curves. -1 when the clip has neither curve.
func _progress(body: Character, leg: float) -> float:
	if kind == Kind.START or kind == Kind.STOP:
		var covered := (body.global_position - _from).dot(_along) / maxf(leg, 0.01)
		return GaitClips.time_at_travel(clip, covered)
	var turned := rad_to_deg(absf(wrapf(body.facing - _facing, -PI, PI)))
	return GaitClips.time_at_turn(clip, turned)


# True when the body has finished its part of the move: stopped for a stop, at its speed for a
# start, turned for a turn.
func _body_done(body: Character) -> bool:
	match kind:
		Kind.STOP:
			return body.ground_speed() < settings.standing_speed
		Kind.START:
			return body.ground_speed() >= body.goal_speed * 0.95
		_:
			return (
				absf(rad_to_deg(wrapf(body.facing - _facing, -PI, PI)))
				>= absf(_turn_to) - TURN_DONE
			)


# Goes on with the clip that plays: true when one plays.
func _went_on(
	animation: CharacterAnimation,
	blend: GaitBlend,
	playback: AnimationNodeStateMachinePlayback,
	delta: float
) -> bool:
	if not is_playing():
		return false
	_go_on(animation, blend, playback, delta)
	return true


# Starts the clip the body's step just started (`CharacterTurnMotion`), once: true when it did.
func _began_by_step(
	animation: CharacterAnimation, playback: AnimationNodeStateMachinePlayback
) -> bool:
	var motion := animation.character.turn_motion
	if motion.serial == _motion_serial:
		return false
	_motion_serial = motion.serial
	if not _follows(animation, playback):
		return false
	_begin(animation, {"kind": _kind_of(motion.clip), "clip": motion.clip}, playback)
	return true


# True when the clip the step just started can be shown: the machine is on the ground or in a
# transition, no action holds the body, and the player holds the clip.
func _follows(animation: CharacterAnimation, playback: AnimationNodeStateMachinePlayback) -> bool:
	var motion := animation.character.turn_motion
	if not motion.is_active() or settings == null or not settings.transitions:
		return false
	var current := playback.get_current_node()
	if current != CharacterAnimation.GROUND and current != STATE:
		return false
	return not animation.is_acting() and animation.animation_player.has_animation(motion.clip)


# A reversal for a clip that turns the body half round or more, a pivot otherwise.
static func _kind_of(picked: StringName) -> Kind:
	var curve: Array = GaitClips.record(picked).get("turn", [])
	var turned: float = absf(curve[-1][1]) if not curve.is_empty() else 0.0
	return Kind.REVERSAL if turned >= 135.0 else Kind.PIVOT


func _turn_asked(body: Character) -> float:
	if kind == Kind.TURN:
		return rad_to_deg(wrapf(body.view_yaw + PI - body.facing, -PI, PI))
	var wish := body.last_command.world_move()
	if wish.is_zero_approx():
		return 0.0
	return rad_to_deg(wrapf(atan2(wish.x, wish.z) - body.facing, -PI, PI))


# Back to the ground state, at the gait phase the clip ends on when it ran to its end.
func _hand_over(
	animation: CharacterAnimation,
	blend: GaitBlend,
	playback: AnimationNodeStateMachinePlayback,
	cancelled: bool
) -> void:
	var record := GaitClips.record(clip)
	var phase := -1.0
	if not cancelled:
		phase = float(record.get("exit_phase", -1.0))
		if phase < 0.0 and kind != Kind.STOP and kind != Kind.TURN:
			match String(record.get("end_foot", "")):
				"l":
					phase = 0.0
				"r":
					phase = 0.5
	_end()
	playback.travel(CharacterAnimation.GROUND)
	if phase >= 0.0:
		blend.seek_phase(animation.tree, CharacterAnimation.GROUND, phase)


## Ends what plays, without a hand-over (the tree is built again, the body died).
func stop() -> void:
	_end()


func _end() -> void:
	if kind == Kind.NONE:
		return
	kind = Kind.NONE
	clip = &""
	serial += 1
