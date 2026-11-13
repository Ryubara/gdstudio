## Solves the pistol's trigger finger's way from along the frame to the trigger, with both hands on
## the gun (kit #1272), and writes it as a `HandPoseWay`: the default body's (`female`) into
## `gameplay/weapon/hold/pistol_trigger_way.tres`, which `weapon_hold.tscn` names, another body's
## into its fit (`pistol_fit_<body>.tres`, `HoldFit.trigger_way`).
##
## The pistol solve (`solve_pistol_hold.py`) gives the finger one pose between, nearly straight
## and drawn out to its own side; swinging in from there the last bone crossed the trigger guard's
## front strut (kit #1212) or rubbed its inner face (kit #1273). A real trigger finger comes off
## the frame, bends its last two bones and drops them into the guard's open side, then onto the
## trigger. The way here is that: a few poses, searched in the solver's own angles (a finger's
## spread and three bends, `authored_pose.gd`), each leg blended as the game blends it
## (`HandPoseModifier.second_way`: a slerp of each bone's rotation, the legs spread evenly over the
## weight), and measured with the
## tests' own measure (`HandContact`) on the tests' stage (`HoldStage`, the aimed pistol with both
## hands on it): the index finger against the gun and against the left hand as it holds. Depth into
## the gun is read against the part's thickness (`HandContact.measure_through`), so a finger that
## crosses a thin part reads its whole thickness, not the half that its nearest face is away.
##
## Nothing is written when any step of the way goes deeper than `LIMIT`. No number of the way is
## typed: change the gun, the seat or the poses, run `write_hold.gd`, then this, then
## `tests/gameplay/test_pistol_hold.gd`. It lives in tools/, which the export leaves out.
##
## `<godot> --headless --path game -s res://tools/hold/solve_pistol_trigger_way.gd -- <body>
## [<report file>] [sweep]`: `sweep` writes nothing and prints how deep the way the hold has now
## goes at every hundredth.
extends SceneTree

const Authored := preload("res://tools/hold/authored_pose.gd")
const OUT := "res://gameplay/weapon/hold/pistol_trigger_way.tres"
const FIT := "res://gameplay/weapon/hold/pistol_fit_%s.tres"
const DEFAULT_BODY := "female"
const BONES: Array[StringName] = [&"index_01_r", &"index_02_r", &"index_03_r"]
const PARTS: Array[String] = ["index_base", "index_mid", "index_tip"]
## The pose of the aim the way is solved in, as the test measures it.
const AIM_TIME := 0.16
## The deepest any step of the way may go into the gun or the left hand, in metres: the hold's own
## limit (`HandContact.MAX_DEPTH`), less what the tests' samples may find between the solver's.
const LIMIT := 0.0015
## What the search aims under, in metres: the deepest step costs nothing below it.
const AIM := 0.0008
## The steps each leg is measured at while searching, and at the end.
const SEARCH_STEPS := 8
const CHECK_STEPS := 100
## The angle limits of the poses between, degrees: `hold_hand.py`'s `LIMITS["index"]`, but the
## knuckle may spread and straighten further off the gun (to 25 degrees each way; a person's index
## knuckle straightens 20 to 30 degrees past flat, and the hold's own poses stop at 20 and 15).
const LOW := [-25.0, -25.0, 0.0, 0.0]
const HIGH := [25.0, 95.0, 110.0, 80.0]
## The ways tried, as how many poses between.
const STOPS: Array[int] = [2, 3]

var _stage: HoldStage
var _other: HandContact.HandSkin
var _report := PackedStringArray()
var _report_path := ""
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var body := DEFAULT_BODY if arguments.is_empty() else arguments[0]
	if arguments.size() > 1:
		_report_path = arguments[1]
	var sweep_only := arguments.has("sweep")
	if not HoldStage.MODELS.has(body):
		printerr("solve_pistol_trigger_way: a body ", HoldStage.MODELS.keys())
		quit(1)
		return
	_rng.seed = 1272
	_stage = HoldStage.make(root, body)
	await process_frame
	# The aimed pistol in both hands, the trigger finger along the frame (a reload's weight takes it
	# off the trigger, as the test does).
	_stage.pose(CharacterClips.PISTOL_AIM, AIM_TIME, 1.0)
	_stage.hold.set(&"reload_weight", 1.0)
	_stage.hold.call(&"refresh")
	await _stage.settle()
	_other = _stage.contact.hand_skin("l")
	var hold := _stage.hold
	var frame := _angles(_rotations(hold.get(&"grip_pose")))
	var trigger := _angles(_rotations(hold.get(&"trigger_pose")))
	_say("body %s" % body)
	_say("frame %s trigger %s" % [_fmt(frame), _fmt(trigger)])
	var now: Array = []
	var way: HandPoseWay = hold.get(&"trigger_way")
	if way != null:
		for pose in way.poses:
			now.append(_angles(_rotations(pose)))
	elif hold.get(&"trigger_way_pose") != null:
		now.append(_angles(_rotations(hold.get(&"trigger_way_pose"))))
	_say("the way now: %s" % ", ".join(now.map(_fmt)))
	_sweep([frame] + now + [trigger], true)
	if sweep_only:
		_finish(0)
		return
	var best: Array = []
	var best_cost := INF
	for stops in STOPS:
		var found := _search(frame, trigger, now, stops)
		var cost := _cost([frame] + found + [trigger], SEARCH_STEPS)
		_say("%d poses between: %s, cost %.3f" % [stops, ", ".join(found.map(_fmt)), cost])
		if cost < best_cost:
			best_cost = cost
			best = found
	var deepest := _sweep([frame] + best + [trigger], true)
	if deepest.x > LIMIT or deepest.y > LIMIT:
		_say(
			(
				"no way within %.1f mm (gun %.2f, hand %.2f); nothing written"
				% [LIMIT * 1e3, deepest.x * 1e3, deepest.y * 1e3]
			)
		)
		_finish(1)
		return
	var written := HandPoseWay.new()
	for angles: Array in best:
		var pose := HandPose.new()
		pose.rotations = Authored.rotations(_stage.skeleton, "r", "index", angles)
		written.poses.append(pose)
	var out := OUT
	var error := OK
	if body == DEFAULT_BODY:
		written.resource_path = OUT
		error = ResourceSaver.save(written, OUT)
	else:
		out = FIT % body
		var fit := load(out) as HoldFit
		fit.trigger_way = written
		error = ResourceSaver.save(fit, out)
	_say("wrote %s: %d poses (error %d)" % [out, written.poses.size(), error])
	_finish(error)


func _finish(code: int) -> void:
	if not _report_path.is_empty():
		var file := FileAccess.open(_report_path, FileAccess.WRITE)
		file.store_string("\n".join(_report) + "\n")
	_stage.free()
	quit(code)


func _say(line: String) -> void:
	print(line)
	_report.append(line)


static func _fmt(angles: Array) -> String:
	return "[%.1f, %.1f, %.1f, %.1f]" % angles


static func _rotations(pose: HandPose) -> Dictionary:
	var found := {}
	for bone in BONES:
		found[bone] = pose.rotations[bone]
	return found


# The solver's angles of an index finger's rotations (`Authored.rotations` backwards): the first
# bone turned about its rest's Z, then X; the other two about X.
func _angles(rotations: Dictionary) -> Array:
	var found: Array = []
	for joint in 3:
		var bone := BONES[joint]
		var rest := _stage.skeleton.get_bone_rest(_stage.skeleton.find_bone(bone)).basis
		var turn := rest.orthonormalized().inverse() * Basis(rotations[bone] as Quaternion)
		if joint == 0:
			var spread := atan2(turn.x.y, turn.x.x)
			var bent := Basis(Vector3.BACK, -spread) * turn
			found.append_array([rad_to_deg(spread), rad_to_deg(atan2(bent.y.z, bent.y.y))])
		else:
			found.append(rad_to_deg(atan2(turn.y.z, turn.y.y)))
	return found


# A way's poses from angles, as `HandPose` rotations hold them.
func _poses(way: Array) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for angles: Array in way:
		found.append(Authored.rotations(_stage.skeleton, "r", "index", angles))
	return found


# Where the finger is `weight` of the way along, as `HandPoseModifier._on_the_way` puts it.
static func _on_the_way(poses: Array[Dictionary], weight: float) -> Dictionary:
	var legs := poses.size() - 1
	var leg := mini(floori(weight * legs), legs - 1)
	var share := weight * legs - leg
	var found := {}
	for bone in BONES:
		found[bone] = (poses[leg][bone] as Quaternion).slerp(poses[leg + 1][bone], share)
	return found


# How deep the finger posed `rotations` is in the gun (read through) and in the left hand, metres.
func _depth(rotations: Dictionary) -> Vector2:
	_stage.contact.pose_chain(rotations)
	var parts := _stage.contact.measure_through("r", PARTS, _other)
	var deepest := Vector2(-INF, -INF)
	for part in PARTS:
		deepest.x = maxf(deepest.x, -(parts[part] as Vector2).x)
		deepest.y = maxf(deepest.y, -(parts[part] as Vector2).y)
	return deepest


# The deepest the way goes into the gun and the left hand, over `steps` equal parts of each leg;
# with `say` every hundredth that goes deeper than `AIM` is printed.
func _sweep(way: Array, say: bool) -> Vector2:
	var poses := _poses(way)
	var deepest := Vector2(-INF, -INF)
	var count := CHECK_STEPS
	var worst_at := Vector2.ZERO
	for step in count + 1:
		var weight := float(step) / count
		var depth := _depth(_on_the_way(poses, weight))
		if depth.x > deepest.x:
			deepest.x = depth.x
			worst_at.x = weight
		if depth.y > deepest.y:
			deepest.y = depth.y
			worst_at.y = weight
		if say and maxf(depth.x, depth.y) > AIM:
			_say("  %.2f: gun %.2f mm, left hand %.2f mm" % [weight, depth.x * 1e3, depth.y * 1e3])
	if say:
		_say(
			(
				"  deepest: gun %.2f mm at %.2f, left hand %.2f mm at %.2f"
				% [deepest.x * 1e3, worst_at.x, deepest.y * 1e3, worst_at.y]
			)
		)
	return deepest


# What a way costs: each millimetre a step goes deeper than `AIM` (the left hand counted ten
# times), the deepest step's alone and the sum, and a little for the way's length in degrees.
func _cost(way: Array, steps: int) -> float:
	var poses := _poses(way)
	var legs := poses.size() - 1
	var total := 0.0
	var worst := 0.0
	var count := steps * legs
	for step in range(1, count):
		var depth := _depth(_on_the_way(poses, float(step) / count))
		var over := maxf(depth.x - AIM, 0.0) + 10.0 * maxf(depth.y - AIM, 0.0)
		worst = maxf(worst, over)
		total += over
	var travel := 0.0
	for leg in legs:
		for index in 4:
			travel += absf(float(way[leg + 1][index]) - float(way[leg][index]))
	return 1000.0 * (worst + total / count) + 0.002 * travel


# The poses between of the least costly way with `stops` of them: a first guess from the way the
# hold has (its poses spread along it), then the bones bent and spread in steps that halve.
func _search(frame: Array, trigger: Array, now: Array, stops: int) -> Array:
	var guesses: Array = []
	# Along the way the hold has.
	guesses.append(_spread(frame, now, trigger, stops))
	# Off the frame to its side, the last two bones bent there, then in: the way a finger is taught
	# to come to the trigger, from a few sides and lifts.
	for side in [-25.0, -20.0, -15.0, -10.0]:
		for lift in [-25.0, -20.0, -10.0, 0.0]:
			for curl in [0.0, 15.0]:
				var out_pose := [side, lift, frame[2], frame[3]]
				var bent := [side, lift, trigger[2] - curl, trigger[3] + curl]
				var guess := [out_pose, bent]
				while guess.size() < stops:
					guess.append(_mix(bent, trigger, 0.5))
				guesses.append(_clamped(guess.slice(0, stops)))
	var best: Array = []
	var best_cost := INF
	for guess: Array in guesses:
		var cost := _cost([frame] + guess + [trigger], SEARCH_STEPS)
		if cost < best_cost:
			best_cost = cost
			best = guess
	_say("  %d poses between, first guess %s: %.3f" % [stops, ", ".join(best.map(_fmt)), best_cost])
	for scale in [8.0, 4.0, 2.0, 1.0, 0.5]:
		for _try in 40:
			var tried := _nudged(best, scale)
			var cost := _cost([frame] + tried + [trigger], SEARCH_STEPS)
			if cost < best_cost:
				best_cost = cost
				best = tried
		_say("  scale %.1f: %.3f" % [scale, best_cost])
	return best


# `stops` poses spread evenly along the way `frame`, `now`..., `trigger`.
func _spread(frame: Array, now: Array, trigger: Array, stops: int) -> Array:
	var way := [frame] + now + [trigger]
	var found: Array = []
	for stop in stops:
		var at := float(stop + 1) / (stops + 1) * (way.size() - 1)
		var leg := mini(floori(at), way.size() - 2)
		found.append(_mix(way[leg], way[leg + 1], at - leg))
	return found


static func _mix(a: Array, b: Array, share: float) -> Array:
	var found: Array = []
	for index in 4:
		found.append(lerpf(a[index], b[index], share))
	return found


func _clamped(way: Array) -> Array:
	var found: Array = []
	for angles: Array in way:
		var kept: Array = []
		for index in 4:
			kept.append(clampf(angles[index], LOW[index], HIGH[index]))
		found.append(kept)
	return found


# One or two angles of one or two poses moved by up to `scale` degrees.
func _nudged(way: Array, scale: float) -> Array:
	var found: Array = []
	for angles: Array in way:
		found.append(angles.duplicate())
	for change in _rng.randi_range(1, 3):
		var stop := _rng.randi_range(0, found.size() - 1)
		var index := _rng.randi_range(0, 3)
		found[stop][index] = float(found[stop][index]) + _rng.randf_range(-scale, scale)
	return _clamped(found)
