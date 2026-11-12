## Fits another body's right hand to the default body's finger placement in the one-handed aim
## (kit #1274): the pistol is held one-handed with one placement for every body, the female's
## (`DEFAULT_BODY`). Her fingers are measured on the gun (each finger's middle and last joints
## and its tip, in the gun's own space: `one_hand_match.gd`), then each finger of `body` is turned
## until the same points land on the same places, while it stays within the hold suite's limits
## (no part deeper than `DEPTH`; where it holds, no holding part farther off than `FLOAT`). The
## seat and the knuckles stay the body's own: a larger hand sits farther out on the grip. Two
## poses are fitted (`POSES`): the aim (`one_hand`, every finger) and the trigger finger's stop
## half-way up to it (`one_hand_way`), so it goes the same way on the gun on every body too. The
## stop is fitted with its two legs (from the body's own grip, then on to its fitted aim) held to
## `DEPTH` at `LEG_SAMPLES` steps each. The thumb keeps the body's own way (`thumb_way_pose`): it
## leaves from the body's own carried grip, whose thumb lies elsewhere on each body (kit #1262),
## and fitted to the default body's stop the male thumb's first leg went 6 mm into the frame.
##
## The angles are a finger's spread and three bends, the thumb's six (`authored_pose.gd`), so each
## pose is written into `tools/hold/pistol_authored.json`, where `write_hold.gd` lays it over
## every later solve, and as `<pose>_pose` in the body's fit (the default body's own files,
## `pistol_one_hand_pose.tres` and `pistol_one_hand_way_pose.tres`). Run with the default body
## first: its own placement is kept and only cleared to the limits (a seat moved under it, kit
## #1262, put its thumb 2.6 mm into the frame), then with each other body. Without `write`, it
## prints the fit and writes nothing.
##
## `<godot> --headless --path game -s res://tools/hold/fit_one_hand.gd -- [male] [write]`
extends SceneTree

const Authored := preload("res://tools/hold/authored_pose.gd")
const Match := preload("res://tools/hold/one_hand_match.gd")
const DEFAULT_BODY := "female"
const FIT := "res://gameplay/weapon/hold/pistol_fit_%s.tres"
## The default body's poses, which the hold scene names.
const OWN := "res://gameplay/weapon/hold/pistol_%s_pose.tres"
const FINGERS: Array[String] = ["index", "middle", "ring", "pinky", "thumb"]
## Each pose fitted: how far the aim is up where it is whole (the way's one stop is at half), the
## fingers it names, and whether they hold the gun there (`FLOAT` counts).
const POSES: Dictionary[String, Array] = {
	"one_hand": [1.0, FINGERS, true],
	"one_hand_way": [0.5, ["index"], false],
}
## How much each point counts: the middle joint, the last joint, the tip.
const WEIGHTS: Array[float] = [0.5, 1.0, 1.5]
## The search's limits, in metres: a little inside the suite's 2 mm in and 5 mm off.
const DEPTH := 0.0015
const FLOAT := 0.004
## The shares of each leg of the way measured while the stop is fitted.
const LEG_SAMPLES: Array[float] = [0.2, 0.4, 0.6, 0.8]
## The steps the search tries on each angle, in degrees, coarse to fine.
const STEPS: Array[float] = [8.0, 4.0, 2.0, 1.0, 0.5, 0.25]

var _stage: HoldStage
var _to_gun := Transform3D.IDENTITY
# For the way's stop: each finger's rotations where the way leaves from and where it ends.
var _legs := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var body := "male"
	for word in arguments:
		if HoldStage.MODELS.has(word):
			body = word
	var fitted := {}
	for key: String in POSES:
		var aim: float = POSES[key][0]
		var holds: bool = POSES[key][2]
		var default := await _staged(DEFAULT_BODY, aim)
		var targets := Match.places(default)
		var theirs := {}
		for finger: String in POSES[key][1]:
			theirs[finger] = angles_of(default, finger)
		default.free()
		_stage = await _staged(body, aim)
		_to_gun = _stage.pistol.global_transform.affine_inverse() * _stage.skeleton.global_transform
		fitted[key] = {}
		_legs.clear()
		if not holds:
			var grip: HandPose = _stage.hold.get(&"grip_pose")
			for finger: String in POSES[key][1]:
				var ends := Authored.rotations(
					_stage.skeleton, "r", finger, fitted["one_hand"][finger]
				)
				var starts: Dictionary[StringName, Quaternion] = {}
				for bone: StringName in ends:
					starts[bone] = grip.rotations[bone]
				_legs[finger] = [starts, ends]
		for finger: String in POSES[key][1]:
			# From the body's own pose and from the default body's angles (a thumb that goes
			# round the tang on one and over it on the other is a valley apart): the better.
			var own := angles_of(_stage, finger)
			var before := _cost(finger, own, targets, holds)
			var angles := _search(finger, own, targets, holds)
			var other := _search(finger, theirs[finger], targets, holds)
			if _cost(finger, other, targets, holds) < _cost(finger, angles, targets, holds):
				angles = other
			var after := _cost(finger, angles, targets, holds)
			fitted[key][finger] = angles
			print(
				(
					"FIT %s %s %s: cost %.1f -> %.1f, apart %s, gun %s"
					% [body, key, finger, before, after, _apart(finger, targets), _gaps(finger)]
				)
			)
		_stage.free()
	print("ANGLES ", JSON.stringify(fitted))
	if "write" in arguments:
		_write(body, fitted)
	quit()


# `body` on a stage, one-handed, with the aim `aim` up, after the hold's modifiers ran.
func _staged(body: String, aim: float) -> HoldStage:
	var stage := HoldStage.make(root, body)
	stage.hold.set(&"one_handed", true)
	await process_frame
	stage.pose(CharacterClips.PISTOL_AIM, 0.0, aim, &"ual1/Idle", [WeaponDef.FREE_ARM_BONE])
	await stage.settle()
	return stage


## A finger's angles as `stage` holds it now, read back from its bones' rotations, to 0.25
## degrees.
static func angles_of(stage: HoldStage, finger: String) -> Array:
	var skeleton := stage.skeleton
	var turns: Array[Basis] = []
	for joint in 3:
		var bone_name := StringName("%s_0%d_r" % [finger, joint + 1])
		var bone := skeleton.find_bone(bone_name)
		var above := skeleton.get_bone_name(skeleton.get_bone_parent(bone))
		var local := (
			stage.contact.bone_pose(above).basis.inverse()
			* stage.contact.bone_pose(bone_name).basis
		)
		var rest := skeleton.get_bone_rest(bone).basis.orthonormalized()
		turns.append(rest.inverse() * local.orthonormalized())
	if finger == "thumb":
		var root_angles := turns[0].get_euler(EULER_ORDER_YZX)
		var middle := _spread_bend(turns[1])
		var thumb := [
			rad_to_deg(root_angles.y),
			rad_to_deg(root_angles.z),
			rad_to_deg(root_angles.x),
			middle[0],
			middle[1],
			_bend(turns[2]),
		]
		return thumb.map(func(angle: float) -> float: return snappedf(angle, 0.25))
	var first := _spread_bend(turns[0])
	var found := [first[0], first[1], _bend(turns[1]), _bend(turns[2])]
	return found.map(func(angle: float) -> float: return snappedf(angle, 0.25))


# A turn as a spread about Z then a bend about X, in degrees.
static func _spread_bend(turn: Basis) -> Array:
	var spread := atan2(turn.x.y, turn.x.x)
	var rest := Basis(Vector3.BACK, -spread) * turn
	return [rad_to_deg(spread), rad_to_deg(atan2(rest.y.z, rest.y.y))]


static func _bend(turn: Basis) -> float:
	return rad_to_deg(atan2(turn.y.z, turn.y.y))


# Coordinate descent over the angles, coarse steps to fine.
func _search(finger: String, start: Array, targets: Dictionary, holds: bool) -> Array:
	var best := start.duplicate()
	var best_cost := _cost(finger, best, targets, holds)
	for step in STEPS:
		var better := true
		while better:
			better = false
			for index in best.size():
				for direction: float in [1.0, -1.0]:
					var tried := best.duplicate()
					tried[index] = snappedf(tried[index] + direction * step, 0.25)
					var cost := _cost(finger, tried, targets, holds)
					if cost < best_cost - 1e-4:
						best = tried
						best_cost = cost
						better = true
	return best


# How far the finger's points are from the targets (mm squared, weighted), plus a steep cost for
# any part deeper than the limit or, where it `holds`, farther off.
func _cost(finger: String, angles: Array, targets: Dictionary, holds: bool) -> float:
	_stage.contact.pose_chain(Authored.rotations(_stage.skeleton, "r", finger, angles))
	var cost := 0.0
	var points := _points(finger)
	for index in 3:
		var key: String = ["%s_2", "%s_3", "%s_tip"][index] % finger
		cost += WEIGHTS[index] * ((points[key] - targets[key]) * 1e3).length_squared()
	var gaps := _stage.contact.measure_parts("r", _parts(finger))
	for part: String in gaps:
		var gap: float = gaps[part]
		if gap < -DEPTH:
			cost += 1e3 * pow((-gap - DEPTH) * 1e3, 2.0)
		elif holds and part in HoldStage.RIGHT_CONTACTS and gap > FLOAT:
			cost += 1e3 * pow((gap - FLOAT) * 1e3, 2.0)
	if _legs.has(finger):
		cost += _legs_cost(finger, Authored.rotations(_stage.skeleton, "r", finger, angles))
		_stage.contact.pose_chain(Authored.rotations(_stage.skeleton, "r", finger, angles))
	return cost


# The steep cost of the way's two legs through `stop`: any part deeper than `DEPTH`.
func _legs_cost(finger: String, stop: Dictionary) -> float:
	var cost := 0.0
	var starts: Dictionary = _legs[finger][0]
	var ends: Dictionary = _legs[finger][1]
	for leg in 2:
		for share in LEG_SAMPLES:
			var turned := {}
			for bone: StringName in stop:
				var from: Quaternion = starts[bone] if leg == 0 else stop[bone]
				var to: Quaternion = stop[bone] if leg == 0 else ends[bone]
				turned[bone] = from.slerp(to, share)
			_stage.contact.pose_chain(turned)
			var gaps := _stage.contact.measure_parts("r", _parts(finger))
			for part: String in gaps:
				if gaps[part] < -DEPTH:
					cost += 1e3 * pow((-gaps[part] - DEPTH) * 1e3, 2.0)
	return cost


# The finger's middle and last joints and tip, in the gun's space.
func _points(finger: String) -> Dictionary:
	var bone := "%s_0%d_r"
	return {
		finger + "_2": _to_gun * _stage.contact.bone_pose(StringName(bone % [finger, 2])).origin,
		finger + "_3": _to_gun * _stage.contact.bone_pose(StringName(bone % [finger, 3])).origin,
		finger + "_tip": _to_gun * Match.tip(_stage, StringName(bone % [finger, 3])),
	}


static func _parts(finger: String) -> Array[String]:
	return [finger + "_base", finger + "_mid", finger + "_tip"]


func _apart(finger: String, targets: Dictionary) -> String:
	var points := _points(finger)
	var text := PackedStringArray()
	for key: String in points:
		text.append("%s %.1f" % [key, (points[key] as Vector3).distance_to(targets[key]) * 1e3])
	return ", ".join(text)


func _gaps(finger: String) -> String:
	var gaps := _stage.contact.measure_parts("r", _parts(finger))
	var text := PackedStringArray()
	for part: String in gaps:
		text.append("%s %.1f" % [part, gaps[part] * 1e3])
	return ", ".join(text)


# The fitted poses in the authored file and in the body's `HoldFit` (the default body's files).
func _write(body: String, fitted: Dictionary) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(Authored.FILE))
	var file: Dictionary = parsed if parsed is Dictionary else {}
	if not file.has(body):
		file[body] = {}
	for key: String in fitted:
		file[body][key] = fitted[key]
	var out := FileAccess.open(Authored.FILE, FileAccess.WRITE)
	out.store_string(JSON.stringify(file, "\t", false) + "\n")
	out.close()
	print("wrote ", Authored.FILE)
	var fit: HoldFit = null if body == DEFAULT_BODY else load(FIT % body) as HoldFit
	var rig := (load(CharacterBodies.BY_NAME[body]) as PackedScene).instantiate()
	var skeleton := rig.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for key: String in fitted:
		var pose := HandPose.new()
		var rotations: Dictionary[StringName, Quaternion] = {}
		for finger: String in fitted[key]:
			var turned := Authored.rotations(skeleton, "r", finger, fitted[key][finger])
			for bone: StringName in turned:
				var q := turned[bone]
				rotations[bone] = Quaternion(
					snappedf(q.x, 1e-5),
					snappedf(q.y, 1e-5),
					snappedf(q.z, 1e-5),
					snappedf(q.w, 1e-5)
				)
		pose.rotations = rotations
		if fit == null:
			print("wrote ", OWN % key, " (", ResourceSaver.save(pose, OWN % key), ")")
		else:
			fit.set(key + "_pose", pose)
	rig.free()
	if fit != null:
		print("wrote ", FIT % body, " (", ResourceSaver.save(fit), ")")
