## Plays the variants of GDStudio's own starts and stops of one gait for review (kit #1156): a
## body per variant in a row, each standing in the shipped idle, starting, going on in the
## shipped gait, stopping and standing again, as the clips join in the game.
##
## The clips are in place and their travel is a curve in `clips.json`, so each body stands on a
## strip of floor that moves under it by what its clip travels (0.25 m squares): a foot that
## slides is seen sliding, and a run that covers 15 m stays in the picture, which the template's
## map is too small for. The first pass steps off with the left foot and stops on the left, seen
## from behind and above as the game's camera sees a character; the second does both on the
## right foot, seen from the side.
##
## Record it with Movie Maker through the kit, in a game made from the template:
## `gds capture frames --project game --seconds 14 --fps 30
## --scene res://tools/capture/own_moves_review.tscn`
## `OWN_GAIT=<Walk|Jog|Sprint>` picks the gait (default `Walk`). `OWN_LETTERS=A,C` keeps only
## those variants. `OWN_SHIPPED=1` plays the shipped clips (`gds/Idle_To_Walk_L`) on one body
## instead of the review files' variants.
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

const OWN := "res://assets/animation/own/locomotion.glb"
const RECORDS := "res://assets/animation/own/locomotion.json"
const REVIEW := "res://assets/animation/own/review/%s"
const SPACING := 1.5
## Seconds a body stands before it starts and after it has stopped, and the least it spends in
## the gait between the two.
const STAND := 0.8
const REST := 1.0
const GAIT_LEAST := 1.0
## Where the camera stands from the middle of the row for each pass (the bodies face +Z).
const VIEWS: Array[Vector3] = [Vector3(1.6, 2.0, -4.6), Vector3(-6.2, 1.3, 0.6)]
const GRID := """
shader_type spatial;
uniform float travel = 0.0;
varying vec3 world;
void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 cell = abs(fract(vec2(world.x, world.z + travel) / 0.25) - 0.5);
	float line = step(0.46, max(cell.x, cell.y));
	float metre = step(0.49, abs(fract(world.z + travel) - 0.5));
	ALBEDO = mix(vec3(0.36, 0.38, 0.41), vec3(0.17, 0.18, 0.2), max(line, metre));
	ROUGHNESS = 0.95;
}
"""

var _gait := "Walk"
var _cycle := {}
## A lane per variant: its player, its floor's material and, per pass, its timeline.
var _lanes: Array[Dictionary] = []
var _camera: Camera3D
var _label: Label
var _clock := 0.0
var _pass := 0


func _ready() -> void:
	var gait := OS.get_environment("OWN_GAIT")
	_gait = gait if gait != "" else _gait
	var shipped := OS.get_environment("OWN_SHIPPED") != ""
	var keep := OS.get_environment("OWN_LETTERS")
	var records: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RECORDS)).clips
	_cycle = records[_gait]
	var start_type := "idle_to_%s" % _gait.to_lower()
	var stop_type := "%s_stop" % _gait.to_lower()
	var letters: Array[String] = [""]
	var starts := {}
	var stops := {}
	var libraries := {}
	if not shipped:
		starts = _read_records(REVIEW % (start_type + ".json"))
		stops = _read_records(REVIEW % (stop_type + ".json"))
		libraries = {
			&"start": _read_review(REVIEW % (start_type + ".glb")),
			&"stop": _read_review(REVIEW % (stop_type + ".glb")),
		}
		letters.clear()
		for clip: String in starts:
			var letter := clip.get_slice("_", clip.get_slice_count("_") - 1)
			if not letters.has(letter) and (keep == "" or keep.split(",").has(letter)):
				letters.append(letter)
	_stage()
	for i in letters.size():
		var lane := _lane(i, letters.size(), letters[i], libraries)
		for foot: String in ["L", "R"]:
			var start := "Idle_To_%s_%s" % [_gait, foot]
			var stop := "%s_Stop_%s" % [_gait, foot]
			if shipped:
				lane.passes.append(
					_timeline("gds/" + start, records[start], "gds/" + stop, records[stop])
				)
			else:
				start += "_" + letters[i]
				stop += "_" + letters[i]
				lane.passes.append(
					_timeline("start/" + start, starts[start], "stop/" + stop, stops[stop])
				)
		_lanes.append(lane)


func _physics_process(delta: float) -> void:
	_clock += delta
	var longest := 0.0
	for lane in _lanes:
		longest = maxf(longest, _play(lane, lane.passes[_pass], _clock))
	var foot := "left" if _pass == 0 else "right"
	var view := "from behind, as the game sees them" if _pass == 0 else "from the side"
	_label.text = "%s: start and stop on the %s foot, %s" % [_gait, foot, view]
	_camera.position = VIEWS[_pass]
	_camera.look_at(Vector3(0.0, 0.95, 0.4))
	if _clock >= longest:
		_clock = 0.0
		_pass += 1
		if _pass >= 2:
			set_physics_process(false)
			get_tree().quit()


# The steps of one pass for one lane: `[clip, from (s), length (s), record or null]`, the travel
# of each coming from its record's curve, or from the gait's speed.
func _timeline(
	start: String, start_record: Dictionary, stop: String, stop_record: Dictionary
) -> Array:
	var cycle: float = _cycle.seconds
	var enters: float = start_record.joins.last_frame / 30.0
	var leaves: float = stop_record.joins.first_frame / 30.0
	var gait := fposmod(leaves - enters, cycle)
	while gait < GAIT_LEAST:
		gait += cycle
	return [
		["gds/Idle", 0.0, STAND, null],
		[start, 0.0, start_record.seconds, start_record],
		["gds/" + _gait, enters, gait, null],
		[stop, 0.0, stop_record.seconds, stop_record],
		["gds/Idle", 0.0, REST, null],
	]


# Poses a lane at a time of its pass and moves its floor; returns the pass's length.
func _play(lane: Dictionary, steps: Array, at: float) -> float:
	var player: AnimationPlayer = lane.player
	var travelled := 0.0
	var begins := 0.0
	var posed := false
	for step: Array in steps:
		var clip: String = step[0]
		var length: float = step[2]
		var inside := clampf(at - begins, 0.0, length)
		var record: Variant = step[3]
		if record != null:
			travelled += _travel(record, inside * 30.0)
		elif clip != "gds/Idle":
			travelled += float(_cycle.speed) * inside
		if not posed and (at < begins + length or step == steps[-1]):
			var animation := player.get_animation(clip)
			var time: float = step[1] + inside
			if animation.loop_mode != Animation.LOOP_NONE:
				time = fposmod(time, animation.length)
			player.play(clip)
			player.seek(minf(time, animation.length), true)
			player.pause()
			lane.plate.text = "%s\n%s" % [lane.name, clip.get_slice("/", 1)]
			posed = true
		begins += length
	(lane.floor as ShaderMaterial).set_shader_parameter(&"travel", travelled)
	return begins


# Metres a clip's root has travelled at a frame, from the travel curve of its record.
func _travel(record: Dictionary, frame: float) -> float:
	var curve: Array = record.travel
	for i in range(curve.size() - 1):
		var a: Array = curve[i]
		var b: Array = curve[i + 1]
		if frame <= b[0]:
			return lerpf(a[1], b[1], clampf((frame - a[0]) / maxf(b[0] - a[0], 1.0), 0.0, 1.0))
	return curve[-1][1]


func _lane(i: int, count: int, letter: String, libraries: Dictionary) -> Dictionary:
	var at := Vector3((i - 0.5 * (count - 1)) * -SPACING, 0.0, 0.0)
	var body: Node3D = (load(CharacterBodies.FEMALE) as PackedScene).instantiate()
	add_child(body)
	body.position = at
	var player := AnimationPlayer.new()
	add_child(player)
	player.root_node = player.get_path_to(body)
	player.add_animation_library(&"gds", load(OWN))
	for library: StringName in libraries:
		player.add_animation_library(library, libraries[library])
	var strip := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(SPACING - 0.1, 60.0)
	strip.mesh = plane
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = GRID
	material.shader = shader
	strip.material_override = material
	strip.position = at
	add_child(strip)
	var plate := Label3D.new()
	plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plate.font_size = 30
	plate.pixel_size = 0.004
	plate.no_depth_test = true
	plate.position = at + Vector3(0.0, 2.05, 0.0)
	add_child(plate)
	var names := {"A": "A, grounded", "B": "B, loose", "C": "C, sharp", "": "shipped"}
	return {
		"player": player,
		"floor": material,
		"plate": plate,
		"name": names.get(letter, letter),
		"passes": []
	}


func _stage() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -140.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.55, 0.58, 0.62)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.77, 0.8)
	environment.ambient_light_energy = 0.7
	world.environment = environment
	add_child(world)
	_camera = Camera3D.new()
	_camera.fov = 60.0
	add_child(_camera)
	_camera.make_current()
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(40, 30)
	_label.add_theme_font_size_override(&"font_size", 34)
	layer.add_child(_label)


func _read_records(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path)).clips


# Reads a clip file the game does not import (`own_clips_review.gd` does the same).
func _read_review(path: String) -> AnimationLibrary:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(ProjectSettings.globalize_path(path), state)
	assert(error == OK, "cannot read %s" % path)
	var scene := document.generate_scene(state, 30.0)
	var source: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
	var library := AnimationLibrary.new()
	for clip in source.get_animation_list():
		library.add_animation(clip, source.get_animation(clip).duplicate())
	scene.free()
	return library
