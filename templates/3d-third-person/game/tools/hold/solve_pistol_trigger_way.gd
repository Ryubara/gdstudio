## Writes the pistol's trigger finger's way from along the frame to the trigger, with both hands on
## the gun (kit #1272), as a `HandPoseWay`: the default body's (`female`) into
## `gameplay/weapon/hold/pistol_trigger_way.tres`, which `weapon_hold.tscn` names, another body's
## into its fit (`pistol_fit_<body>.tres`, `HoldFit.trigger_way`).
##
## The pistol solve (`solve_pistol_hold.py`) gives the finger one pose between, nearly straight
## and drawn out to its own side; swinging in from there the last bone crossed the trigger guard's
## front strut (kit #1212) or rubbed its inner face (kit #1273). A real trigger finger comes off
## the frame, bends its last two bones and drops them into the guard's open side, then onto the
## trigger.
##
## The way is planned by `plan_trigger_way.py`, the rifle's planner (kit #1283, kit #1480), on what
## this script dumps, and only checked and written here, measured as the tests measure it
## (`HandContact` on `HoldStage`, the aimed pistol with both hands on it): the index finger against
## the gun, its depth read through the part's thickness (`HandContact.measure_through`, so a finger
## that crosses a thin part reads its whole thickness, not the half its nearest face is away), and
## against the left hand as it holds. The dump carries both, and the planner measures the same:
##
##   1. `<godot> --headless --path game -s res://tools/hold/solve_pistol_trigger_way.gd -- <body>
##      --dump=<abs>/pistol_way_<body>.json`
##   2. `uv run --no-project --with numpy --with scipy python tools/hold/plan_trigger_way.py
##      <abs>/pistol_way_<body>.json <abs>/pistol_way_<body>_out.json`
##   3. `<godot> --headless --path game -s res://tools/hold/solve_pistol_trigger_way.gd -- <body>
##      --way=<abs>/pistol_way_<body>_out.json`
##
## Step 3 measures the whole way at every hundredth, as `test_pistol_trigger_way.gd` does, and
## writes nothing when any of them goes deeper than `LIMIT` into the gun or the left hand. With
## neither option it measures the way the body has now. `--report=<file>` writes what it prints to
## a file too.
##
## No number of the way is typed: change the gun, the seat or the poses, run `write_hold.gd`, then
## the three steps for each body, then `tests/gameplay/test_pistol_trigger_way.gd` and
## `test_pistol_hold.gd`. It lives in tools/, which the export leaves out.
extends SceneTree

const Files := preload("res://tools/hold/finger_way_files.gd")
const OUT := "res://gameplay/weapon/hold/pistol_trigger_way.tres"
const FIT := "res://gameplay/weapon/hold/pistol_fit_%s.tres"
const BONES := Files.BONES
const PARTS := Files.PARTS
## The pose of the aim the way is planned in, as the test measures it.
const AIM_TIME := 0.16
## The deepest any hundredth of the way may go into the gun or the left hand, in metres: the
## test's own room (`test_pistol_trigger_way.gd`, `TRIGGER_ROOM`).
const LIMIT := 0.001
## What the planner keeps each leg within, in metres (`plan_trigger_way.py --limit`, its default
## for this dump): under `LIMIT`, so the planner's grid and the blend between its steps leave room.
const PLAN_LIMIT := 0.0008
## The equal parts of the whole way it is checked at.
const CHECK_STEPS := 100
## The grid of poses the planner searches, degrees, each from, to and by: the knuckle's spread
## (Z), bend (X) and roll (Y), then the middle and last joints' bends (X). The spread and the
## knuckle's straightening reach 25 degrees each way off the gun (a person's index knuckle
## straightens 20 to 30 degrees past flat; the hold's own poses stop at 20 and 15, kit #1272), the
## roll stays within 20 (a finger has only a little of that turn).
const AXES := [
	[-25.0, 25.0, 2.5],
	[-25.0, 50.0, 3.0],
	[-20.0, 20.0, 5.0],
	[-5.0, 110.0, 3.0],
	[-5.0, 85.0, 3.0],
]

var _stage: HoldStage
var _other: HandContact.HandSkin
var _lines := PackedStringArray()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var body := Files.DEFAULT_BODY
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
		printerr("solve_pistol_trigger_way: a body ", HoldStage.MODELS.keys())
		quit(1)
		return
	_stage = HoldStage.make(root, body)
	await process_frame
	# The aimed pistol in both hands, the trigger finger along the frame (a reload's weight takes it
	# off the trigger, as the test does).
	_stage.pose(CharacterClips.PISTOL_AIM, AIM_TIME, 1.0)
	_stage.hold.set(&"reload_weight", 1.0)
	_stage.hold.call(&"refresh")
	await _stage.settle()
	_other = _stage.contact.hand_skin("l")
	var grip := Files.pose_of(_stage.hold.get(&"grip_pose"))
	var trigger := Files.pose_of(_stage.hold.get(&"trigger_pose"))
	var now: Array[Dictionary] = []
	var way: HandPoseWay = _stage.hold.get(&"trigger_way")
	if way != null:
		for pose in way.poses:
			now.append(Files.pose_of(pose))
	_say("body %s" % body)
	var code := OK
	if not dump.is_empty():
		code = _dump(dump, grip, trigger, now)
	elif not way_file.is_empty():
		code = _write(body, way_file, grip, trigger)
	else:
		_say("the way now, %d poses between:" % now.size())
		_sweep(_keys(grip, now, trigger))
	if not report.is_empty():
		var file := FileAccess.open(report, FileAccess.WRITE)
		file.store_string("\n".join(_lines) + "\n")
		file.close()
	_stage.free()
	quit(code)


func _say(line: String) -> void:
	print(line)
	_lines.append(line)


static func _keys(grip: Dictionary, between: Array[Dictionary], trigger: Dictionary) -> Array:
	var keys: Array[Dictionary] = [grip]
	keys.append_array(between)
	keys.append(trigger)
	return keys


# Checks the planner's way in `path` at every hundredth and writes it when none goes deeper than
# `LIMIT` into the gun or the left hand.
func _write(body: String, path: String, grip: Dictionary, trigger: Dictionary) -> int:
	var between := Files.read_way(path)
	if between.is_empty():
		return ERR_PARSE_ERROR
	_say("%d poses between:" % between.size())
	var deepest := _sweep(_keys(grip, between, trigger))
	if deepest.x > LIMIT or deepest.y > LIMIT:
		printerr("no way within %.1f mm; nothing written" % (LIMIT * 1e3))
		return FAILED
	var written := Files.save_way(between, body, OUT, FIT)
	_say("wrote %s: %d poses (error %d)" % [written[0], between.size(), written[1]])
	return written[1]


# What the planner needs (`finger_way_files.gd`), with the pistol's triangles, the left hand's
# skin as it holds (its closed pieces, in the gun's space), and the measure's rules: depth into
# the gun read through the part (`through`, `HandContact.CROSSING`), the grid searched and the
# planner's limit.
func _dump(path: String, grip: Dictionary, trigger: Dictionary, now: Array[Dictionary]) -> int:
	var contact := _stage.contact
	var to_weapon := (
		_stage.pistol.global_transform.affine_inverse() * _stage.skeleton.global_transform
	)
	var out := Files.finger(contact, _stage.skeleton, to_weapon, grip, trigger, now)
	out["triangles"] = Files.flat(contact._gun.points)
	out["other"] = Files.flat(_other.field.points, to_weapon)
	out["through"] = {"crossing": HandContact.CROSSING, "least": HandContact.CROSSING_LEAST}
	out["axes"] = AXES
	out["plan_limit"] = PLAN_LIMIT
	var error := Files.save_dump(out, path)
	_say("wrote %s (error %d)" % [path, error])
	return error


# Where the finger is `weight` of the way along, as `HandPoseModifier._on_the_way` puts it.
static func _on_the_way(poses: Array, weight: float) -> Dictionary:
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


# The deepest the way `keys` goes into the gun and the left hand at every hundredth; each
# hundredth deeper than `PLAN_LIMIT` is printed.
func _sweep(keys: Array) -> Vector2:
	var deepest := Vector2(-INF, -INF)
	var worst_at := Vector2.ZERO
	for step in CHECK_STEPS + 1:
		var weight := float(step) / CHECK_STEPS
		var depth := _depth(_on_the_way(keys, weight))
		if depth.x > deepest.x:
			deepest.x = depth.x
			worst_at.x = weight
		if depth.y > deepest.y:
			deepest.y = depth.y
			worst_at.y = weight
		if maxf(depth.x, depth.y) > PLAN_LIMIT:
			_say("  %.2f: gun %.2f mm, left hand %.2f mm" % [weight, depth.x * 1e3, depth.y * 1e3])
	_say(
		(
			"  deepest: gun %.2f mm at %.2f, left hand %.2f mm at %.2f"
			% [deepest.x * 1e3, worst_at.x, deepest.y * 1e3, worst_at.y]
		)
	)
	return deepest
