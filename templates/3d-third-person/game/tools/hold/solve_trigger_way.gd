## Solves the rifle's trigger finger's way from along the receiver to the trigger (kit #1036) and
## writes it as `gameplay/weapon/hold/rifle_trigger_way.tres` (a `HandPoseWay`). The straight way
## between `rifle_grip_pose` and `rifle_trigger_pose` takes the fingertip through the magazine
## well and the trigger guard (17 mm deep): the finger lies along the well's side ahead of the
## guard and curls in before it is over the guard's opening. The solver measures the skinned
## finger of one body against the rifle's triangles (`HandContact`, the right hand on its place on
## the rifle at the low ready, with that body's own hold: the scene's for the female, the
## `HoldFit` for any other) and builds the way from two poses: the straight finger
## rolled about its own length until its bend lies along the rifle's side, then bent to the
## trigger's bend there, then turned onto the trigger (each roll in `ROLLS` is tried, the one whose
## way goes least deep is kept).
##
## Nothing is written when a leg of the way goes deeper than `LIMIT` at any of its `SAMPLES` steps.
## The way is a passing way, held to the depth a hand may pass through the weapon between two
## places (the reload's 6 mm), not to the 2 mm of a hand that holds: the finger comes into the
## trigger guard from the side through an opening hardly wider than the finger, and no way into
## it found passes less than about 5.6 mm through the guard on the last stretch (inserting poses
## at the deepest step, turned and bent every way near it, stalled there: the trigger pose sits in
## a pocket).
##
## No number of the way is typed: change the rifle, the hold or the poses, run this again, then
## `tests/gameplay/test_rifle_fingers.gd`. It lives in tools/, which the export leaves out.
##
## Each body has its own way, as it has its own hold (kit #1187): the default body's (`female`)
## is `rifle_trigger_way.tres`, which `rifle_held.tscn` names; another body's is written into its
## fit (`rifle_fit_<body>.tres`, `HoldFit.trigger_way`). Run it after `write_hold.gd` for that
## body, since the way starts and ends on that body's poses.
##
## `<godot> --headless --path game -s res://tools/hold/solve_trigger_way.gd -- [female|male]`
extends SceneTree

const OUT := "res://gameplay/weapon/hold/rifle_trigger_way.tres"
const FIT := "res://gameplay/weapon/hold/rifle_fit_%s.tres"
## The body whose way is the scene's own; every other body's is in its `HoldFit` file.
const DEFAULT_BODY := "female"
const BONES: Array[StringName] = [&"index_01_r", &"index_02_r", &"index_03_r"]
const PARTS: Array[String] = ["index_base", "index_mid", "index_tip"]
## The deepest any step of the way may go into the rifle, in metres: the depth a hand may pass
## through the weapon on its way between two places (the reload's, `test_rifle_hold.gd`). Where
## the finger holds, at either end, the hold's 2 mm stand.
const LIMIT := 0.006
## The steps each leg is measured at.
const SAMPLES := 16
## The rolls of the first guess, in degrees about the finger's own length.
const ROLLS: Array[float] = [-120.0, -105.0, -90.0, -75.0, 75.0, 90.0, 105.0, 120.0]

var _stages: Array[RifleStage] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var body := DEFAULT_BODY
	var arguments := OS.get_cmdline_user_args()
	if not arguments.is_empty():
		body = arguments[0]
	if not HoldStage.MODELS.has(body):
		printerr("solve_trigger_way: a body ", HoldStage.MODELS.keys())
		quit(1)
		return
	var holder := Node3D.new()
	root.add_child(holder)
	var stage := RifleStage.make_rifle(holder, body)
	stage.pose_rifle(CharacterClips.IDLE, 0.0, 0.0)
	await stage.settle()
	_stages.append(stage)
	# The poses the hold put on for this body (the scene's own, or its fit's).
	var held := stage.hold as TwoHandHold
	var grip := _pose_of(held.grip_pose)
	var trigger := _pose_of(held.trigger_pose)
	print("body %s" % body)
	print("straight way: %.1f mm deep" % (_leg_depth(grip, trigger)[0] * 1e3))
	var keys := _first_guess(grip, trigger)
	var report := "legs:"
	var deepest := 0.0
	for leg in keys.size() - 1:
		var depth: float = _leg_depth(keys[leg], keys[leg + 1])[0]
		deepest = maxf(deepest, depth)
		report += " %.1f" % (depth * 1e3)
	print(report + " mm; the deepest %.1f mm" % (deepest * 1e3))
	if deepest > LIMIT:
		printerr("no way within %.1f mm; nothing written" % (LIMIT * 1e3))
		quit(1)
		return
	var way := HandPoseWay.new()
	for index in range(1, keys.size() - 1):
		var pose := HandPose.new()
		var rotations: Dictionary[StringName, Quaternion] = {}
		for bone in BONES:
			rotations[bone] = (keys[index][bone] as Quaternion).normalized()
		pose.rotations = rotations
		way.poses.append(pose)
	var out := OUT
	var error := OK
	if body == DEFAULT_BODY:
		error = ResourceSaver.save(way, OUT)
	else:
		out = FIT % body
		var fit := load(out) as HoldFit
		fit.trigger_way = way
		error = ResourceSaver.save(fit, out)
	print("wrote %s: %d poses (error %d)" % [out, way.poses.size(), error])
	holder.free()
	quit(error)


# The index finger's rotations of a pose.
func _pose_of(pose: HandPose) -> Dictionary:
	var found := {}
	for bone in BONES:
		found[bone] = pose.rotations[bone]
	return found


# Grip, the straight finger rolled, the rolled finger bent, trigger: the roll whose way goes least
# deep.
func _first_guess(grip: Dictionary, trigger: Dictionary) -> Array[Dictionary]:
	var best: Array[Dictionary] = [grip, trigger]
	var best_depth := INF
	for roll in ROLLS:
		var rolled := grip.duplicate()
		rolled[&"index_01_r"] = (
			(grip[&"index_01_r"] as Quaternion) * Quaternion(Vector3.UP, deg_to_rad(roll))
		)
		var bent := rolled.duplicate()
		bent[&"index_02_r"] = trigger[&"index_02_r"]
		bent[&"index_03_r"] = trigger[&"index_03_r"]
		var depth := _way_depth([grip, rolled, bent, trigger])
		print("roll %.0f: %.1f mm" % [roll, depth * 1e3])
		if depth < best_depth:
			best_depth = depth
			best = [grip, rolled, bent, trigger]
	return best


func _way_depth(keys: Array[Dictionary]) -> float:
	var deepest := -INF
	for leg in keys.size() - 1:
		deepest = maxf(deepest, _leg_depth(keys[leg], keys[leg + 1])[0])
	return deepest


# [the deepest the finger goes on the straight way from `from` to `to`, the share at it].
func _leg_depth(from: Dictionary, to: Dictionary) -> Array:
	var deepest := -INF
	var at := 0.5
	for step in SAMPLES + 1:
		var share := float(step) / SAMPLES
		var depth := _depth(_between(from, to, share))
		if depth > deepest:
			deepest = depth
			at = share
	return [deepest, at]


func _between(from: Dictionary, to: Dictionary, share: float) -> Dictionary:
	var found := {}
	for bone in BONES:
		found[bone] = (from[bone] as Quaternion).slerp(to[bone], share)
	return found


# How deep the finger posed `rotations` goes into the rifle, in metres (below 0: that far off it).
func _depth(rotations: Dictionary) -> float:
	var deepest := -INF
	for stage in _stages:
		stage.contact.pose_chain(rotations)
		var parts := stage.contact.measure_parts("r", PARTS)
		for part in PARTS:
			deepest = maxf(deepest, -float(parts[part]))
	return deepest
