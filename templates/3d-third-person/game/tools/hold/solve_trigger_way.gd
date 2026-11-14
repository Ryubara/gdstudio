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

const Files := preload("res://tools/hold/finger_way_files.gd")
const OUT := "res://gameplay/weapon/hold/rifle_trigger_way.tres"
const FIT := "res://gameplay/weapon/hold/rifle_fit_%s.tres"
const DEFAULT_BODY := Files.DEFAULT_BODY
const BONES := Files.BONES
const PARTS := Files.PARTS
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


# Checks the way in `path` (the planner's output, the poses between the two ends) and writes it
# when no step of it goes deeper than `LIMIT`.
func _write(body: String, path: String, grip: Dictionary, trigger: Dictionary) -> int:
	var between := Files.read_way(path)
	if between.is_empty():
		return ERR_PARSE_ERROR
	var keys: Array[Dictionary] = [grip]
	keys.append_array(between)
	keys.append(trigger)
	var deepest := _way_depth(keys)
	_say("%d poses between; the deepest %.2f mm" % [between.size(), deepest * 1e3])
	if deepest > LIMIT:
		printerr("no way within %.1f mm; nothing written" % (LIMIT * 1e3))
		return FAILED
	var written := Files.save_way(between, body, OUT, FIT)
	_say("wrote %s: %d poses (error %d)" % [written[0], between.size(), written[1]])
	return written[1]


# What the planner needs, as JSON (`finger_way_files.gd`), with the rifle's triangles.
func _dump(path: String, grip: Dictionary, trigger: Dictionary, held: TwoHandHold) -> int:
	var contact := _stage.contact
	var to_weapon := (
		(_stage.rifle.get_node(^"Near") as Node3D).global_transform.affine_inverse()
		* _stage.skeleton.global_transform
	)
	var way: Array[Dictionary] = []
	if held.trigger_way != null:
		for pose in held.trigger_way.poses:
			way.append(_pose_of(pose))
	var out := Files.finger(contact, _stage.skeleton, to_weapon, grip, trigger, way)
	out["triangles"] = Files.flat(contact._gun.points)
	out["limit"] = LIMIT
	var error := Files.save_dump(out, path)
	_say("wrote %s (error %d)" % [path, error])
	return error


# The index finger's rotations of a pose.
func _pose_of(pose: HandPose) -> Dictionary:
	return Files.pose_of(pose)


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
