## Writes the pistol's slide rack into the project (kit #1081), one `SlideRack` a body: the left
## hand's way over the slide, its fingers closed on it and opened over it, the slide's travel and
## the shares of the rack clip, from the JSON file `assets/animation/pistol/build_pistol_rack.py`
## wrote with `--data`. The default body's (`female`, `CharacterBodies.FEMALE`) is
## `gameplay/weapon/hold/pistol_slide_rack.tres`; every other body's is
## `pistol_slide_rack_<body>.tres`, which the first lists in `fits`. No number is typed by hand:
## change the solver or the clip's build, run them and this again, then
## `tests/gameplay/test_pistol_rack.gd`.
##
## `<godot> --headless --path game -s res://tools/hold/write_slide_rack.gd -- <rack_clip.json>`
extends SceneTree

const RACK := "res://gameplay/weapon/hold/pistol_slide_rack.tres"
const FIT := "res://gameplay/weapon/hold/pistol_slide_rack_%s.tres"
## The body whose rack is the file every other body's is listed in.
const DEFAULT_BODY := "female"


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
	var bodies: Dictionary = data.bodies
	if not bodies.has(DEFAULT_BODY):
		printerr("write_slide_rack: the data has no rack for the body ", DEFAULT_BODY)
		quit(1)
		return
	var fits: Array[Resource] = []
	for body: String in bodies:
		if body == DEFAULT_BODY:
			continue
		if not CharacterBodies.BY_NAME.has(body):
			printerr("write_slide_rack: the body is one of ", CharacterBodies.BY_NAME.keys())
			quit(1)
			return
		var path := FIT % body
		_save(_rack(path, data, body, []), path)
		# Loaded again, so the default body's file refers to this one and does not hold a copy.
		fits.append(ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE))
	_save(_rack(RACK, data, DEFAULT_BODY, fits), RACK)
	quit()


# One body's rack, in the file at `path` when there is one already (its `uid` stays).
func _rack(path: String, data: Dictionary, body: String, fits: Array[Resource]) -> SlideRack:
	var rack := SlideRack.new()
	if ResourceLoader.exists(path):
		rack = load(path) as SlideRack
	var solved: Dictionary = data.bodies[body]
	rack.clip = StringName(data.clip)
	rack.body = CharacterBodies.BY_NAME[body].get_file()
	rack.hand = _place(solved.hand)
	var places: Array[Transform3D] = []
	for rows: Array in solved.places:
		places.append(_place(rows))
	rack.places = places
	rack.places_from = snappedf(data.places_from, 1e-5)
	rack.places_to = snappedf(data.places_to, 1e-5)
	rack.reach = _pair(data.reach)
	rack.away = _pair(data.away)
	rack.grip_pose = _pose(solved.grip)
	rack.open_pose = _pose(solved.open)
	rack.fingers_over = _pair(data.fingers_over)
	rack.fingers_away = _pair(data.fingers_away)
	rack.fingers_close = snappedf(data.fingers_close, 1e-4)
	rack.travel = _vector(data.travel, 1e-4)
	rack.elbow = _vector(data.elbow, 1e-3)
	rack.leave = _pair(data.leave)
	rack.grip = _pair(data.grip)
	rack.pull = _pair(data.pull)
	rack.release = _pair(data.release)
	rack.slam = snappedf(data.slam, 1e-4)
	rack.back = _pair(data.back)
	rack.fits = fits
	return rack


func _save(rack: SlideRack, path: String) -> void:
	var error := ResourceSaver.save(rack, path)
	print("wrote ", path, " (", error, ")")


# A hand's finger bones (name to x, y, z, w) as a pose.
func _pose(bones: Dictionary) -> HandPose:
	var pose := HandPose.new()
	var names := bones.keys()
	names.sort()
	for bone: String in names:
		var q: Array = bones[bone]
		pose.rotations[StringName(bone)] = Quaternion(
			snappedf(q[0], 1e-5), snappedf(q[1], 1e-5), snappedf(q[2], 1e-5), snappedf(q[3], 1e-5)
		)
	return pose


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
