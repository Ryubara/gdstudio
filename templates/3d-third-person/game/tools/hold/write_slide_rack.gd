## Writes the pistol's slide rack into the project (kit #1081):
## `gameplay/weapon/hold/pistol_slide_rack.tres` (a `SlideRack`: the left hand's way over the
## slide, the slide's travel and the shares of the rack clip), from the JSON file
## `assets/animation/pistol/build_pistol_rack.py` wrote with `--data`. No number is typed by hand:
## change the clip's build, run it and this again, then `tests/gameplay/test_pistol_rack.gd`.
##
## `<godot> --headless --path game -s res://tools/hold/write_slide_rack.gd -- <rack_clip.json>`
extends SceneTree

const RACK := "res://gameplay/weapon/hold/pistol_slide_rack.tres"


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var parsed: Variant = null
	if arguments.size() == 1 and FileAccess.file_exists(arguments[0]):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(arguments[0]))
	if not parsed is Dictionary:
		# A path relative to another folder reads as nothing: stop here instead of hanging.
		printerr("write_slide_rack: give the clip's data as one absolute path to a JSON file")
		quit(1)
		return
	var data: Dictionary = parsed
	var rack := SlideRack.new()
	if ResourceLoader.exists(RACK):
		rack = load(RACK) as SlideRack
	rack.clip = StringName(data.clip)
	rack.hand = _place(data.hand)
	var places: Array[Transform3D] = []
	for rows: Array in data.places:
		places.append(_place(rows))
	rack.places = places
	rack.places_from = snappedf(data.places_from, 1e-5)
	rack.places_to = snappedf(data.places_to, 1e-5)
	rack.reach = _pair(data.reach)
	rack.away = _pair(data.away)
	rack.travel = _vector(data.travel, 1e-4)
	rack.elbow = _vector(data.elbow, 1e-3)
	rack.leave = _pair(data.leave)
	rack.grip = _pair(data.grip)
	rack.pull = _pair(data.pull)
	rack.release = _pair(data.release)
	rack.slam = snappedf(data.slam, 1e-4)
	rack.back = _pair(data.back)
	var error := ResourceSaver.save(rack, RACK)
	print("wrote ", RACK, " (", error, ")")
	quit()


# A 4 x 4 matrix (rows) as a place.
func _place(rows: Array) -> Transform3D:
	var basis := Basis(
		_vector([rows[0][0], rows[1][0], rows[2][0]], 1e-5),
		_vector([rows[0][1], rows[1][1], rows[2][1]], 1e-5),
		_vector([rows[0][2], rows[1][2], rows[2][2]], 1e-5)
	)
	return Transform3D(basis, _vector([rows[0][3], rows[1][3], rows[2][3]], 1e-5))


func _vector(numbers: Array, step: float) -> Vector3:
	return Vector3(
		snappedf(numbers[0], step), snappedf(numbers[1], step), snappedf(numbers[2], step)
	)


func _pair(numbers: Array) -> Vector2:
	return Vector2(snappedf(numbers[0], 1e-4), snappedf(numbers[1], 1e-4))
