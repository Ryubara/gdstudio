## Films the prototype mannequins of one look (kit #1149) beside the Quaternius mannequin, all
## playing the same Universal Animation Library clips in step: idle, walk, jog, sprint, crouch
## walk, pistol aim and a roll. The chibi body plays them through the same rig, its hips' keys
## scaled by the skeleton's `motion_scale`.
##
## Record it with Movie Maker through the kit, once a look (the `PARADE_LOOK` environment variable
## is `form`, `joint` or `facet`; `PARADE_VIEW` is `front` or `side`):
## `gds capture frames --project game --seconds 13 --scene
## res://tools/capture/mannequin_parade.tscn`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node3D

const LIBRARIES := {
	&"ual1": "res://assets/animation/universal/ual1.glb",
	&"ual2": "res://assets/animation/universal/ual2.glb",
}
const REFERENCE := "res://assets/characters/mannequin/mannequin_male.glb"
const FOLDER := "res://assets/characters/prototype/"
const BODIES: Array[String] = ["male", "female", "chibi"]
## The clips and how long each plays (s).
const PROGRAMME := [
	[&"ual1/Idle", 1.2],
	[&"ual1/Walk", 2.4],
	[&"ual1/Jog_Fwd", 2.0],
	[&"ual1/Sprint", 1.6],
	[&"ual1/Crouch_Fwd", 2.0],
	[&"ual1/Pistol_Aim_Neutral", 1.4],
	[&"ual1/Roll", 1.6],
]
const SPACING := 1.25

var _players: Array[AnimationPlayer] = []
var _clock := 0.0
var _step := -1
var _next := 0.0
var _caption: Label3D


func _ready() -> void:
	var look := OS.get_environment("PARADE_LOOK")
	if look == "":
		look = "form"
	var side := OS.get_environment("PARADE_VIEW") == "side"
	var paths: Array[String] = [REFERENCE]
	for body in BODIES:
		paths.append("%s%s_%s.glb" % [FOLDER, look, body])
	_stage()
	for i in paths.size():
		var model: Node3D = (load(paths[i]) as PackedScene).instantiate()
		model.position = Vector3((i - (paths.size() - 1) / 2.0) * SPACING, 0.0, 0.0)
		model.rotation_degrees.y = 90.0 if side else 0.0
		add_child(model)
		var player := AnimationPlayer.new()
		model.add_child(player)
		for library: StringName in LIBRARIES:
			player.add_animation_library(library, load(LIBRARIES[library]))
		_players.append(player)
		var label := Label3D.new()
		label.text = paths[i].get_file().get_basename()
		label.position = model.position + Vector3(0.0, 2.0, 0.0)
		label.pixel_size = 0.003
		label.modulate = Color(0.1, 0.1, 0.12)
		label.outline_size = 0
		add_child(label)
	_caption = Label3D.new()
	_caption.position = Vector3(0.0, 2.3, 0.0)
	_caption.pixel_size = 0.004
	_caption.modulate = Color(0.1, 0.1, 0.12)
	_caption.outline_size = 0
	add_child(_caption)


func _process(delta: float) -> void:
	_clock += delta
	if _clock < _next:
		return
	_step += 1
	if _step >= PROGRAMME.size():
		get_tree().quit()
		return
	_next += PROGRAMME[_step][1]
	_caption.text = String(PROGRAMME[_step][0])
	for player in _players:
		player.play(PROGRAMME[_step][0], 0.15)


func _stage() -> void:
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14.0, 8.0)
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color(0.56, 0.58, 0.6)
	plane.material = ground
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
	var camera := Camera3D.new()
	camera.fov = 30.0
	camera.position = Vector3(0.0, 1.25, 8.6)
	camera.rotation_degrees.x = -2.0
	add_child(camera)
	camera.make_current()
