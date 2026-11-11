## Solves the rifle's trigger finger's way from along the receiver to the trigger (kit #1036) and
## writes it as `gameplay/weapon/hold/rifle_trigger_way.tres` (a `HandPoseWay`). The straight way
## between `rifle_grip_pose` and `rifle_trigger_pose` takes the fingertip through the magazine
## well and the trigger guard (17 mm deep): the finger lies along the well's side ahead of the
## guard and curls in before it is over the guard's opening. The solver measures the skinned
## finger of both mannequins against the rifle's triangles (`HandContact`, the right hand on its
## place on the rifle at the low ready) and builds the way from poses:
##
## - a first guess: the straight finger rolled about its own length until its bend lies along the
##   rifle's side, then bent to the trigger's bend there (each roll in `ROLLS` is tried, the one
##   whose two legs go least deep is kept);
## - then, while a leg of the way goes deeper than `LIMIT` at any of its `SAMPLES` steps, the
##   deepest step of the deepest leg is moved out of the rifle (a seeded random climb over the
##   knuckle's turn and the two outer bones' bends) and becomes a pose of the way.
##
## No number of the way is typed: change the rifle, the hold or the poses, run this again, then
## `tests/gameplay/test_rifle_fingers.gd`. It lives in tools/, which the export leaves out.
##
## `<godot> --headless --path game -s res://tools/hold/solve_trigger_way.gd`
extends SceneTree

const OUT := "res://gameplay/weapon/hold/rifle_trigger_way.tres"
const GRIP := "res://gameplay/weapon/hold/rifle_grip_pose.tres"
const TRIGGER := "res://gameplay/weapon/hold/rifle_trigger_pose.tres"
const BONES: Array[StringName] = [&"index_01_r", &"index_02_r", &"index_03_r"]
const PARTS: Array[String] = ["index_base", "index_mid", "index_tip"]
## The deepest any step of the way may go into the rifle, in metres (the hold's limit is 2 mm).
const LIMIT := 0.0015
## The steps each leg is measured at.
const SAMPLES := 16
## The rolls of the first guess, in degrees about the finger's own length.
const ROLLS: Array[float] = [-120.0, -105.0, -90.0, -75.0, -60.0, 60.0, 75.0, 90.0, 105.0]
## How much further than the trigger's bend the outer bones are bent on the way in.
const TUCKS: Array[float] = [1.2, 1.4, 1.6, 1.8]
## How many poses the way may have, and how many tries the climb has for each.
const MOST_POSES := 12
const TRIES := 160
## What a radian of turn away from the way costs in the climb, in metres of depth.
const PULL := 0.004

var _stages: Array[RifleStage] = []
var _random := RandomNumberGenerator.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_random.seed = 1036
	var holder := Node3D.new()
	root.add_child(holder)
	for model: String in HoldStage.MODELS:
		var stage := RifleStage.make_rifle(holder, model)
		stage.pose_rifle(CharacterClips.IDLE, 0.0, 0.0)
		await stage.settle()
		_stages.append(stage)
	var grip := _pose_of(load(GRIP) as HandPose)
	var trigger := _pose_of(load(TRIGGER) as HandPose)
	print("straight way: %.1f mm deep" % (_leg_depth(grip, trigger)[0] * 1e3))
	var keys := _first_guess(grip, trigger)
	while keys.size() - 2 < MOST_POSES:
		var worst := _worst_leg(keys)
		if worst[1] <= LIMIT:
			break
		var leg: int = worst[0]
		var share: float = worst[2]
		var moved := _climb(_between(keys[leg], keys[leg + 1], share))
		keys.insert(leg + 1, moved)
		print("pose %d added in leg %d: %.1f mm before" % [keys.size() - 2, leg, worst[1] * 1e3])
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
	var error := ResourceSaver.save(way, OUT)
	print("wrote %s: %d poses (error %d)" % [OUT, way.poses.size(), error])
	holder.free()
	quit(error)


# The index finger's rotations of a pose.
func _pose_of(pose: HandPose) -> Dictionary:
	var found := {}
	for bone in BONES:
		found[bone] = pose.rotations[bone]
	return found


# Grip, the straight finger rolled, the rolled finger bent, trigger: the roll whose first two
# legs go least deep. Then the way into the trigger: the knuckle turned to the trigger's with the
# outer bones bent further than the trigger's by each of `TUCKS` (the fingertip tucked back from
# the guard's front), then straightened onto the trigger; the tuck whose way goes least deep is
# kept, none when none helps.
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
		var depth := maxf(_leg_depth(grip, rolled)[0], _leg_depth(rolled, bent)[0])
		print("roll %.0f: %.1f mm" % [roll, depth * 1e3])
		if depth < best_depth:
			best_depth = depth
			best = [grip, rolled, bent, trigger]
	var plain := _way_depth(best)
	var chosen := best
	print("into the trigger straight: %.1f mm" % (plain * 1e3))
	for tuck in TUCKS:
		var tucked := trigger.duplicate()
		for bone: StringName in [&"index_02_r", &"index_03_r"]:
			var q := trigger[bone] as Quaternion
			tucked[bone] = Quaternion(Vector3.RIGHT, 2.0 * atan2(q.x, q.w) * tuck)
		for share in [0.5, 1.0]:
			var turned := tucked.duplicate()
			turned[&"index_01_r"] = (best[2][&"index_01_r"] as Quaternion).slerp(
				trigger[&"index_01_r"], share
			)
			var keys: Array[Dictionary] = [best[0], best[1], best[2], turned, trigger]
			var depth := _way_depth(keys)
			print("tuck %.2f, knuckle %.1f of the way: %.1f mm" % [tuck, share, depth * 1e3])
			if depth < plain:
				plain = depth
				chosen = keys
	return chosen


func _way_depth(keys: Array[Dictionary]) -> float:
	var deepest := -INF
	for leg in keys.size() - 1:
		deepest = maxf(deepest, _leg_depth(keys[leg], keys[leg + 1])[0])
	return deepest


# [the leg, its depth, the share of it at its deepest step] of the deepest leg of the way.
func _worst_leg(keys: Array[Dictionary]) -> Array:
	var worst := [0, -INF, 0.5]
	for leg in keys.size() - 1:
		var depth := _leg_depth(keys[leg], keys[leg + 1])
		if depth[0] > worst[1]:
			worst = [leg, depth[0], depth[1]]
	return worst


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


# How deep the finger posed `rotations` goes into the rifle, the deeper of the two mannequins, in
# metres (below 0: that far off it).
func _depth(rotations: Dictionary) -> float:
	var deepest := -INF
	for stage in _stages:
		stage.contact.pose_chain(rotations)
		var parts := stage.contact.measure_parts("r", PARTS)
		for part in PARTS:
			deepest = maxf(deepest, -float(parts[part]))
	return deepest


# `start` moved out of the rifle by as little as it takes: random turns of the knuckle and bends
# of the outer two bones, each kept when it scores better, smaller as the climb goes on. The score
# is the depth below `LIMIT` and the turn from `start` (`PULL` metres a radian), so the pose stays
# near the way it replaces and the legs on both sides of it stay short.
func _climb(start: Dictionary) -> Dictionary:
	var best := start
	var best_score := _score(start, start)
	for attempt in TRIES:
		var size := lerpf(0.3, 0.02, float(attempt) / TRIES)
		var tried := best.duplicate()
		var turn := Vector3(_random.randfn(), _random.randfn(), _random.randfn()) * size
		tried[&"index_01_r"] = (
			(best[&"index_01_r"] as Quaternion) * Quaternion(turn.normalized(), turn.length())
		)
		for bone: StringName in [&"index_02_r", &"index_03_r"]:
			var bend := Quaternion(Vector3.RIGHT, _random.randfn() * size)
			tried[bone] = (best[bone] as Quaternion) * bend
		var score := _score(tried, start)
		if score < best_score:
			best_score = score
			best = tried
	return best


func _score(rotations: Dictionary, start: Dictionary) -> float:
	var turned := 0.0
	for bone in BONES:
		turned += (rotations[bone] as Quaternion).angle_to(start[bone])
	return maxf(_depth(rotations), LIMIT * 0.5) + PULL * turned
