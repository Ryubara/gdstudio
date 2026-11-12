## Writes the solved pistol hold into the project (kit #1001): the eight `HandPose` files of
## `gameplay/weapon/hold/`, `assets/weapons/pistol/pistol_held.tscn` (the pistol's seat on
## `hand_r`, the `SupportHand` and `MagazineHand` markers) and the left hand's way off the pistol
## in `gameplay/weapon/hold/weapon_hold.tscn` (`support_way`), from the JSON file
## `solve_pistol_hold.py` wrote. No number of the hold is typed into those files: change the model
## or the solver, run both again, then the test `tests/gameplay/test_pistol_hold.gd`.
##
## The finger poses set by hand (kit #1084, `tools/hold/pistol_authored.json`, read by
## `authored_pose.gd`) are laid over the solved ones here, on the body's own skeleton, so a new
## solve keeps them: a finger the file names takes its angles, in the pose it names. The thumb's
## pose between (`thumb_way`) exists only there.
##
## Each body has its own hold (kit #1187). The default body's (`female`, `CharacterBodies.FEMALE`)
## goes into the files above; another body's into one `HoldFit` file,
## `gameplay/weapon/hold/pistol_fit_<body>.tres`, which `weapon_hold.tscn` lists in `fits`.
##
## `<godot> --headless --path game -s res://tools/hold/write_hold.gd -- <hold.json> [female|male]`
extends SceneTree

const Authored := preload("res://tools/hold/authored_pose.gd")
const POSES: Dictionary[String, String] = {
	"grip": "res://gameplay/weapon/hold/pistol_grip_pose.tres",
	"trigger": "res://gameplay/weapon/hold/pistol_trigger_pose.tres",
	"trigger_way": "res://gameplay/weapon/hold/pistol_trigger_way_pose.tres",
	"thumb": "res://gameplay/weapon/hold/pistol_thumb_pose.tres",
	"thumb_way": "res://gameplay/weapon/hold/pistol_thumb_way_pose.tres",
	"support": "res://gameplay/weapon/hold/pistol_support_pose.tres",
	"magazine": "res://gameplay/weapon/hold/pistol_magazine_pose.tres",
	"open": "res://gameplay/weapon/hold/pistol_open_pose.tres",
}
const HELD := "res://assets/weapons/pistol/pistol_held.tscn"
const HOLD := "res://gameplay/weapon/hold/weapon_hold.tscn"
## The body whose hold is the scene's own; every other body's is a `HoldFit` file.
const DEFAULT_BODY := "female"
const FIT := "res://gameplay/weapon/hold/pistol_fit_%s.tres"
## The line of the hold scene the way is written after when the scene has none yet.
const _WAY_AFTER := "open_pose = "


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var parsed: Variant = null
	var body := arguments[1] if arguments.size() == 2 else DEFAULT_BODY
	if not CharacterBodies.BY_NAME.has(body):
		printerr("write_hold: the body is one of ", CharacterBodies.BY_NAME.keys())
		quit(1)
		return
	if arguments.size() in [1, 2] and FileAccess.file_exists(arguments[0]):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(arguments[0]))
	if not parsed is Dictionary:
		# A path relative to another folder reads as nothing: stop here instead of hanging.
		printerr("write_hold: give the solved hold as one absolute path to a JSON file")
		quit(1)
		return
	var solved: Dictionary = parsed
	_lay_authored(solved, body)
	if body != DEFAULT_BODY:
		_write_fit(solved, body)
		quit()
		return
	for key: String in POSES:
		if not solved.has(key):
			continue
		var pose := HandPose.new()
		if ResourceLoader.exists(POSES[key]):
			pose = load(POSES[key]) as HandPose
		_fill(pose, solved, key)
		var error := ResourceSaver.save(pose, POSES[key])
		print("wrote ", POSES[key], " (", error, ")")
	var places := {"Pistol": _text(solved.seat)}
	if solved.has("support_hand"):
		places["SupportHand"] = _text(solved.support_hand)
	if solved.has("magazine_hand"):
		places["MagazineHand"] = _text(solved.magazine_hand)
	var lines := FileAccess.get_file_as_string(HELD).split("\n")
	var node := ""
	for index in lines.size():
		if lines[index].begins_with('[node name="'):
			node = lines[index].get_slice('"', 1)
		elif lines[index].begins_with("transform = ") and places.has(node):
			lines[index] = "transform = " + places[node]
	var file := FileAccess.open(HELD, FileAccess.WRITE)
	file.store_string("\n".join(lines))
	file.close()
	print("wrote ", HELD)
	if solved.has("way"):
		_write_way(solved.way)
	quit()


# Lays the finger poses set by hand for `body` over the solved ones: each bone they name takes
# their rotation, worked out on the body's own skeleton.
func _lay_authored(solved: Dictionary, body: String) -> void:
	var rig := (load(CharacterBodies.BY_NAME[body]) as PackedScene).instantiate()
	var skeleton := rig.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var authored := Authored.poses(skeleton, body)
	for key: String in authored:
		if not solved.has(key):
			solved[key] = {}
		for bone: StringName in authored[key]:
			var turned: Quaternion = authored[key][bone]
			solved[key][String(bone)] = [turned.x, turned.y, turned.z, turned.w]
		print("laid the authored ", key, " pose over the solved one (", body, ")")
	rig.free()


# Writes another body's hold as one `HoldFit` file, its poses inside it.
func _write_fit(solved: Dictionary, body: String) -> void:
	var path := FIT % body
	var fit := HoldFit.new()
	fit.body = CharacterBodies.BY_NAME[body].get_file()
	fit.seat = _transform(solved.seat)
	if solved.has("support_hand"):
		fit.support_hand = _transform(solved.support_hand)
	if solved.has("magazine_hand"):
		fit.magazine_hand = _transform(solved.magazine_hand)
	if solved.has("way"):
		fit.support_way = Vector3(
			snappedf(solved.way[0], 1e-5),
			snappedf(solved.way[1], 1e-5),
			snappedf(solved.way[2], 1e-5)
		)
	for key: String in POSES:
		if solved.has(key):
			var pose := HandPose.new()
			_fill(pose, solved, key)
			fit.set(key + "_pose", pose)
	var error := ResourceSaver.save(fit, path)
	print("wrote ", path, " (", error, ")")


# Puts the solved rotations of `key` (and, for the grip, the wrist's turn) on `pose`.
func _fill(pose: HandPose, solved: Dictionary, key: String) -> void:
	var rotations: Dictionary[StringName, Quaternion] = {}
	for bone: String in solved.get(key, {}):
		rotations[StringName(bone)] = _quaternion(solved[key][bone])
	pose.rotations = rotations
	var turns: Dictionary[StringName, Quaternion] = {}
	if key == "grip" and solved.has("wrist"):
		turns[&"hand_r"] = _quaternion(solved.wrist)
	pose.turns = turns


func _quaternion(q: Array) -> Quaternion:
	return Quaternion(
		snappedf(q[0], 1e-5), snappedf(q[1], 1e-5), snappedf(q[2], 1e-5), snappedf(q[3], 1e-5)
	)


# A 4 x 4 matrix (rows) as a Transform3D, rounded as `_text` writes one.
func _transform(rows: Array) -> Transform3D:
	var columns: Array[Vector3] = []
	for column in 3:
		columns.append(
			Vector3(
				snappedf(rows[0][column], 1e-5),
				snappedf(rows[1][column], 1e-5),
				snappedf(rows[2][column], 1e-5)
			)
		)
	return Transform3D(
		Basis(columns[0], columns[1], columns[2]),
		Vector3(snappedf(rows[0][3], 1e-5), snappedf(rows[1][3], 1e-5), snappedf(rows[2][3], 1e-5))
	)


# Puts the left hand's way off the pistol on the hold scene's root: its `support_way` line is
# replaced, or added after the open pose's when the scene still has the script's default.
func _write_way(way: Array) -> void:
	var numbers := PackedStringArray()
	for value: float in way:
		numbers.append(_number(value, 1e-5))
	var line := "support_way = Vector3(%s)" % ", ".join(numbers)
	var lines := FileAccess.get_file_as_string(HOLD).split("\n")
	var at := -1
	for index in lines.size():
		if lines[index].begins_with("support_way = "):
			at = index
	if at >= 0:
		lines[at] = line
	else:
		for index in lines.size():
			if lines[index].begins_with(_WAY_AFTER):
				lines.insert(index + 1, line)
				at = index + 1
				break
	if at < 0:
		printerr("write_hold: no place for support_way in ", HOLD)
		return
	var file := FileAccess.open(HOLD, FileAccess.WRITE)
	file.store_string("\n".join(lines))
	file.close()
	print("wrote ", HOLD)


# A 4 x 4 matrix (rows) as a scene file writes a Transform3D: the basis by rows, then the origin.
func _text(rows: Array) -> String:
	var numbers := PackedStringArray()
	for row in 3:
		for column in 3:
			numbers.append(_number(rows[row][column], 1e-5))
	for row in 3:
		numbers.append(_number(rows[row][3], 1e-5))
	return "Transform3D(%s)" % ", ".join(numbers)


func _number(value: float, step: float) -> String:
	var rounded := snappedf(value, step)
	return "0" if is_zero_approx(rounded) else String.num(rounded, 5)
