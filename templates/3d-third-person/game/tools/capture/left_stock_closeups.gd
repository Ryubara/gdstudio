## Close-ups of the rifle's stock at the left shoulder on a left peek lean (gdstudio #1484): the
## game's own `player.tscn` on a floor holds the rifle, aims ahead and leans left, then the camera
## goes round the left shoulder, holding each view for `VIEW_FRAMES` frames: the upper body from the
## front, the shoulder from the front, the left, above, behind and below. `CLOSEUP_BODY=male` wears
## the prototype male, `CLOSEUP_CROUCH=1` crouches.
##
## `gds godot -- --path game --fixed-fps 60 --write-movie <folder>/stock.png --resolution 1000x800
## res://tools/capture/left_stock_closeups.tscn`. It prints a `VIEW <name> <frame>` line as each
## view starts (the view's last frame is the still to keep); `test_peek_left_stock.gd` measures the
## stock. It lives in tools/, which the export leaves out.
extends Node3D

## Frames before the aim is pressed, until the lean, and until the first view.
const AIM_AT := 70
const LEAN_AT := 90
const VIEWS_AT := 140
## Frames each view is held.
const VIEW_FRAMES := 6
## Where the camera is from the left shoulder, in the character's space (+Z its front, +X its
## left), and its field of view.
const VIEWS: Array[Dictionary] = [
	{"name": "body", "at": Vector3(-0.2, -0.25, 2.2), "fov": 40.0},
	{"name": "front", "at": Vector3(0.15, 0.0, 1.0), "fov": 30.0},
	{"name": "left", "at": Vector3(1.0, 0.05, 0.15), "fov": 30.0},
	{"name": "above", "at": Vector3(0.1, 1.0, 0.1), "fov": 30.0},
	{"name": "behind", "at": Vector3(0.6, 0.3, -0.75), "fov": 30.0},
	{"name": "below", "at": Vector3(0.3, -0.85, 0.4), "fov": 30.0},
]

var _frame := -1
var _player: Player
var _camera: Camera3D
var _view := -1


func _ready() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 150.0, 0.0)
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.36, 0.39, 0.44)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	environment.environment.ambient_light_energy = 0.8
	add_child(environment)
	var arena := PlayArena.new()
	add_child(arena)
	_player = arena.add_player(Vector3.ZERO)
	if OS.get_environment("CLOSEUP_BODY") == "male":
		var slot := _player.model
		var old := slot.rig()
		slot.remove_child(old)
		old.free()
		slot.add_child((load(CharacterBodies.MALE) as PackedScene).instantiate())
	_player.loadout.give(load("res://gameplay/weapon/rifle.tres") as WeaponDef, 60)
	CommandDriver.take(_player)
	_camera = Camera3D.new()
	_camera.near = 0.03
	# The body is drawn between two physics ticks; a camera that was too would trail the shoulder.
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_camera)
	_camera.make_current()


func _physics_process(_delta: float) -> void:
	_frame += 1
	# Stepped by commands, as a server steps it: the moving camera is no view for the body to
	# turn to.
	var command := PlayerCommand.new()
	var ahead := CommandCodec.direction_angles(Vector3.FORWARD)
	command.yaw = ahead.x
	command.pitch = ahead.y
	command.aim = _frame >= AIM_AT
	command.crouch = OS.get_environment("CLOSEUP_CROUCH") == "1"
	command.lean_left = _frame >= LEAN_AT
	_player.step(command, CommandDriver.tick_seconds())
	if _frame >= VIEWS_AT + VIEWS.size() * VIEW_FRAMES:
		get_tree().quit()
	var view := floori(float(_frame - VIEWS_AT) / VIEW_FRAMES) if _frame >= VIEWS_AT else -1
	if view != _view and view >= 0 and view < VIEWS.size():
		_view = view
		print("VIEW %s %d" % [VIEWS[view]["name"], _frame])


func _process(_delta: float) -> void:
	var skeleton := _player.model.skeleton()
	if skeleton != null and not skeleton.skeleton_updated.is_connected(_follow):
		# The camera follows the shoulder as the modifiers leave it in this frame, where it is
		# drawn.
		skeleton.skeleton_updated.connect(_follow.bind(skeleton))


func _follow(skeleton: Skeleton3D) -> void:
	var xf := skeleton.get_global_transform_interpolated()
	var shoulder := xf * skeleton.get_bone_global_pose(skeleton.find_bone(&"upperarm_l")).origin
	var model_basis := _player.model.get_global_transform_interpolated().basis.orthonormalized()
	var view: Dictionary = VIEWS[clampi(_view, 0, VIEWS.size() - 1)]
	_camera.fov = view["fov"]
	_camera.global_position = shoulder + model_basis * (view["at"] as Vector3)
	var up := model_basis.z if view["name"] in ["above", "below"] else Vector3.UP
	_camera.look_at(shoulder, up)
