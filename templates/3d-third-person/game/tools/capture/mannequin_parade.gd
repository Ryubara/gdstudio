## Films the prototype mannequins of one look (kit #1149) playing the Universal Animation
## Library's clips in step on the prototype grid, drawn here with 0.25 m cells and a heavier
## line every metre: the male, the female and the chibi side by side. The chibi plays them
## through the same rig, its hips' keys scaled by the skeleton's `motion_scale`.
##
## Environment variables choose what is filmed:
## `PARADE_LOOK` `form`, `joint` or `facet`; `PARADE_VIEW` `front`, `quarter`, `side` or `close`
## (the male's forearm and hands from near: a hand roll that drives the twist bones, then the
## pistol clips and a reach, the camera following the hands);
## `PARADE_CLIP` one clip looped for whole cycles, in place of the programme (`ual1/Walk`);
## `PARADE_REFERENCE` `1` adds the Quaternius male on the left.
##
## Record it with Movie Maker through the kit; the scene prints its length (`PARADE seconds`)
## and quits at its end:
## `gds capture frames --project game --seconds 20 --fps 30 --scene
## res://tools/capture/mannequin_parade.tscn`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node3D

const LIBRARIES := {
	&"ual1": "res://assets/animation/universal/ual1.glb",
	&"ual2": "res://assets/animation/universal/ual2.glb",
}
const REFERENCE := "res://assets/characters/mannequin/mannequin_male.glb"
const FOLDER := "res://assets/characters/prototype/"
const FLOOR := "res://assets/materials/prototype/prototype_floor.tres"
const BODIES: Array[String] = ["male", "female", "chibi"]
## The grid under the bodies: metres a cell, and cells between heavier lines.
const CELL := 0.25
const MAJOR_EVERY := 4.0
## The clips and how long each plays (s); 0 plays the clip once to its end. A third number lifts
## the bodies along an arc that high (m, times each body's `motion_scale`) while the step plays:
## the clips are in place and the game moves the character, so here the scene does.
const PROGRAMME := [
	[&"ual1/Idle", 2.5],
	[&"ual1/Walk", 3.2],
	[&"ual1/Jog_Fwd", 2.8],
	[&"ual1/Sprint", 2.6],
	[&"ual1/Crouch_Fwd", 3.2],
	[&"ual1/Idle", 0.8],
	[&"ual1/Jump_Start", 0.0],
	[&"ual1/Jump", 0.9, 0.4],
	[&"ual1/Jump_Land", 0.0],
	[&"ual1/Idle", 1.5],
]
## The close view's steps: clip (empty: the hand roll), seconds, the bones the camera frames,
## and the side it stands on (1 the body's left, -1 its right).
const CLOSE_PROGRAMME := [
	[&"", 5.0, ["lowerarm_l", "hand_l", "middle_02_l"], 1.0],
	[&"ual1/Pistol_Aim_Neutral", 2.5, ["hand_l", "hand_r"], 1.0],
	[&"ual1/Pistol_Reload", 0.0, ["hand_l", "hand_r"], 1.0],
	[&"ual1/Pistol_Aim_Neutral", 1.0, ["hand_l", "hand_r"], 1.0],
	[&"ual1/Interact", 0.0, ["lowerarm_l", "hand_l", "middle_02_l"], 1.0],
	[&"ual1/Push", 2.667, ["hand_l", "hand_r"], 1.0],
]
## Metres between bodies: the programme's jump spreads the arms, a looped gait does not.
const SPACING := 1.6
const LOOP_SPACING := 1.25
## A looped clip plays whole cycles for at least this long (s).
const LOOP_SECONDS := 3.0
## The hand roll of the close view: degrees each way, and seconds a cycle.
const ROLL := 80.0
const ROLL_PERIOD := 2.5
const VIEWS := {"front": 0.0, "quarter": 35.0, "side": 90.0, "close": 0.0}
const INK := Color(0.1, 0.1, 0.12)

var _models: Array[Node3D] = []
var _players: Array[AnimationPlayer] = []
var _skeletons: Array[Skeleton3D] = []
var _programme: Array = []
var _clock := 0.0
var _step := -1
var _next := 0.0
var _began := 0.0
var _lift := 0.0
var _rolling := false
var _close := false
var _caption: Label
var _camera: Camera3D
var _framed: Array = []
var _side := 1.0
var _aim := Vector3.ZERO
var _from := Vector3.ZERO
var _aimed := false


func _ready() -> void:
	var look := _setting("PARADE_LOOK", "form")
	var view := _setting("PARADE_VIEW", "front")
	var looped := OS.get_environment("PARADE_CLIP")
	_close = view == "close"
	var paths: Array[String] = []
	if OS.get_environment("PARADE_REFERENCE") == "1":
		paths.append(REFERENCE)
	for body in BODIES:
		if not _close or body == "male":
			paths.append("%s%s_%s.glb" % [FOLDER, look, body])
	var spacing := SPACING if looped == "" else LOOP_SPACING
	_stage(spacing * (paths.size() - 1) + (2.0 if looped == "" else 1.5))
	for i in paths.size():
		var model: Node3D = (load(paths[i]) as PackedScene).instantiate()
		model.position = Vector3((i - (paths.size() - 1) / 2.0) * spacing, 0.0, 0.0)
		model.rotation_degrees.y = VIEWS[view]
		add_child(model)
		_models.append(model)
		var player := AnimationPlayer.new()
		model.add_child(player)
		for library: StringName in LIBRARIES:
			player.add_animation_library(library, load(LIBRARIES[library]))
		_players.append(player)
		_skeletons.append(model.find_children("*", "Skeleton3D", true, false)[0])
		if not _close:
			# On the floor in front, clear of a jump; over the head in the nearer view of a loop.
			var above := Vector3(0.0, 1.98, 0.0) if looped != "" else Vector3(0.0, 0.0, 1.0)
			_label(paths[i].get_file().get_basename(), model.position + above)
	if looped != "":
		var length := _players[0].get_animation(looped).length
		_programme = [[StringName(looped), ceilf(LOOP_SECONDS / length) * length]]
	else:
		_programme = CLOSE_PROGRAMME if _close else PROGRAMME
	var total := 0.0
	for step: Array in _programme:
		total += (
			step[1]
			if step[1] > 0.0 or step[0] == &""
			else _players[0].get_animation(step[0]).length
		)
	print("PARADE seconds %.3f" % total)
	_advance()
	if _close:
		_follow(0.0)


func _process(delta: float) -> void:
	_clock += delta
	if _clock >= _next:
		_advance()
	if _rolling:
		_roll_hands()
	var along := clampf((_clock - _began) / maxf(_next - _began, 0.001), 0.0, 1.0)
	for i in _models.size():
		_models[i].position.y = _lift * _skeletons[i].motion_scale * 4.0 * along * (1.0 - along)
	if _close:
		_follow.call_deferred(delta)


func _advance() -> void:
	_step += 1
	if _step >= _programme.size():
		get_tree().quit()
		return
	var clip: StringName = _programme[_step][0]
	var seconds: float = _programme[_step][1]
	_began = _next
	_lift = _programme[_step][2] if not _close and _programme[_step].size() > 2 else 0.0
	if _close:
		_framed = _programme[_step][2]
		_side = _programme[_step][3]
	_rolling = clip == &""
	if _rolling:
		_caption.text = "hand roll, %d degrees each way (rest pose)" % int(ROLL)
		_next += seconds
		return
	_next += seconds if seconds > 0.0 else _players[0].get_animation(clip).length
	_caption.text = String(clip)
	for player in _players:
		player.play(clip, 0.0 if _programme.size() == 1 else 0.15)


## Rolls both hands about the forearm's length on the rest pose; `MannequinTwist` gives the
## forearm's twist bone the roll.
func _roll_hands() -> void:
	var angle := deg_to_rad(ROLL) * sin(_clock * TAU / ROLL_PERIOD)
	for skeleton in _skeletons:
		for bone_name: String in ["hand_l", "hand_r"]:
			var bone := skeleton.find_bone(bone_name)
			var rest := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
			skeleton.set_bone_pose_rotation(bone, Quaternion(Vector3.UP, angle) * rest)


## Keeps the close camera on the middle of the framed bones, further back the wider they spread.
func _follow(delta: float) -> void:
	var skeleton := _skeletons[0]
	var low := Vector3.INF
	var high := -Vector3.INF
	for bone_name: String in _framed:
		var at := (
			skeleton.global_transform
			* skeleton.get_bone_global_pose(skeleton.find_bone(bone_name)).origin
		)
		low = low.min(at)
		high = high.max(at)
	var goal := (low + high) / 2.0
	var from := (
		goal + Vector3(0.55 * _side, 0.3, 0.8).normalized() * (0.5 + (high - low).length() * 0.8)
	)
	var weight := 1.0 if not _aimed else 1.0 - exp(-4.0 * delta)
	_aim = _aim.lerp(goal, weight)
	_from = _from.lerp(from, weight)
	_aimed = true
	_camera.look_at_from_position(_from, _aim)


func _setting(variable: String, fallback: String) -> String:
	var value := OS.get_environment(variable)
	return fallback if value == "" else value


func _label(text: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.pixel_size = 0.003
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.95, 0.96, 0.98)
	label.outline_modulate = INK
	label.outline_size = 10
	add_child(label)


## The floor, the light, the camera (framing `span` metres across the bodies) and the caption.
func _stage(span: float) -> void:
	RenderingServer.global_shader_parameter_set(&"prototype_cell_size", CELL)
	RenderingServer.global_shader_parameter_set(&"prototype_major_every", MAJOR_EVERY)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(16.0, 10.0)
	plane.material = load(FLOOR)
	floor_mesh.mesh = plane
	add_child(floor_mesh)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 32.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.74, 0.77, 0.8)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.8, 0.82, 0.86)
	environment.ambient_light_energy = 0.7
	world.environment = environment
	add_child(world)
	_camera = Camera3D.new()
	add_child(_camera)
	if _close:
		_camera.fov = 36.0
		_camera.near = 0.02
	else:
		# A 30 degree lens on a 16:9 frame shows 0.953 m across for each metre of distance.
		_camera.fov = 30.0
		var distance := maxf(span / 0.953, 4.6)
		_camera.look_at_from_position(Vector3(0.0, 1.45, distance), Vector3(0.0, 1.02, 0.0))
	_camera.make_current()
	var layer := CanvasLayer.new()
	add_child(layer)
	_caption = Label.new()
	_caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_caption.offset_top = 4.0
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 44)
	_caption.add_theme_color_override("font_color", INK)
	_caption.add_theme_color_override("font_outline_color", Color(0.9, 0.92, 0.94))
	_caption.add_theme_constant_override("outline_size", 10)
	layer.add_child(_caption)
