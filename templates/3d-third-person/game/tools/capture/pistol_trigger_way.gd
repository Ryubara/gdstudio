## Films the pistol's trigger finger on its way from along the frame to the trigger with both
## hands on the gun (kit #1272, kit #1480): both bodies on the hold suite's stage (`HoldStage`, the
## aimed pistol, the trigger finger taken along its way by the reload's weight as
## `test_pistol_trigger_way.gd` takes it), the finger brought onto the trigger a `STEPS`th at a
## time and off again, each body from the gun's right side, from under its right and from ahead
## of the guard, close on the trigger, with how far along the way the finger is and how deep it is
## in the gun (read through the part, `HandContact.measure_through`) and in the left hand on each
## view. With `-- <share>` it holds that share of the way (a still).
##
## Record it with Movie Maker through the kit (the frames land where `--write-movie` says):
## `gds godot -- --path game --resolution 1280x720 --write-movie <folder>/f.png --fixed-fps 10
## --quit-after 90 res://tools/capture/pistol_trigger_way.tscn`
## It prints a `WAY` line a step and body. It lives in tools/, which the export leaves out, and
## nothing in the game refers to it.
extends Node3D

const MODELS: Array[String] = ["female", "male"]
const PARTS: Array[String] = ["index_base", "index_mid", "index_tip"]
## The views: the name and where the camera is from the fingertip on the trigger, in the pistol's
## space (the muzzle along -X, up +Y, its left +Z).
const VIEWS: Array[Array] = [
	["from the right", Vector3(0.0, 0.0, -0.22)],
	["from under its right", Vector3(0.03, -0.15, -0.15)],
	["from ahead of the guard", Vector3(-0.16, -0.06, -0.1)],
]
## The pose of the aim, as the test measures it.
const AIM_TIME := 0.16
## The steps of the way; the finger goes onto the trigger through them and off again.
const STEPS := 20
## How far apart the figures stand, in metres.
const SPACING := 40.0

var _stages: Array[HoldStage] = []
var _focus: Array[Vector3] = []
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
		_stages.append(HoldStage.make(holder, model))
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
	# Where the fingertip is on the trigger, in each pistol's space: the cameras look there.
	await _pose(1.0)
	for stage in _stages:
		var tip := stage.skeleton.global_transform * stage.contact.bone_pose(&"index_03_r").origin
		_focus.append(stage.pistol.global_transform.affine_inverse() * tip)
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and args[0].is_valid_float():
		while true:
			await _show(clampf(args[0].to_float(), 0.0, 1.0))
	while true:
		for step in range(0, STEPS + 1) + range(STEPS - 1, 0, -1):
			await _show(float(step) / STEPS)


# Puts both figures in the aim with the trigger finger `share` of its way onto the trigger.
func _pose(share: float) -> void:
	for stage in _stages:
		stage.pose(CharacterClips.PISTOL_AIM, AIM_TIME, 1.0)
		stage.hold.set(&"reload_weight", 1.0 - share)
		stage.hold.call(&"refresh")
	for stage in _stages:
		await stage.settle()


# Poses both figures `share` of the way, measures the index finger against the gun and the left
# hand, and aims the cameras at the trigger.
func _show(share: float) -> void:
	await _pose(share)
	for index in _stages.size():
		var stage := _stages[index]
		var parts := stage.contact.measure_through("r", PARTS, stage.contact.hand_skin("l"))
		var deepest := Vector2(-INF, -INF)
		for part in PARTS:
			deepest.x = maxf(deepest.x, -(parts[part] as Vector2).x)
			deepest.y = maxf(deepest.y, -(parts[part] as Vector2).y)
		var mm := deepest * 1e3
		print("WAY %s %.2f gun %.2f mm hand %.2f mm" % [MODELS[index], share, mm.x, mm.y])
		var axes := stage.pistol.global_basis.orthonormalized()
		var at := stage.pistol.global_transform * _focus[index]
		for view in VIEWS.size():
			var cell := index * VIEWS.size() + view
			var camera := _cameras[cell]
			camera.global_position = at + axes * (VIEWS[view][1] as Vector3)
			camera.look_at(at, axes.y)
			_labels[cell].text = (
				"%s\n%.2f of the way, index finger %.1f mm in the gun, %.1f mm in the left hand"
				% [_titles[cell], share, deepest.x * 1e3, deepest.y * 1e3]
			)
