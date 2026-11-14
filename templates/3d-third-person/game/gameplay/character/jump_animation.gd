class_name JumpAnimation
extends RefCounted
## The jump's states of `CharacterAnimation`'s body machine (gdstudio #1371), each clip picked by
## code from the body's own numbers, as the gait transitions are:
##
## - **The take-off** (`jump`): from the ground state at `GaitSettings.run_takeoff_speed` or more,
##   the run take-off of the foot that pushes off: the one down at the gait's phase now, else the
##   one that lands next (`Jump_Start_Run_L` begins on the jog's left foot strike, `_R` on its
##   right one: `joins.first_frame` in `clips.json`); else `CharacterAnimation.jump_clip`. It
##   plays to its end while the body is in the air, then the air follows. The momentum blend
##   carries no speed of the pose before into the standing one (`carries_speed()`) and starts
##   again on one frame more (`extra_settle()`).
## - **The air** (`fall`): `GaitSettings.rise_clip`, `apex_clip` and `CharacterAnimation.air_clip`
##   (the fall) in a blend space on the body's vertical speed: the rise alone from `air_rise_speed`
##   up, the top at 0, the fall alone from `air_fall_speed` down.
## - **The landing** (`land`): by the fall speed, `hard_land_clip` from the clip's
##   `fall_speed.from` (`hard_land_speed` without a record); below it, with the body asked to run
##   (`run_land_speed`), `run_land_clip`, which hands over to the ground state at the gait phase
##   it ends on (`joins.last_frame`); else `CharacterAnimation.land_clip`. The landing holds the
##   body until its clip's `control` frame while the body is asked to move and has not moved yet,
##   and plays on through its settle while the body stands; asked to move once it is past that
##   frame (or moving), the body leaves it at once, as it leaves a transition clip.
##
## A clip missing from the libraries (or empty) leaves that choice to the clip of
## `CharacterAnimation`, and `GaitSettings.jump_choices` off plays those three alone, as before.
## Cosmetic: worked out on each machine from the body it draws, never sent; a puppet picks from
## the state, the velocity and the goal it is drawn with.

enum Phase { NONE, TAKEOFF, AIR, LANDING }

## The air blend space's points.
const RISE := &"rise"
const APEX := &"apex"
const FALL := &"fall"
const _P_AIR := &"parameters/Locomotion/fall/blend_position"
## Seconds before the end at which a take-off counts as played (a tick of rounding).
const _END := 0.001

var settings: GaitSettings
## The take-off picked last, and the landing.
var takeoff: StringName = &""
var landing: StringName = &""
## The fall speed the landing was picked by, in m/s.
var fall_speed := 0.0
## Where the jump is.
var phase := Phase.NONE

var _animation: CharacterAnimation
var _takeoff_node: AnimationNodeAnimation
var _landing_node: AnimationNodeAnimation
var _air := false  # The air is a blend space (the rise and the top are in the libraries).
var _watched: Character
var _impact := -1.0  # The stepped body's own landing speed (`Character.landed`), this landing.
var _falling := 0.0  # The fastest the body fell since it left the ground, read each frame.
var _control := 0.0  # Seconds into the landing at which it gives the body back.
var _hand_over := -1.0  # The gait phase a landing into a run hands over at (-1: none).
var _asked: StringName = CharacterAnimation.GROUND


## Adds the jump's three states to `machine` from `animation`'s clips and the settings.
func add_states(animation: CharacterAnimation, machine: AnimationNodeStateMachine) -> void:
	_animation = animation
	_watch(animation.character)
	phase = Phase.NONE
	_takeoff_node = _clip(animation.jump_clip)
	_landing_node = _clip(animation.land_clip)
	machine.add_node(CharacterAnimation.JUMP, _takeoff_node, Vector2(400, -100))
	machine.add_node(CharacterAnimation.FALL, _build_air(animation), Vector2(600, 0))
	machine.add_node(CharacterAnimation.LAND, _landing_node, Vector2(400, 100))


## The state the machine goes to when `CharacterAnimation` asks for `state` (after the
## transitions' own routing): a take-off that plays keeps the body until it ends, and a landing
## keeps it from the ground state until `step()` lets it go.
func route(state: StringName, blend: GaitBlend) -> StringName:
	_asked = state
	if not _choosing():
		return state
	match state:
		CharacterAnimation.JUMP:
			_pick_takeoff(blend)
			phase = Phase.TAKEOFF
		CharacterAnimation.FALL:
			if phase == Phase.TAKEOFF:
				return CharacterAnimation.JUMP
			if phase != Phase.AIR:
				_falling = 0.0
				_impact = -1.0
			phase = Phase.AIR
		CharacterAnimation.LAND:
			_pick_landing()
			phase = Phase.LANDING
		CharacterAnimation.GROUND:
			if phase == Phase.LANDING:
				return CharacterAnimation.LAND
			phase = Phase.NONE
		_:
			phase = Phase.NONE
	return state


## One frame: the air's place on the vertical speed, the end of a take-off, the end of a landing.
func step(
	animation: CharacterAnimation, blend: GaitBlend, playback: AnimationNodeStateMachinePlayback
) -> void:
	if phase == Phase.NONE or not _choosing():
		return
	var body := animation.character
	var current := playback.get_current_node()
	match phase:
		Phase.TAKEOFF, Phase.AIR:
			_falling = maxf(_falling, -body.velocity.y)
			if phase == Phase.TAKEOFF and current == CharacterAnimation.JUMP and _ended(playback):
				phase = Phase.AIR
				playback.travel(CharacterAnimation.FALL)
			if current == CharacterAnimation.FALL and _air:
				animation.tree.set(_P_AIR, body.velocity.y)
		Phase.LANDING:
			if current == CharacterAnimation.LAND and _asked == CharacterAnimation.GROUND:
				_follow_landing(animation, blend, playback)


## True when the landing that plays lets the body go: asked to move (or aiming, which the ground
## state's stance holds) once past the clip's `control` frame or already moving, or at its end.
func lets_go(at: float, length: float, body: Character) -> bool:
	if at >= length - _END:
		return true
	if at < _control and body.ground_speed() <= settings.standing_speed:
		return false
	return body.goal_speed > settings.standing_speed or body.aiming


## Whether the momentum blend (`MomentumBlend`) carries the speed of the pose shown before into
## `state`, the body state it starts for: not into the standing take-off, whose push-off starts
## from its own crouch. From a stop clip, the stop's sway carried into it turned the raised
## pistol at 41 to 43 degrees a second on the third and fourth update (24 from a still stand),
## by which foot the stop began on (gdstudio #1530); the run take-offs join the gait's own
## motion and carry it.
func carries_speed(state: StringName) -> bool:
	if not _choosing() or phase != Phase.TAKEOFF or state != CharacterAnimation.JUMP:
		return true
	return takeoff != _animation.jump_clip


## Frames more than `MomentumBlend.SETTLE_FRAMES` the momentum blend starts again after a change
## into `state`: one for the standing take-off, whose pose is drawn a tick later than a gait's
## after a transition clip. With the three of gdstudio #1536 its last start came on the update the
## take-off's pose arrived, and the 26 to 33 degree difference from the stop died away on top of
## the clip's own first move: the raised pistol 36 degrees a second on the fourth update, 27 to 29
## with one more start (gdstudio #1530).
func extra_settle(state: StringName) -> int:
	return 0 if carries_speed(state) else 1


## The clip a jump of `body` would take off with now: `gait` is the ground gait that weighs most,
## `phase_now` the ground gaits' phase and `on_ground` whether the machine is in the ground state
## (or a gait transition). A run takes off from the foot that is down at that phase, or else the
## one that lands next (`clips.json`'s contacts); with no record of the gait, from the take-off
## whose first frame is nearest the phase.
func takeoff_for(
	body: Character, gait: StringName, phase_now: float, on_ground: bool
) -> StringName:
	var standing := _animation.jump_clip
	if not on_ground or body.ground_speed() < settings.run_takeoff_speed:
		return standing
	var left := settings.run_takeoff_left
	var right := settings.run_takeoff_right
	if not _has(left) or not _has(right):
		return standing
	if GaitClips.has(gait):
		var foot := GaitClips.planted_foot(gait, phase_now)
		if foot == "":
			foot = GaitTransitions.next_foot(gait, phase_now)
		return left if foot == "l" else right
	var to_left := _apart(phase_now, join_phase(left, 0.0))
	var to_right := _apart(phase_now, join_phase(right, 0.5))
	return left if to_left <= to_right else right


## The landing a body asked to go at `goal` m/s plays from a fall of `speed` m/s.
func landing_for(speed: float, goal: float) -> StringName:
	var hard := settings.hard_land_clip
	if _has(hard) and speed >= range_of(hard, settings.hard_land_speed, INF).x:
		return hard
	var run := settings.run_land_clip
	if _has(run) and goal >= settings.run_land_speed:
		var band := range_of(run, 0.0, INF)
		if speed >= band.x and speed < band.y:
			return run
	return _animation.land_clip


## The share of the gait's cycle (0 to 1) a take-off's first frame is (`joins.first_frame` over
## the joined gait's frames), `fallback` without a record.
static func join_phase(clip: StringName, fallback: float) -> float:
	var joins: Dictionary = GaitClips.record(clip).get("joins", {})
	var gait := GaitClips.record(StringName("gds/" + String(joins.get("first", ""))))
	var frames := float(gait.get("frames", 0.0))
	if not joins.has("first_frame") or frames <= 0.0:
		return fallback
	return fposmod(float(joins.first_frame) / frames, 1.0)


## The fall speeds a landing is made for (`fall_speed` `from` and `to` in `clips.json`, m/s), as
## `Vector2(from, to)`; `from` and `to` stand in where the record has none.
static func range_of(clip: StringName, from: float, to: float) -> Vector2:
	var band: Variant = GaitClips.record(clip).get("fall_speed", {})
	if not band is Dictionary:
		return Vector2(from, to)
	var low: Variant = band.get("from")
	var high: Variant = band.get("to")
	return Vector2(float(low) if low != null else from, float(high) if high != null else to)


func _choosing() -> bool:
	return settings != null and settings.jump_choices and _animation != null


func _pick_takeoff(blend: GaitBlend) -> void:
	_falling = 0.0
	_impact = -1.0
	var tree := _animation.tree
	var playback := _playback()
	var current := playback.get_current_node() if playback != null else &""
	var on_ground := current == CharacterAnimation.GROUND or current == GaitTransitions.STATE
	var body := _animation.character
	var phase_now := blend.phase(tree, CharacterAnimation.GROUND)
	var gait := blend.main_gait(CharacterAnimation.GROUND, body.ground_speed())
	takeoff = takeoff_for(body, gait, phase_now, on_ground)
	_takeoff_node.animation = takeoff


func _pick_landing() -> void:
	var body := _animation.character
	fall_speed = _impact if _impact >= 0.0 else maxf(_falling, -body.velocity.y)
	_impact = -1.0
	_falling = 0.0
	landing = landing_for(fall_speed, body.goal_speed)
	_landing_node.animation = landing
	var record := GaitClips.record(landing)
	_control = float(record.get("control", 0.0)) / GaitClips.FPS
	_hand_over = -1.0
	var joins: Dictionary = record.get("joins", {})
	if landing == settings.run_land_clip and joins.has("last_frame"):
		var gait := GaitClips.record(StringName("gds/" + String(joins.get("last", ""))))
		var frames := float(gait.get("frames", 0.0))
		if frames > 0.0:
			_hand_over = fposmod(float(joins.last_frame) / frames, 1.0)


func _follow_landing(
	animation: CharacterAnimation, blend: GaitBlend, playback: AnimationNodeStateMachinePlayback
) -> void:
	var at := playback.get_current_play_position()
	var length := playback.get_current_length()
	if not lets_go(at, length, animation.character):
		return
	phase = Phase.NONE
	playback.travel(CharacterAnimation.GROUND)
	if _hand_over >= 0.0 and at >= length - _END:
		blend.seek_phase(animation.tree, CharacterAnimation.GROUND, _hand_over)


func _ended(playback: AnimationNodeStateMachinePlayback) -> bool:
	var length := playback.get_current_length()
	return length > 0.0 and playback.get_current_play_position() >= length - _END


func _playback() -> AnimationNodeStateMachinePlayback:
	var tree := _animation.tree
	if tree == null or tree.tree_root == null:
		return null
	return tree.get(&"parameters/Locomotion/playback") as AnimationNodeStateMachinePlayback


# The air: the fall alone, or the rise, the top and the fall on the vertical speed.
func _build_air(animation: CharacterAnimation) -> AnimationRootNode:
	var rise := settings.rise_clip if settings != null else &""
	var apex := settings.apex_clip if settings != null else &""
	_air = _choosing() and _has(rise) and _has(apex)
	if not _air:
		return _clip(animation.air_clip)
	var space := AnimationNodeBlendSpace1D.new()
	space.min_space = -settings.air_fall_speed
	space.max_space = settings.air_rise_speed
	space.sync = true
	space.add_blend_point(_clip(animation.air_clip), -settings.air_fall_speed, -1, FALL)
	space.add_blend_point(_clip(apex), 0.0, -1, APEX)
	space.add_blend_point(_clip(rise), settings.air_rise_speed, -1, RISE)
	return space


# Hears the stepped body's own landing speed; a puppet never says it, and reads its fall instead.
func _watch(body: Character) -> void:
	if body == _watched or Engine.is_editor_hint():
		return
	if (
		_watched != null
		and is_instance_valid(_watched)
		and _watched.landed.is_connected(_on_landed)
	):
		_watched.landed.disconnect(_on_landed)
	_watched = body
	if body != null:
		body.landed.connect(_on_landed)


func _on_landed(impact_speed: float) -> void:
	_impact = impact_speed


func _has(clip: StringName) -> bool:
	var player := _animation.animation_player if _animation != null else null
	return clip != &"" and player != null and player.has_animation(clip)


# How far apart two shares of a cycle are, the short way round (0 to 0.5).
static func _apart(a: float, b: float) -> float:
	var gap := fposmod(a - b, 1.0)
	return minf(gap, 1.0 - gap)


static func _clip(clip: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	return node
