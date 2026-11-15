class_name MoveKeyMatrix
extends RefCounted
## Plays sequences of movement keys on a real player (gdstudio #1563): the keys go through the
## engine's input path (`InputSim`), the player's own `PlayerInput` turns them into its command,
## and the body and its tree are stepped by hand, a few ticks a physics frame. Each tick it notes
## the transition clip the tree plays (`GaitTransitions`), so a case reads back as the clips that
## began, the keys held as each began, how long each played and whether it was cut.
##
## A case is `[name, steps, expect]`: `steps` are `[keys, ticks]` (`"WD"` holds W and D, `""` lets
## go of all four), `expect` what must hold (`stops`: the number of stops, -1 for any; `starts`:
## the most starts; `reversal`: a reversal must begin; `clean`: no clip cut within `FLICKER` ticks).
## Whatever the case, a stop never begins while a movement key is held.

## A clip cut this many ticks or fewer after it began is a flicker.
const FLICKER := 6
## Ticks stepped between two awaited physics frames.
const PER_FRAME := 6
## The longest the last let-go is stepped, in ticks (a sprint's stop is 100).
const TAIL := 170
## Below this ground speed, with no clip playing, the body is at rest and the case ends (m/s).
const AT_REST := 0.01
const KEYS := {"W": KEY_W, "A": KEY_A, "S": KEY_S, "D": KEY_D}
## The key held for the whole case for each gait (`KEY_NONE`: a jog).
const GAIT_KEYS := {"walk": KEY_X, "jog": KEY_NONE, "sprint": KEY_SHIFT, "crouch": KEY_C}
const KIND_NAMES := ["NONE", "START", "STOP", "REVERSAL", "PIVOT", "TURN"]

var player: Player
var input: PlayerInput
var animation: CharacterAnimation
var camera: Camera3D
var tree: SceneTree
## Every line of the matrix played so far.
var lines: PackedStringArray = []
## Why each failing case failed.
var failures: PackedStringArray = []


## The let-go grace of `GaitTransitions` in ticks (0 before it had one).
static func grace_ticks() -> int:
	var script: Script = load("res://gameplay/character/gait_transitions.gd")
	var constants := script.get_script_constant_map()
	var seconds: float = constants.get("STOP_GRACE", 0.1)
	return roundi(seconds * Engine.physics_ticks_per_second)


## The cases for `gait` (`walk`, `jog`, `sprint`, `crouch`); `subset` keeps only the opposing
## overlaps, a short swap, the diagonals and the let-go from a diagonal (the turned camera's).
static func cases(gait: String, subset := false) -> Array:
	var run_up := 80
	var grace := grace_ticks()
	var moving := gait != "crouch"
	var stop := 1 if moving else 0
	var start := 1 if moving else 0
	var turns := gait == "jog" or gait == "sprint"
	var found: Array = []
	if not subset:
		for key: String in ["W", "A", "S", "D"]:
			found.append(["%s alone" % key, [[key, run_up], ["", TAIL]], {"stops": stop}])
	for pair: Array in [["W", "S"], ["S", "W"], ["A", "D"], ["D", "A"]]:
		var a: String = pair[0]
		var b: String = pair[1]
		if not subset:
			found.append(
				[
					"%s+%s together from standing" % [a, b],
					[[a + b, 60], ["", 40]],
					{"stops": 0, "starts": 0, "clean": true}
				]
			)
		found.append(
			[
				"%s then %s+%s then %s" % [a, a, b, b],
				[[a, run_up], [a + b, 60], [b, 90], ["", TAIL]],
				{"stops": stop, "reversal": turns, "clean": true}
			]
		)
		if subset:
			found.append(
				[
					"%s, 2 ticks of nothing, %s" % [a, b],
					[[a, run_up], ["", 2], [b, 90], ["", TAIL]],
					{"stops": stop, "reversal": turns, "clean": true}
				]
			)
			continue
		found.append(
			[
				"%s then %s+%s then %s again" % [a, a, b, a],
				[[a, run_up], [a + b, 40], [a, 90], ["", TAIL]],
				{"stops": stop, "clean": true}
			]
		)
		for gap: int in [0, 2, 4, 5, 8, 20]:
			var inside := gap < grace
			(
				found
				. append(
					[
						"%s, %d ticks of nothing, %s" % [a, gap, b],
						[[a, run_up], ["", gap], [b, 90], ["", TAIL]],
						{
							"stops": stop if inside else -1,
							"reversal": turns and inside,
							"clean": inside,
						}
					]
				)
			)
	for pair: Array in [["W", "D"], ["W", "A"], ["S", "D"], ["S", "A"]]:
		var a: String = pair[0]
		var b: String = pair[1]
		found.append(
			[
				"%s, %s, %s and back" % [a, a + b, b],
				[[a, run_up], [a + b, 40], [b, 60], [a + b, 40], [a, 60], ["", TAIL]],
				{"stops": stop, "starts": start, "clean": true}
			]
		)
		found.append(
			[
				"%s let go" % (a + b),
				[[a + b, run_up], ["", TAIL]],
				{"stops": stop, "starts": start, "clean": true}
			]
		)
	if subset:
		return found
	found.append(["W, W+S, let go", [["W", run_up], ["WS", 30], ["", TAIL]], {"stops": -1}])
	for gap: int in [2, 4, 8, 20]:
		var inside := gap < grace
		found.append(
			[
				"W, %d ticks of nothing, W" % gap,
				[["W", run_up], ["", gap], ["W", 90], ["", TAIL]],
				{"stops": stop if inside else -1, "clean": inside}
			]
		)
	for tap: int in [2, 4, 8]:
		# A tap of the other way is answered (gdstudio #1565): the clip it starts gives way to W
		# again at once, so it may be cut; no stop plays under a held key.
		found.append(
			[
				"W, S tapped %d ticks" % tap,
				[["W", run_up], ["WS", tap], ["W", 120], ["", TAIL]],
				{"stops": stop}
			]
		)
	found.append(
		[
			"W, D tapped 4 ticks",
			[["W", run_up], ["WD", 4], ["W", 60], ["", TAIL]],
			{"stops": stop, "starts": start, "clean": true}
		]
	)
	return found


## Plays every case of `list` at `gait` with the camera turned `yaw` radians, noting lines and
## failures.
func play_all(gait: String, yaw: float, list: Array) -> void:
	for case: Array in list:
		await play(gait, yaw, case)


## Plays one case and checks it.
func play(gait: String, yaw: float, case: Array) -> void:
	var events := await _run(gait, yaw, case[1])
	var expect: Dictionary = case[2]
	var why: PackedStringArray = []
	var stops := 0
	var starts := 0
	var reversals := 0
	var parts: PackedStringArray = []
	for event: Dictionary in events:
		var flags := ""
		if event.kind == GaitTransitions.Kind.STOP:
			stops += 1
			if event.keys != "":
				flags += " STOP-WITH-KEYS-HELD"
				why.append("a stop began with %s held" % event.keys)
		elif event.kind == GaitTransitions.Kind.START:
			starts += 1
		elif event.kind == GaitTransitions.Kind.REVERSAL:
			reversals += 1
		if event.cut:
			flags += " cut"
			if event.ticks <= FLICKER:
				flags += " FLICKER"
				if expect.get("clean", false):
					why.append("%s cut after %d ticks" % [event.clip, event.ticks])
		parts.append(
			(
				"t%d [%s] %s %s %dt%s"
				% [
					event.at,
					event.keys if event.keys != "" else "-",
					KIND_NAMES[event.kind],
					String(event.clip).trim_prefix("gds/"),
					event.ticks,
					flags
				]
			)
		)
	var want_stops: int = expect.get("stops", -1)
	if want_stops >= 0 and stops != want_stops:
		why.append("%d stops, %d wanted" % [stops, want_stops])
	if expect.has("starts") and starts > int(expect.starts):
		why.append("%d starts, at most %d wanted" % [starts, expect.starts])
	if expect.get("reversal", false) and reversals == 0:
		why.append("no reversal")
	var steps := PackedStringArray()
	for step: Array in case[1]:
		steps.append("%s%d" % [step[0] if step[0] != "" else "-", step[1]])
	var line := (
		"%s | camera %d | %s | %s | %s | %s"
		% [
			gait,
			roundi(rad_to_deg(yaw)),
			case[0],
			" ".join(steps),
			"; ".join(parts) if not parts.is_empty() else "no clip",
			"FAIL: " + ", ".join(why) if not why.is_empty() else "ok"
		]
	)
	lines.append(line)
	if not why.is_empty():
		failures.append(line)


# Steps `steps` from standing at the origin and returns the clips that began, in order.
func _run(gait: String, yaw: float, steps: Array) -> Array:
	await _settle()
	player.teleport(Vector3.ZERO, PI)
	camera.rotation = Vector3(0.0, yaw, 0.0)
	var held: Key = GAIT_KEYS[gait]
	if held != KEY_NONE:
		InputSim.key(held, true)
	var transitions := animation.gait.transitions
	var step_seconds := 1.0 / Engine.physics_ticks_per_second
	var events: Array = []
	var open := {}
	var serial := transitions.serial
	var last_time := 0.0
	var tick := 0
	for index in steps.size():
		var keys: String = steps[index][0]
		_hold(keys)
		var last := index == steps.size() - 1
		for _count in int(steps[index][1]):
			if tick % PER_FRAME == 0:
				await tree.physics_frame
			player.step(input.sample(), step_seconds)
			animation.advance(step_seconds)
			if transitions.serial != serial:
				serial = transitions.serial
				if not open.is_empty():
					var length := animation.animation_player.get_animation(open.clip).length
					open.ticks = tick - open.at
					open.cut = last_time < length - 0.02
					open = {}
				if transitions.is_playing():
					open = {
						"at": tick,
						"kind": transitions.kind,
						"clip": transitions.clip,
						"keys": keys,
						"ticks": 0,
						"cut": false
					}
					events.append(open)
			last_time = transitions.time()
			tick += 1
			if last and not transitions.is_playing() and player.ground_speed() < AT_REST:
				break
	if not open.is_empty():
		open.ticks = tick - open.at
	_hold("")
	if held != KEY_NONE:
		InputSim.key(held, false)
	return events


# Holds exactly the movement keys in `keys`.
func _hold(keys: String) -> void:
	for key: String in KEYS:
		InputSim.key(KEYS[key], keys.contains(key))


# Steps with nothing held until the body stands and plays no clip (at most two seconds).
func _settle() -> void:
	_hold("")
	var step_seconds := 1.0 / Engine.physics_ticks_per_second
	for tick in 120:
		if not animation.gait.transitions.is_playing() and player.ground_speed() < AT_REST:
			return
		if tick % PER_FRAME == 0:
			await tree.physics_frame
		player.step(input.sample(), step_seconds)
		animation.advance(step_seconds)
