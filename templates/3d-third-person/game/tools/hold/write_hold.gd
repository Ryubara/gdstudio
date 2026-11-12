## Writes a solved hold into the project: the `HandPose` files of `gameplay/weapon/hold/` and the
## places of the weapon's scene, from the JSON file its solver wrote. The pistol's (kit #1001,
## `solve_pistol_hold.py`): five poses, `assets/weapons/pistol/pistol_held.tscn` (the pistol's
## seat on `hand_r`, the `SupportHand` and `MagazineHand` markers) and the left hand's way off the
## pistol in `gameplay/weapon/hold/weapon_hold.tscn` (`support_way`). The rifle's (kit #889,
## `solve_rifle_hold.py`, asked for with `rifle`): five poses and `gameplay/weapon/rifle_held.tscn`
## (where each hand's bone sits on the rifle: `RightHandTarget`, `LeftHandTarget`,
## `MagazineHand`). No number of a hold is typed by hand: change the model or the solver, run both
## again, then the hold's test (`tests/gameplay/test_pistol_hold.gd`, `test_rifle_hold.gd`).
##
## Each body has its own hold of each weapon (kit #1187). The default body's (`female`,
## `CharacterBodies.FEMALE`) goes into the files above; another body's into one `HoldFit` file,
## `gameplay/weapon/hold/<weapon>_fit_<body>.tres`, which the weapon's hold lists in `fits`
## (`weapon_hold.tscn` for the pistol, `rifle_held.tscn` for the rifle, whose fit's `seat` is the
## inverse of the right hand's place on the rifle).
##
## `<godot> --headless --path game -s res://tools/hold/write_hold.gd -- <hold.json> [rifle] [male]`
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
const HOLD := "res://gameplay/weapon/hold/weapon_hold.tscn"
## The body whose hold is the scene's own; every other body's is a `HoldFit` file.
const DEFAULT_BODY := "female"
const FIT := "res://gameplay/weapon/hold/%s_fit_%s.tres"
## The line of the hold scene the way is written after when the scene has none yet.
const _WAY_AFTER := "open_pose = "


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var parsed: Variant = null
	var which := "pistol"
	var body := DEFAULT_BODY
	for word: String in arguments.slice(1):
		if WEAPONS.has(word):
			which = word
		elif CharacterBodies.BY_NAME.has(word):
			body = word
		else:
			printerr("write_hold: after the file, a weapon ", WEAPONS.keys())
			printerr("  and a body ", CharacterBodies.BY_NAME.keys())
			quit(1)
			return
	if arguments.size() in [1, 2, 3] and FileAccess.file_exists(arguments[0]):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(arguments[0]))
	if not parsed is Dictionary:
		# A path relative to another folder reads as nothing: stop here instead of hanging.
		printerr("write_hold: give the solved hold as one absolute path to a JSON file")
		quit(1)
		return
	var solved: Dictionary = parsed
	if body != DEFAULT_BODY:
		_write_fit(solved, which, body)
		quit()
		return
	var weapon := WEAPONS[which]
	var poses: Dictionary = weapon.poses
	for key: String in poses:
		if not solved.has(key):
			continue
		var pose := HandPose.new()
		if ResourceLoader.exists(poses[key]):
			pose = load(poses[key]) as HandPose
		_fill(pose, solved, key)
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
	if solved.has("way"):
		_write_way(solved.way)
	quit()


# Writes another body's hold as one `HoldFit` file, its poses inside it.
func _write_fit(solved: Dictionary, which: String, body: String) -> void:
	var path := FIT % [which, body]
	var fit := HoldFit.new()
	fit.body = CharacterBodies.BY_NAME[body].get_file()
	if solved.has("seat"):
		fit.seat = _transform(solved.seat)
	elif solved.has("right_hand"):
		# The rifle's right hand is a place on the gun; the seat is the gun's place on the hand.
		fit.seat = _transform(solved.right_hand).affine_inverse()
	if solved.has("left_hand"):
		fit.support_hand = _transform(solved.left_hand)
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
	for key: String in WEAPONS[which].poses:
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
