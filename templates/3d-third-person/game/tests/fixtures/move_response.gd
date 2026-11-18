class_name MoveResponse
extends RefCounted
## How fast the real player answers its movement keys (gdstudio #1565), measured through the same
## input path and hand stepping as `MoveKeyMatrix`: the keys go through `InputSim`, the player's
## `PlayerInput` turns them into its command, and the body and its tree are stepped a tick at a
## time. Each tick notes the body's ground velocity, the way its command asks it to go, the
## transition clip drawn (`GaitTransitions`) and the largest move of a drawn bone since the tick
## before, so every key change reads back as:
##
## - `turn`: ticks until the velocity starts toward the new wish (its share along the wish has
##   risen by `STARTED` m/s since the tick before the change);
## - `to30`: ticks until it points within 30 degrees of the wish, at more than `MOVING` m/s;
## - `clip`: ticks until the transition clip drawn before the change is left (0 when none was).
##
## A case is a list of steps `[keys, ticks]` (or `[keys, ticks, press, turn]` with `press` an action
## held through the step, `""` for none, and `turn` degrees the camera turns from the step on); the
## gait key (`MoveKeyMatrix.GAIT_KEYS`) is held all through. Limits are in the constants, set from
## what a responsive controller does; a case fails when a change goes over one.

## The rise of the velocity's share along the new wish that counts as turning toward it (m/s).
const STARTED := 0.05
## The least ground speed at which the velocity's way is read (m/s).
const MOVING := 0.3
## Ticks within which the velocity must start toward any new wish.
const TURN_MOST := 1
## Ticks within which the velocity must be within 30 degrees of the wish: a change of under 100
## degrees, and a reversal (100 degrees or more) from a jog and from a sprint.
const STEER_30_MOST := 12
const REVERSE_30_MOST := {"walk": 8, "jog": 12, "sprint": 14, "crouch": 8}
## Ticks within which a transition clip drawn when the wish moves 60 degrees or more from the one it
## was drawn for must be left (a start asked to go elsewhere, a reversal asked another way).
const CLIP_MOST := 2
## Ticks within which an action pressed during a transition clip must have ended it.
const ACTION_CLIP_MOST := 1
## The largest move of a drawn bone in one tick after an action's press, against the largest of
## the ticks before it (a share, plus metres), over `POSE_TICKS` ticks.
const POSE_JUMP_SHARE := 1.6
const POSE_JUMP_PLUS := 0.04
const POSE_TICKS := 20
const PER_FRAME := 6
## The action whose hand-off from the steady gait bounds another's (gdstudio #1568): lying down and
## getting up move no drawn bone further in a tick than crouching does.
const BOUND_OF := {"prone": "crouch"}
## Ticks from the press in which a clip that starts on the drawn pose (lying down from a crouch at
## rest) moves no bone more than `POSE_JUMP_PLUS`: a cross-fade from the state under it shows there.
const CLIP_START_TICKS := 3
## Ticks from a stance key's press that a stance change is checked over (gdstudio #1576): the
## longest clip (getting up, 0.7 s), the crouch's stand after it and the hand-off at each end.
const STANCE_TICKS := 110
## Ticks after a carried clip's end over which its hand-off to the state under it is checked
## (`check_hand_off()`).
const HAND_OFF_TICKS := 6
## Seed of the spam cases' random keys.
const SEED := 1565
const DIRECTIONS := ["W", "WD", "D", "SD", "S", "AS", "A", "WA"]
const ACTION_KEYS := {
	"crouch": KEY_C,
	"prone": KEY_Z,
	"jump": KEY_SPACE,
	"aim": MOUSE_BUTTON_RIGHT,
	"fire": MOUSE_BUTTON_LEFT,
}
## Keys a step can hold that are no action of their own (not checked as one by `_actions()`).
const HELD_KEYS := {"sprint": KEY_SHIFT}

var matrix: MoveKeyMatrix
## Every line measured so far, and why each failing one failed.
var lines: PackedStringArray = []
var failures: PackedStringArray = []

# The drawn bones measured (`_bones()`), by index, and their names.
var _measured: PackedInt32Array = []
var _bone_names: PackedStringArray = []
# The pose the skeleton last drew (`_on_drawn`), and the skeleton it is read from.
var _drawn := PackedVector3Array()
var _drawn_from: Skeleton3D
# The drawn pose a tick before (`_note_drawn`).
var _last_drawn := PackedVector3Array()


## Steps `steps` at `gait` with the camera turned `yaw` and returns one sample a tick. With
## `drawn`, each tick is its own engine frame, so the skeleton draws every tick (the momentum blend
## runs as the skeleton updates, once a frame) and each sample has the largest move of a drawn bone.
func run(gait: String, yaw: float, steps: Array, height := 0.0, drawn := false) -> Array:
	var player := matrix.player
	var animation := matrix.animation
	var tree := matrix.tree
	await matrix._settle()
	player.teleport(Vector3(0.0, height, 0.0), PI)
	matrix.camera.rotation = Vector3(0.0, yaw, 0.0)
	var held: Key = MoveKeyMatrix.GAIT_KEYS[gait]
	if held != KEY_NONE:
		InputSim.key(held, true)
	var transitions := animation.gait.transitions
	var step_seconds := 1.0 / Engine.physics_ticks_per_second
	var samples: Array = []
	var tick := 0
	var since_frame := 0
	_bones()
	_last_drawn = PackedVector3Array()
	for index in steps.size():
		var step: Array = steps[index]
		matrix._hold(step[0])
		var press: String = step[2] if step.size() > 2 else ""
		if step.size() > 3:
			matrix.camera.rotation = Vector3(0.0, yaw + deg_to_rad(step[3]), 0.0)
		_press(press, true)
		for count in int(step[1]):
			# A press is read on the physics frame after its event (`is_action_just_pressed`): the
			# step that presses starts on a new frame, so the press is stepped on its first tick.
			if drawn or since_frame % PER_FRAME == 0 or (count == 0 and press != ""):
				await tree.physics_frame
				since_frame = 0
				if drawn and not samples.is_empty():
					_note_drawn(samples[-1])
			since_frame += 1
			player.step(matrix.input.sample(), step_seconds)
			animation.advance(step_seconds)
			(
				samples
				. append(
					{
						"tick": tick,
						"step": index,
						"keys": step[0],
						"press": press,
						"velocity": Vector3(player.velocity.x, 0.0, player.velocity.z),
						"wish": player._wish_direction(),
						"playing": transitions.is_playing(),
						"kind": transitions.kind,
						"clip": transitions.clip,
						"serial": transitions.serial,
						"state": player.state,
						"jump": 0.0,
						"jump_bone": "",
					}
				)
			)
			tick += 1
		_press(press, false)
	if drawn and not samples.is_empty():
		await tree.physics_frame
		_note_drawn(samples[-1])
	matrix._hold("")
	if held != KEY_NONE:
		InputSim.key(held, false)
	return samples


# Notes in `sample` the largest move of a drawn bone between the last two drawn poses.
func _note_drawn(sample: Dictionary) -> void:
	var bones := _drawn
	if _last_drawn.size() == bones.size():
		for bone in bones.size():
			var moved := bones[bone].distance_to(_last_drawn[bone])
			if moved > sample.jump:
				sample.jump = moved
				sample.jump_bone = _bone_names[bone]
	_last_drawn = bones


## The ticks each change of keys at `step` took, as `{turn, to30, clip, angle}` (-1: never within
## the case).
static func response(samples: Array, step: int) -> Dictionary:
	var at := -1
	for index in samples.size():
		if samples[index].step == step:
			at = index
			break
	var found := {"turn": -1, "to30": -1, "clip": 0, "angle": 0.0, "ticks": 0}
	if at <= 0:
		return found
	var prior: Dictionary = samples[at - 1]
	var wish: Vector3 = (samples[at].wish as Vector3).normalized()
	if wish.is_zero_approx():
		return found
	var moving: Vector3 = prior.velocity
	found.angle = rad_to_deg(moving.angle_to(wish)) if moving.length() > MOVING else 0.0
	var share_before := moving.dot(wish)
	var clip_left: bool = not prior.playing
	for index in range(at, samples.size()):
		var sample: Dictionary = samples[index]
		if sample.step != step:
			break
		var ticks := index - at + 1
		found.ticks = ticks
		var velocity: Vector3 = sample.velocity
		if found.turn < 0 and velocity.dot(wish) >= share_before + STARTED:
			found.turn = ticks
		if (
			found.to30 < 0
			and velocity.length() > MOVING
			and rad_to_deg(velocity.angle_to(wish)) <= 30.0
		):
			found.to30 = ticks
		if not clip_left and sample.serial != prior.serial:
			clip_left = true
			found.clip = ticks
	if not clip_left:
		found.clip = -1
	return found


## Checks every change of keys in `samples` against the limits and notes a line: `checked` lists
## the steps to check (their keys must differ from the step before), `clips` whether a clip drawn
## before a change of 60 degrees or more must be left within `CLIP_MOST`.
func check(
	name: String, gait: String, yaw: float, samples: Array, checked: Array, clips := false
) -> void:
	var why: PackedStringArray = []
	var parts: PackedStringArray = []
	for step: int in checked:
		if _in_air(samples, step):
			continue
		var found := response(samples, step)
		var keys := _keys_of(samples, step)
		var reversal: bool = found.angle >= 100.0
		var to30_most: int = REVERSE_30_MOST[gait] if reversal else STEER_30_MOST
		parts.append(
			(
				"%s turn %d to30 %d clip %d (%.0f deg)"
				% [keys, found.turn, found.to30, found.clip, found.angle]
			)
		)
		if found.turn < 0 or found.turn > TURN_MOST:
			why.append("%s: velocity started toward it after %d ticks" % [keys, found.turn])
		# A change held for fewer ticks than the limit (a spam's) is held to the start alone.
		var held_long: bool = found.ticks >= to30_most
		if (found.to30 < 0 and held_long) or found.to30 > to30_most:
			why.append("%s: within 30 degrees after %d ticks" % [keys, found.to30])
		if clips and _asks_clip_end(samples, step) and (found.clip < 0 or found.clip > CLIP_MOST):
			why.append("%s: the clip drawn was left after %d ticks" % [keys, found.clip])
	_note(name, gait, yaw, parts, why)


## The largest move of a drawn bone in a tick over `POSE_TICKS` ticks from `step` on.
static func peak_move(samples: Array, step: int) -> float:
	var peak := 0.0
	var at := -1
	for index in samples.size():
		if samples[index].step == step and at < 0:
			at = index
		if at >= 0 and index < at + POSE_TICKS:
			peak = maxf(peak, samples[index].jump)
	return peak


## The largest move of a drawn bone in each tick over `ticks` ticks (`POSE_TICKS`) from `step` on.
static func moves_from(samples: Array, step: int, ticks := POSE_TICKS) -> PackedFloat32Array:
	var moves := PackedFloat32Array()
	for sample: Dictionary in samples:
		if sample.step >= step and moves.size() < ticks:
			moves.append(sample.jump)
	return moves


## Checks that the clip whose moves a tick are `moves` (`moves_from()`, played where it starts on
## the drawn pose) starts on that pose: no move over `POSE_JUMP_PLUS` in its first
## `CLIP_START_TICKS` ticks. Its moves can then stand for the clip alone (`check_action()`'s `own`).
func check_clip_start(name: String, gait: String, moves: PackedFloat32Array) -> void:
	var why: PackedStringArray = []
	var first := moves.slice(0, CLIP_START_TICKS)
	var largest := 0.0
	for move in first:
		largest = maxf(largest, move)
	if largest > POSE_JUMP_PLUS:
		why.append("a bone moved %.3f m in a tick as the clip began" % largest)
	_note(name, gait, 0.0, ["first ticks %s m" % str(Array(first))], why)


## Checks an action pressed at `step` during a transition clip: the clip ends within
## `ACTION_CLIP_MOST` ticks and no drawn bone jumps further in a tick than the ticks before allow,
## or than the same action taken from the steady gait (`plain`, its `peak_move()`) by a share.
## Without `in_clip` no transition clip need be drawn (an action from the steady gait or a stance).
## `own` is what the action's own clip moves a tick from the press on (`moves_from()` of it played
## where it starts on the drawn pose), added to the allowance tick by tick (lying down: gdstudio
## #1568); the line then gives the largest move over it. `ticks` is how many ticks from the press
## are checked (`POSE_TICKS`; a stance change's whole clip and its hand-off: `STANCE_TICKS`).
func check_action(
	name: String,
	gait: String,
	samples: Array,
	step: int,
	plain := 0.0,
	in_clip := true,
	own := PackedFloat32Array(),
	ticks := POSE_TICKS
) -> void:
	var why: PackedStringArray = []
	var at := -1
	for index in samples.size():
		if samples[index].step == step:
			at = index
			break
	var prior: Dictionary = samples[at - 1]
	var ended := -1
	var steady := 0.0
	for index in range(maxi(at - POSE_TICKS, 1), at):
		steady = maxf(steady, samples[index].jump)
	var peak := 0.0
	var peak_bone := ""
	var over := 0.0
	for index in range(at, mini(at + ticks, samples.size())):
		var sample: Dictionary = samples[index]
		var clip_move: float = own[index - at] if index - at < own.size() else 0.0
		if sample.jump - clip_move > over or peak_bone == "":
			over = sample.jump - clip_move
			peak = sample.jump
			peak_bone = "%s t+%d" % [sample.jump_bone, index - at]
		if ended < 0 and (not sample.playing or sample.serial != prior.serial):
			ended = index - at + 1
	var allowed := maxf(steady, plain) * POSE_JUMP_SHARE + POSE_JUMP_PLUS
	if not own.is_empty():
		peak_bone += ", its clip alone %.3f" % (peak - over)
	var part := (
		"%s in %s %s: clip ended %d, bone move a tick %.3f m (%s; before %.3f, allowed %.3f)"
		% [
			samples[at].press,
			MoveKeyMatrix.KIND_NAMES[prior.kind],
			String(prior.clip).trim_prefix("gds/"),
			ended,
			peak,
			peak_bone,
			steady,
			allowed
		]
	)
	if in_clip and not prior.playing:
		why.append("no transition clip was drawn when %s was pressed" % samples[at].press)
	elif in_clip and (ended < 0 or ended > ACTION_CLIP_MOST):
		why.append("the clip ended %d ticks after %s" % [ended, samples[at].press])
	if over > allowed:
		why.append("a bone moved %.3f m in a tick after %s" % [peak, samples[at].press])
	if OS.get_environment("GDS_POSE_TRACE") != "":
		var trace: PackedStringArray = []
		for index in range(maxi(at - 2, 0), mini(at + ticks, samples.size())):
			trace.append("%.3f %s" % [samples[index].jump, samples[index].jump_bone])
		part += " | trace from t-2: " + ", ".join(trace)
	_note(name, gait, 0.0, [part], why)


## Checks the hand-off at the end of a carried clip that ends still, on the first pose of the stance
## it was made to end on (getting up: `prone/Prone_To_Crouch` ends on the crouch idle's first pose,
## every bone within 1 mm, gdstudio #1576), `end` ticks after the press at `step`, on a body that
## stays where it is: over `HAND_OFF_TICKS` ticks from the end no drawn bone moves further in a tick
## than `POSE_JUMP_PLUS` (and `extra` more). The bound does not come from the code under test.
## Before the fix the one-shot's 0.1 s fade-out drew the crouch idle rising into the standing idle
## there (0.12 m a tick with the pistol, 0.24 with the rifle).
func check_hand_off(
	name: String, gait: String, samples: Array, step: int, end: int, extra := 0.0
) -> void:
	var why: PackedStringArray = []
	var at := -1
	for index in samples.size():
		if samples[index].step == step:
			at = index
			break
	var allowed := POSE_JUMP_PLUS + extra
	var peak := 0.0
	var peak_bone := ""
	for index in range(at + end, mini(at + end + HAND_OFF_TICKS, samples.size())):
		var sample: Dictionary = samples[index]
		if sample.jump > peak:
			peak = sample.jump
			peak_bone = "%s t+%d" % [sample.jump_bone, index - at]
	if peak > allowed:
		why.append("a bone moved %.3f m in a tick as the clip ended" % peak)
	var part := (
		"clip end t+%d: bone move a tick %.3f m (%s; allowed %.3f)"
		% [end, peak, peak_bone, allowed]
	)
	_note(name + ", its end", gait, 0.0, [part], why)


## Random direction changes, every 3 to 7 ticks, `count` of them, from a seeded generator.
static func spam(rng: RandomNumberGenerator, first: String, count: int) -> Array:
	var steps: Array = []
	var keys := first
	for _change in count:
		var next: String = keys
		while next == keys:
			next = DIRECTIONS[rng.randi_range(0, DIRECTIONS.size() - 1)]
		keys = next
		steps.append([keys, rng.randi_range(3, 7)])
	return steps


func _note(name: String, gait: String, yaw: float, parts: Array, why: PackedStringArray) -> void:
	var line := (
		"%s | camera %d | %s | %s | %s"
		% [
			gait,
			roundi(rad_to_deg(yaw)),
			name,
			"; ".join(PackedStringArray(parts)),
			"FAIL: " + ", ".join(why) if not why.is_empty() else "ok"
		]
	)
	lines.append(line)
	if not why.is_empty():
		failures.append(line)


# True when the change at `step` turns the wish 60 degrees or more from the one before it while a
# transition clip is drawn.
static func _asks_clip_end(samples: Array, step: int) -> bool:
	for index in range(1, samples.size()):
		if samples[index].step == step:
			var prior: Dictionary = samples[index - 1]
			var old: Vector3 = prior.wish
			var new: Vector3 = samples[index].wish
			if not prior.playing or old.is_zero_approx() or new.is_zero_approx():
				return prior.playing and old.is_zero_approx() != new.is_zero_approx()
			return rad_to_deg(old.angle_to(new)) >= 60.0
	return false


# True when the body is off the floor as the change at `step` comes (the air steers by its own
# share, `air_control`).
static func _in_air(samples: Array, step: int) -> bool:
	for index in range(1, samples.size()):
		if samples[index].step == step:
			var state: Character.State = samples[index - 1].state
			return state == Character.State.JUMP or state == Character.State.FALL
	return false


static func _keys_of(samples: Array, step: int) -> String:
	for sample: Dictionary in samples:
		if sample.step == step:
			return sample.keys if sample.keys != "" else "-"
	return "?"


# Presses or lets go of `what`: an action of `ACTION_KEYS`, or several joined by `+`
# (`crouch+prone`: crouch held while prone is pressed).
func _press(what: String, down: bool) -> void:
	if what == "":
		return
	for part in what.split("+"):
		var code: int = ACTION_KEYS.get(part, HELD_KEYS.get(part, KEY_NONE))
		if part == "aim" or part == "fire":
			InputSim.mouse_button(code as MouseButton, down)
		else:
			InputSim.key(code as Key, down)


# Every drawn bone's place in the model's frame, as the skeleton's last update drew it (the body's
# facing and place taken out; the modifiers, the momentum blend among them, and the rig's own turn
# kept in). Read in `skeleton_updated`: after it the skeleton puts the tree's pose back.
func _bones() -> PackedVector3Array:
	var skeleton := matrix.animation.model.skeleton()
	if skeleton != null and skeleton != _drawn_from:
		_drawn_from = skeleton
		skeleton.skeleton_updated.connect(_on_drawn.bind(skeleton))
	return _drawn


func _on_drawn(skeleton: Skeleton3D) -> void:
	var model := matrix.animation.model
	var found := PackedVector3Array()
	if _measured.is_empty():
		for bone in skeleton.get_bone_count():
			var bone_name := skeleton.get_bone_name(bone)
			# The bones the momentum blend leaves to the clip (fingers, twists, sockets, helper
			# targets, the root) move fast and small or are never drawn: the body's are measured.
			var lower := bone_name.to_lower()
			if MomentumBlend.SKIPPED.any(func(part: String) -> bool: return lower.contains(part)):
				continue
			_measured.append(bone)
			_bone_names.append(bone_name)
	var to_model := model.global_transform.affine_inverse() * skeleton.global_transform
	for bone in _measured:
		found.append(to_model * skeleton.get_bone_global_pose(bone).origin)
	_drawn = found
