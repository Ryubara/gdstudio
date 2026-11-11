## Films the rifle's stock against the body (kit #1177): both mannequins posed by hand with the
## rifle (`RifleStage`), each pose from the body's right and from its front, in one frame of a
## grid, the pose's name and the stock's depth in the body on each view. The poses are the low
## ready and the aim in the idle, a sprint and a crouched walk. With `-- <pose>` (`stand`,
## `move`) it shows another set of poses.
##
## Record it with Movie Maker through the kit (the frames land where `--write-movie` says):
## `gds godot -- --path game --write-movie <folder>/f.png --fixed-fps 10 --quit-after 6
## res://tools/capture/rifle_stock.tscn`
## It prints a `STOCK` line a pose (`BodyClearance.deepest()`, the body part and the rifle's
## point). It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node3D

## The poses, one row each: the name, the clip, its time, how far the rifle is up (1 aimed).
const SETS: Dictionary[String, Array] = {
	"stand":
	[
		["idle, low ready", CharacterClips.IDLE, 0.0, 0.0],
		["idle, aimed", CharacterClips.IDLE, 0.0, 1.0],
		["sprint, low ready", CharacterClips.SPRINT, 0.0, 0.0],
		["crouched walk, aimed", CharacterClips.CROUCH_WALK, 0.0, 1.0],
	],
	"move":
	[
		["walk, low ready", CharacterClips.WALK, 0.3, 0.0],
		["jog, aimed", CharacterClips.RUN, 0.3, 1.0],
		["crouched, low ready", CharacterClips.CROUCH_IDLE, 0.0, 0.0],
		["crouched, aimed", CharacterClips.CROUCH_IDLE, 0.0, 1.0],
	],
}
const MODELS: Array[String] = ["female", "male"]
## The views: the name and where the camera is from the chest, in the body's space (+Z its
## front, +X its left).
const VIEWS: Array[Array] = [
	["right", Vector3(-1.3, 0.05, 0.25)],
	["front", Vector3(-0.25, 0.05, 1.3)],
]
## How far apart the figures stand, in metres.
const SPACING := 40.0
const FRAME := Vector2i(1920, 1080)

var _stages: Array[RifleStage] = []
var _clearances: Array[BodyClearance] = []
var _poses: Array = []
var _cameras: Array[Camera3D] = []
var _labels: Array[Label] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_poses = SETS[args[0]] if not args.is_empty() and SETS.has(args[0]) else SETS["stand"]
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
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
	grid.columns = MODELS.size() * VIEWS.size()
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid.add_theme_constant_override(&"h_separation", 2)
	grid.add_theme_constant_override(&"v_separation", 2)
	layer.add_child(grid)
	for row in _poses.size():
		for model in MODELS:
			var holder := Node3D.new()
			holder.position = Vector3(SPACING * _stages.size(), 0.0, 0.0)
			add_child(holder)
			var stage := RifleStage.make_rifle(holder, model)
			_stages.append(stage)
			_clearances.append(
				BodyClearance.new(stage.skeleton, stage.contact, stage.rifle.get_node(^"Near"))
			)
			for view: Array in VIEWS:
				_add_view(grid, "%s, %s, from the %s" % [model, _poses[row][0], view[0]])
	_show.call_deferred()


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
	label.text = title
	label.position = Vector2(8.0, 4.0)
	label.add_theme_font_size_override(&"font_size", 15)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 5)
	container.add_child(label)
	_labels.append(label)


# Poses every figure, waits for its modifiers, measures the stock and aims the cameras.
func _show() -> void:
	for index in _stages.size():
		var stage := _stages[index]
		var pose: Array = _poses[index / MODELS.size()]
		stage.pose_rifle(pose[1], pose[2], pose[3])
	for stage in _stages:
		await stage.settle()
	for index in _stages.size():
		var stage := _stages[index]
		var pose: Array = _poses[index / MODELS.size()]
		var found := _clearances[index].deepest(stage.rifle.get_node(^"Near"))
		var model := MODELS[index % MODELS.size()]
		print(
			(
				"STOCK %s %s: %.1f mm in %s at %s"
				% [model, pose[0], found.depth * 1e3, found.bone, found.point.snappedf(0.001)]
			)
		)
		var chest := stage.bone_origin(&"spine_03")
		var facing := stage.slot.global_basis.orthonormalized()
		for view in VIEWS.size():
			var cell := index * VIEWS.size() + view
			var camera := _cameras[cell]
			camera.global_position = chest + facing * (VIEWS[view][1] as Vector3)
			camera.look_at(chest + facing * Vector3(-0.08, 0.0, 0.15), Vector3.UP)
			_labels[cell].text += "\nstock %.0f mm in the body" % (found.depth * 1e3)
