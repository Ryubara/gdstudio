## Films the rifle's trigger finger on its way from along the receiver to the trigger (kit #1283):
## both bodies posed by hand with the rifle (`RifleStage`, the idle clip), the rifle brought up a
## `STEPS`th at a time and down again, each body from the rifle's right side and from under its
## right, close on the trigger guard, with how far up the rifle is and how deep the index finger is
## in it (`HandContact`, below 0 off it) on each view. With `-- <share>` it holds that share of the
## way up (a still).
##
## Record it with Movie Maker through the kit (the frames land where `--write-movie` says):
## `gds godot -- --path game --resolution 1280x720 --write-movie <folder>/f.png --fixed-fps 10
## --quit-after 90 res://tools/capture/rifle_trigger_way.tscn`
## It prints a `WAY` line a step and body. It lives in tools/, which the export leaves out, and
## nothing in the game refers to it.
extends Node3D

const MODELS: Array[String] = ["female", "male"]
const PARTS: Array[String] = ["index_base", "index_mid", "index_tip"]
## The views: the name and where the camera is from the trigger, in the rifle's space (the muzzle
## along -X, up +Y, its left +Z).
const VIEWS: Array[Array] = [
	["from the right", Vector3(0.0, 0.0, -0.32)],
	["from under its right", Vector3(0.04, -0.22, -0.22)],
]
## The steps of the way up; the rifle goes up through them and down again.
const STEPS := 20
## How far apart the figures stand, in metres.
const SPACING := 40.0

var _stages: Array[RifleStage] = []
var _cameras: Array[Camera3D] = []
var _labels: Array[Label] = []
var _titles: Array[String] = []


func _ready() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40.0, -60.0, 0.0)
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.72, 0.82, 0.92)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	add_child(environment)
	var layer := CanvasLayer.new()
	add_child(layer)
	var grid := GridContainer.new()
	grid.columns = VIEWS.size()
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid.add_theme_constant_override(&"h_separation", 2)
	grid.add_theme_constant_override(&"v_separation", 2)
	layer.add_child(grid)
	for model in MODELS:
		var holder := Node3D.new()
		holder.position = Vector3(SPACING * _stages.size(), 0.0, 0.0)
		add_child(holder)
		_stages.append(RifleStage.make_rifle(holder, model))
		for view: Array in VIEWS:
			_add_view(grid, "%s, %s" % [model, view[0]])
	_run.call_deferred()


func _add_view(grid: GridContainer, title: String) -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_child(container)
	var port := SubViewport.new()
	port.world_3d = get_viewport().world_3d
	container.add_child(port)
	var camera := Camera3D.new()
	camera.fov = 30.0
	camera.near = 0.02
	port.add_child(camera)
	_cameras.append(camera)
	var label := Label.new()
	label.position = Vector2(8.0, 4.0)
	label.add_theme_font_size_override(&"font_size", 16)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 5)
	container.add_child(label)
	_labels.append(label)
	_titles.append(title)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and args[0].is_valid_float():
		while true:
			await _show(clampf(args[0].to_float(), 0.0, 1.0))
	while true:
		for step in range(0, STEPS + 1) + range(STEPS - 1, 0, -1):
			await _show(float(step) / STEPS)


# Poses both figures `share` of the way up, waits for their modifiers, measures the index finger
# and aims the cameras at the trigger.
func _show(share: float) -> void:
	for stage in _stages:
		stage.pose_rifle(CharacterClips.IDLE, 0.0, share)
	for stage in _stages:
		await stage.settle()
	for index in _stages.size():
		var stage := _stages[index]
		var parts := stage.contact.measure("r")
		var deepest := -INF
		for part in PARTS:
			deepest = maxf(deepest, -float(parts[part].distance))
		print("WAY %s %.2f %.2f mm" % [MODELS[index], share, deepest * 1e3])
		var trigger := stage.rifle.find_child("Trigger", true, false) as Node3D
		var axes := stage.rifle.global_basis.orthonormalized()
		var at := trigger.global_position
		for view in VIEWS.size():
			var cell := index * VIEWS.size() + view
			var camera := _cameras[cell]
			camera.global_position = at + axes * (VIEWS[view][1] as Vector3)
			camera.look_at(at, axes.y)
			_labels[cell].text = (
				"%s\n%.2f of the way up, index finger %.1f mm in"
				% [_titles[cell], share, deepest * 1e3]
			)
