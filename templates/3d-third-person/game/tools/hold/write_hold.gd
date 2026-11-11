## Writes a solved hold into the project: the `HandPose` files of `gameplay/weapon/hold/` and the
## places of the weapon's scene, from the JSON file its solver wrote. The pistol's (kit #1001,
## `solve_pistol_hold.py`): five poses and `assets/weapons/pistol/pistol_held.tscn` (the pistol's
## seat on `hand_r`, the `SupportHand` and `MagazineHand` markers). The rifle's (kit #889,
## `solve_rifle_hold.py`, asked for with `rifle` after the file): five poses and
## `gameplay/weapon/rifle_held.tscn` (where each hand's bone sits on the rifle:
## `RightHandTarget`, `LeftHandTarget`, `MagazineHand`). No number of a hold is typed by hand:
## change the model or the solver, run both again, then the hold's test
## (`tests/gameplay/test_pistol_hold.gd`, `tests/gameplay/test_rifle_hold.gd`).
##
## `<godot> --headless --path game -s res://tools/hold/write_hold.gd -- <hold.json> [rifle]`
extends SceneTree

## For each weapon: the pose file of each solved pose, the scene that holds the weapon, and which
## solved place each of the scene's nodes takes.
const WEAPONS: Dictionary[String, Dictionary] = {
	"pistol":
	{
		"poses":
		{
			"grip": "res://gameplay/weapon/hold/pistol_grip_pose.tres",
			"trigger": "res://gameplay/weapon/hold/pistol_trigger_pose.tres",
			"support": "res://gameplay/weapon/hold/pistol_support_pose.tres",
			"magazine": "res://gameplay/weapon/hold/pistol_magazine_pose.tres",
			"open": "res://gameplay/weapon/hold/pistol_open_pose.tres",
		},
		"held": "res://assets/weapons/pistol/pistol_held.tscn",
		"places":
		{"Pistol": "seat", "SupportHand": "support_hand", "MagazineHand": "magazine_hand"},
	},
	"rifle":
	{
		"poses":
		{
			"grip": "res://gameplay/weapon/hold/rifle_grip_pose.tres",
			"trigger": "res://gameplay/weapon/hold/rifle_trigger_pose.tres",
			"support": "res://gameplay/weapon/hold/rifle_support_pose.tres",
			"magazine": "res://gameplay/weapon/hold/rifle_magazine_pose.tres",
			"open": "res://gameplay/weapon/hold/rifle_open_pose.tres",
		},
		"held": "res://gameplay/weapon/rifle_held.tscn",
		"places":
		{
			"RightHandTarget": "right_hand",
			"LeftHandTarget": "left_hand",
			"MagazineHand": "magazine_hand",
		},
	},
}


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var parsed: Variant = null
	if arguments.size() >= 1 and FileAccess.file_exists(arguments[0]):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(arguments[0]))
	var which := arguments[1] if arguments.size() > 1 else "pistol"
	if not parsed is Dictionary or not WEAPONS.has(which):
		# A path relative to another folder reads as nothing: stop here instead of hanging.
		printerr("write_hold: give the solved hold as one absolute path to a JSON file [rifle]")
		quit(1)
		return
	var solved: Dictionary = parsed
	var weapon := WEAPONS[which]
	var poses: Dictionary = weapon.poses
	for key: String in poses:
		if not solved.has(key):
			continue
		var pose := HandPose.new()
		if ResourceLoader.exists(poses[key]):
			pose = load(poses[key]) as HandPose
		var rotations: Dictionary[StringName, Quaternion] = {}
		for bone: String in solved.get(key, {}):
			rotations[StringName(bone)] = _quaternion(solved[key][bone])
		pose.rotations = rotations
		var turns: Dictionary[StringName, Quaternion] = {}
		if key == "grip" and solved.has("wrist"):
			turns[&"hand_r"] = _quaternion(solved.wrist)
		pose.turns = turns
		var error := ResourceSaver.save(pose, poses[key])
		print("wrote ", poses[key], " (", error, ")")
	var places := {}
	for node_name: String in weapon.places:
		if solved.has(weapon.places[node_name]):
			places[node_name] = _text(solved[weapon.places[node_name]])
	var held: String = weapon.held
	var lines := FileAccess.get_file_as_string(held).split("\n")
	var node := ""
	for index in lines.size():
		if lines[index].begins_with('[node name="'):
			node = lines[index].get_slice('"', 1)
		elif lines[index].begins_with("transform = ") and places.has(node):
			lines[index] = "transform = " + places[node]
	var file := FileAccess.open(held, FileAccess.WRITE)
	file.store_string("\n".join(lines))
	file.close()
	print("wrote ", held)
	quit()


func _quaternion(q: Array) -> Quaternion:
	return Quaternion(
		snappedf(q[0], 1e-5), snappedf(q[1], 1e-5), snappedf(q[2], 1e-5), snappedf(q[3], 1e-5)
	)


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
