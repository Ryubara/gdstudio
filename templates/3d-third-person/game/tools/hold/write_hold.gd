## Writes the solved pistol hold into the project (kit #1001): the five `HandPose` files of
## `gameplay/weapon/hold/` and `assets/weapons/pistol/pistol_held.tscn` (the pistol's seat on
## `hand_r`, the `SupportHand` and `MagazineHand` markers), from the JSON file
## `solve_pistol_hold.py` wrote. No number of the hold is typed by hand: change the model or the
## solver, run both again, then the test `tests/gameplay/test_pistol_hold.gd`.
##
## `<godot> --headless --path game -s res://tools/hold/write_hold.gd -- <hold.json>`
extends SceneTree

const POSES: Dictionary[String, String] = {
	"grip": "res://gameplay/weapon/hold/pistol_grip_pose.tres",
	"trigger": "res://gameplay/weapon/hold/pistol_trigger_pose.tres",
	"support": "res://gameplay/weapon/hold/pistol_support_pose.tres",
	"magazine": "res://gameplay/weapon/hold/pistol_magazine_pose.tres",
	"open": "res://gameplay/weapon/hold/pistol_open_pose.tres",
}
const HELD := "res://assets/weapons/pistol/pistol_held.tscn"


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var parsed: Variant = null
	if arguments.size() == 1 and FileAccess.file_exists(arguments[0]):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(arguments[0]))
	if not parsed is Dictionary:
		# A path relative to another folder reads as nothing: stop here instead of hanging.
		printerr("write_hold: give the solved hold as one absolute path to a JSON file")
		quit(1)
		return
	var solved: Dictionary = parsed
	for key: String in POSES:
		if not solved.has(key):
			continue
		var pose := HandPose.new()
		if ResourceLoader.exists(POSES[key]):
			pose = load(POSES[key]) as HandPose
		var rotations: Dictionary[StringName, Quaternion] = {}
		for bone: String in solved.get(key, {}):
			var q: Array = solved[key][bone]
			rotations[StringName(bone)] = Quaternion(
				snappedf(q[0], 1e-5),
				snappedf(q[1], 1e-5),
				snappedf(q[2], 1e-5),
				snappedf(q[3], 1e-5)
			)
		pose.rotations = rotations
		var turns: Dictionary[StringName, Quaternion] = {}
		if key == "grip" and solved.has("wrist"):
			var w: Array = solved.wrist
			turns[&"hand_r"] = Quaternion(
				snappedf(w[0], 1e-5),
				snappedf(w[1], 1e-5),
				snappedf(w[2], 1e-5),
				snappedf(w[3], 1e-5)
			)
		pose.turns = turns
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
	quit()


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
