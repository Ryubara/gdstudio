## Writes the rifle's trigger finger's way from along the receiver to the trigger (kit #1036,
## kit #1283) as a `HandPoseWay`: the default body's (`female`) into
## `gameplay/weapon/hold/rifle_trigger_way.tres`, which `rifle_held.tscn` names, another body's
## into its fit (`rifle_fit_<body>.tres`, `HoldFit.trigger_way`). The straight way between
## `rifle_grip_pose` and `rifle_trigger_pose` takes the fingertip 20 to 24 mm into the magazine well
## and the trigger guard: the finger lies along the well's side ahead of the guard and curls in
## before it is over the guard's opening.
##
## The way is planned by `plan_trigger_way.py` (a search over many poses in numpy) on what this
## script dumps, and only checked and written here, with the game's own measure (`HandContact`, the
## skinned index finger of one body against the rifle's triangles, the right hand on its place at
## the low ready with that body's own hold on):
##
##   1. `<godot> --headless --path game -s res://tools/hold/solve_trigger_way.gd -- <body>
##      --dump=<abs>/way_<body>.json`
##   2. `uv run --no-project --with numpy --with scipy python tools/hold/plan_trigger_way.py
##      <abs>/way_<body>.json <abs>/way_<body>_out.json`
##   3. `<godot> --headless --path game -s res://tools/hold/solve_trigger_way.gd -- <body>
##      --way=<abs>/way_<body>_out.json`
##
## Step 3 measures every leg of the way at `SAMPLES` steps and writes nothing when any step goes
## deeper than `LIMIT` (the 2 mm of a hand that holds, `HandContact.MAX_DEPTH`). With neither
## option it measures the way the body has now. `--report=<file>` writes what it prints to a file
## too (a test run's `print()` reaches no log).
##
## No number of the way is typed: change the rifle, the hold or the poses, run the three steps
## again, then `tests/gameplay/test_rifle_fingers.gd`. Run them after `write_hold.gd` for that body,
## since the way starts and ends on that body's poses. It lives in tools/, which the export leaves
## out.
extends SceneTree

const OUT := "res://gameplay/weapon/hold/rifle_trigger_way.tres"
const FIT := "res://gameplay/weapon/hold/rifle_fit_%s.tres"
## The body whose way is the scene's own; every other body's is in its `HoldFit` file.
const DEFAULT_BODY := "female"
const BONES: Array[StringName] = [&"index_01_r", &"index_02_r", &"index_03_r"]
const PARTS: Array[String] = ["index_base", "index_mid", "index_tip"]
## The deepest any step of the way may go into the rifle, in metres: a finger on its way between
## two places of a holding hand is held to the hold's own 2 mm (kit #1283).
const LIMIT := HandContact.MAX_DEPTH
## The steps each leg is measured at.
const SAMPLES := 40

var _stage: RifleStage
var _lines := PackedStringArray()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var body := DEFAULT_BODY
	var dump := ""
	var way_file := ""
	var report := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dump="):
			dump = argument.trim_prefix("--dump=")
		elif argument.begins_with("--way="):
			way_file = argument.trim_prefix("--way=")
		elif argument.begins_with("--report="):
			report = argument.trim_prefix("--report=")
		else:
			body = argument
	if not HoldStage.MODELS.has(body):
		printerr("solve_trigger_way: a body ", HoldStage.MODELS.keys())
		quit(1)
		return
	var holder := Node3D.new()
	root.add_child(holder)
	_stage = RifleStage.make_rifle(holder, body)
	_stage.pose_rifle(CharacterClips.IDLE, 0.0, 0.0)
	await _stage.settle()
	var held := _stage.hold as TwoHandHold
	var grip := _pose_of(held.grip_pose)
	var trigger := _pose_of(held.trigger_pose)
	_say("body %s" % body)
	_say("straight way: %.2f mm deep" % (_leg_depth(grip, trigger) * 1e3))
	var code := OK
	if not dump.is_empty():
		code = _dump(dump, grip, trigger, held)
	elif not way_file.is_empty():
		code = _write(body, way_file, grip, trigger)
	else:
		var keys: Array[Dictionary] = [grip]
		if held.trigger_way != null:
			for pose in held.trigger_way.poses:
				keys.append(_pose_of(pose))
		keys.append(trigger)
		_say("the way now: the deepest %.2f mm" % (_way_depth(keys) * 1e3))
	if not report.is_empty():
		var file := FileAccess.open(report, FileAccess.WRITE)
		file.store_string("\n".join(_lines) + "\n")
		file.close()
	holder.free()
	quit(code)


func _say(line: String) -> void:
	print(line)
	_lines.append(line)


# Checks the way in `path` (the planner's output: {"poses": [{bone: [x, y, z, w]}, ...]}, the
# poses between the two ends) and writes it when no step of it goes deeper than `LIMIT`.
func _write(body: String, path: String, grip: Dictionary, trigger: Dictionary) -> int:
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		printerr("solve_trigger_way: no way in ", path)
		return ERR_PARSE_ERROR
	var keys: Array[Dictionary] = [grip]
	for entry: Dictionary in (parsed as Dictionary)["poses"]:
		var pose := {}
		for bone in BONES:
			var q: Array = entry[String(bone)]
			pose[bone] = Quaternion(q[0], q[1], q[2], q[3]).normalized()
		keys.append(pose)
	keys.append(trigger)
	var deepest := _way_depth(keys)
	_say("%d poses between; the deepest %.2f mm" % [keys.size() - 2, deepest * 1e3])
	if deepest > LIMIT:
		printerr("no way within %.1f mm; nothing written" % (LIMIT * 1e3))
		return FAILED
	var way := HandPoseWay.new()
	for index in range(1, keys.size() - 1):
		var pose := HandPose.new()
		var rotations: Dictionary[StringName, Quaternion] = {}
		for bone in BONES:
			rotations[bone] = keys[index][bone]
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
	_say("wrote %s: %d poses (error %d)" % [out, way.poses.size(), error])
	return error


# What the planner needs, as JSON: the index finger's skin as `HandContact` measures it (each
# vertex as its bones and its place in each bone's space), every bone pose it hangs from, the chain
# from the hand out, the rifle's triangles and the two ends.
func _dump(path: String, grip: Dictionary, trigger: Dictionary, held: TwoHandHold) -> int:
	var contact := _stage.contact
	var skeleton := _stage.skeleton
	var used := {}
	var parts := {}
	for part in PARTS:
		var list: Array = contact._parts["r"][part]
		var vertices := []
		for index in list.size() / 2:
			var entry: Dictionary = contact._surfaces[list[index * 2]]
			var vertex: int = list[index * 2 + 1]
			var per: int = entry.per
			var rest: Vector3 = (entry.vertices as PackedVector3Array)[vertex]
			var slots := []
			for slot in per:
				var weight: float = (entry.weights as PackedFloat32Array)[vertex * per + slot]
				if weight <= 0.0:
					continue
				var bind: int = (entry.bones as PackedInt32Array)[vertex * per + slot]
				var bone: int = (entry.bind_bones as PackedInt32Array)[bind]
				var local: Vector3 = (entry.bind_poses as Array)[bind] * rest
				used[bone] = true
				slots.append([bone, weight, local.x, local.y, local.z])
			vertices.append(slots)
		parts[part] = vertices
	var chain := []
	for bone_name in BONES:
		var bone := skeleton.find_bone(bone_name)
		var children := []
		for child in skeleton.get_bone_children(bone):
			if not BONES.has(skeleton.get_bone_name(child)):
				children.append([child, _numbers(skeleton.get_bone_pose(child))])
				used[child] = true
		(
			chain
			. append(
				{
					"bone": bone,
					"parent": skeleton.get_bone_parent(bone),
					"position": _vector(skeleton.get_bone_pose_position(bone)),
					"rest":
					_quaternion(skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()),
					"children": children,
				}
			)
		)
		used[skeleton.get_bone_parent(bone)] = true
	var poses := {}
	for bone: int in used:
		poses[str(bone)] = _numbers(contact._poses[bone])
	var to_weapon := (
		(_stage.rifle.get_node(^"Near") as Node3D).global_transform.affine_inverse()
		* skeleton.global_transform
	)
	var triangles := []
	for point in contact._gun.points:
		triangles.append_array([point.x, point.y, point.z])
	var way := []
	if held.trigger_way != null:
		for pose in held.trigger_way.poses:
			way.append(_quaternions(_pose_of(pose)))
	var out := {
		"parts": parts,
		"chain": chain,
		"poses": poses,
		"to_weapon": _numbers(to_weapon),
		"triangles": triangles,
		"grip": _quaternions(grip),
		"trigger": _quaternions(trigger),
		"way": way,
		"limit": LIMIT,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(out))
	file.close()
	_say("wrote %s" % path)
	return OK


# A transform as the planner reads it: the basis's columns, then the origin.
static func _numbers(t: Transform3D) -> Array:
	return [
		t.basis.x.x,
		t.basis.x.y,
		t.basis.x.z,
		t.basis.y.x,
		t.basis.y.y,
		t.basis.y.z,
		t.basis.z.x,
		t.basis.z.y,
		t.basis.z.z,
		t.origin.x,
		t.origin.y,
		t.origin.z,
	]


static func _vector(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _quaternion(q: Quaternion) -> Array:
	return [q.x, q.y, q.z, q.w]


static func _quaternions(pose: Dictionary) -> Dictionary:
	var out := {}
	for bone: StringName in pose:
		out[String(bone)] = _quaternion(pose[bone])
	return out


# The index finger's rotations of a pose.
func _pose_of(pose: HandPose) -> Dictionary:
	var found := {}
	for bone in BONES:
		found[bone] = pose.rotations[bone]
	return found


func _way_depth(keys: Array[Dictionary]) -> float:
	var deepest := -INF
	for leg in keys.size() - 1:
		var depth := _leg_depth(keys[leg], keys[leg + 1])
		_say("  leg %d: %.2f mm" % [leg, depth * 1e3])
		deepest = maxf(deepest, depth)
	return deepest


# The deepest the finger goes on the straight way from `from` to `to`, as the game blends it.
func _leg_depth(from: Dictionary, to: Dictionary) -> float:
	var deepest := -INF
	for step in SAMPLES + 1:
		deepest = maxf(deepest, _depth(_between(from, to, float(step) / SAMPLES)))
	return deepest


func _between(from: Dictionary, to: Dictionary, share: float) -> Dictionary:
	var found := {}
	for bone in BONES:
		found[bone] = (from[bone] as Quaternion).slerp(to[bone], share)
	return found


# How deep the finger posed `rotations` goes into the rifle, in metres (below 0: that far off it).
func _depth(rotations: Dictionary) -> float:
	_stage.contact.pose_chain(rotations)
	var parts := _stage.contact.measure_parts("r", PARTS)
	var deepest := -INF
	for part in PARTS:
		deepest = maxf(deepest, -float(parts[part]))
	return deepest
