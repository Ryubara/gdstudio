## Close-ups of both hands on the weapon in a peek lean (gdstudio #1435): the game's own
## `player.tscn` on a floor aims ahead and leans (left by default), then the camera goes round the
## hands, holding each view for `VIEW_FRAMES` frames: the whole upper body from the front, then the
## hands from the front, the left, the right, above and below. On a left lean the rifle is on the
## left shoulder and the pistol across at the left eye; with `LEFT_SHOULDER=0` the tuning's
## `left_shoulder` is off, as before (the weapon right of the head).
##
## `gds godot -- --path game --fixed-fps 60 --write-movie <folder>/hands.png --resolution 1000x800
## res://tools/capture/left_shoulder_closeups.tscn` with `CLOSEUP_WEAPON=pistol|rifle` and
## `CLOSEUP_SIDE=left|right`. It prints a `VIEW <name> <frame>` line as each view starts (the view's
## last frame is the still to keep) and a `HANDS` line a view (each hand's distance from its place
## on the weapon, mm). It lives in tools/, which the export leaves out.
extends Node3D

## Frames before the aim is pressed, until the lean, and until the first view.
const AIM_AT := 70
const LEAN_AT := 90
const VIEWS_AT := 130
## Frames each view is held.
const VIEW_FRAMES := 6
## Where the camera is from the middle of the hands, in the character's space (+Z its front, +X its
## left), and its field of view.
const VIEWS: Array[Dictionary] = [
	{"name": "body", "at": Vector3(0.0, 0.05, 2.4), "fov": 40.0},
	{"name": "front", "at": Vector3(0.05, 0.05, 0.85), "fov": 34.0},
	{"name": "left", "at": Vector3(0.75, 0.05, 0.05), "fov": 34.0},
	{"name": "right", "at": Vector3(-0.75, 0.05, 0.05), "fov": 34.0},
	{"name": "above", "at": Vector3(0.05, 0.75, -0.05), "fov": 34.0},
	{"name": "below", "at": Vector3(0.1, -0.7, 0.3), "fov": 34.0},
]

var _frame := -1
var _player: Player
var _camera: Camera3D
var _view := -1
var _report := false


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
	if OS.get_environment("LEFT_SHOULDER") == "0":
		_player.peek_tuning = _player.peek_tuning.duplicate()
		_player.peek_tuning.left_shoulder = false
	if OS.get_environment("CLOSEUP_WEAPON") == "rifle":
		_player.loadout.give(load("res://gameplay/weapon/rifle.tres") as WeaponDef, 60)
	CommandDriver.take(_player)
	_camera = Camera3D.new()
	_camera.near = 0.05
	# The body is drawn between two physics ticks; a camera that was too would trail the hand.
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
	var right := OS.get_environment("CLOSEUP_SIDE") == "right"
	command.lean_right = right and _frame >= LEAN_AT
	command.lean_left = not right and _frame >= LEAN_AT
	_player.step(command, CommandDriver.tick_seconds())
	if _frame >= VIEWS_AT + VIEWS.size() * VIEW_FRAMES:
		get_tree().quit()
	var view := floori(float(_frame - VIEWS_AT) / VIEW_FRAMES) if _frame >= VIEWS_AT else -1
	if view != _view and view >= 0 and view < VIEWS.size():
		_view = view
		print("VIEW %s %d" % [VIEWS[view]["name"], _frame])
		_report = true


func _process(_delta: float) -> void:
	var skeleton := _player.model.skeleton()
	if skeleton != null and not skeleton.skeleton_updated.is_connected(_follow):
		# The camera follows the hands as the modifiers leave them in this frame, where they are
		# drawn.
		skeleton.skeleton_updated.connect(_follow.bind(skeleton))


func _follow(skeleton: Skeleton3D) -> void:
	var xf := skeleton.get_global_transform_interpolated()
	var right := xf * skeleton.get_bone_global_pose(skeleton.find_bone(&"hand_r")).origin
	var left := xf * skeleton.get_bone_global_pose(skeleton.find_bone(&"hand_l")).origin
	var middle := (right + left) * 0.5
	var model_basis := _player.model.get_global_transform_interpolated().basis.orthonormalized()
	var view: Dictionary = VIEWS[clampi(_view, 0, VIEWS.size() - 1)]
	_camera.fov = view["fov"]
	_camera.global_position = middle + model_basis * (view["at"] as Vector3)
	var up := model_basis.z if view["name"] in ["above", "below"] else Vector3.UP
	_camera.look_at(middle, up)
	if _report:
		_report = false
		_print_hands()


func _print_hands() -> void:
	var skeleton := _player.model.skeleton()
	var right_place: Vector3
	var left_place: Vector3
	var rifle := _player.model.get_node_or_null(^"RifleHeld")
	if _player.weapon.definition.display_name == "Rifle" and rifle != null:
		right_place = (rifle.find_child("RightHandTarget", true, false) as Node3D).global_position
		left_place = (rifle.find_child("LeftHandTarget", true, false) as Node3D).global_position
	else:
		var seat := _player.model.get_node(^"PistolHeld") as Node3D
		right_place = seat.global_position
		left_place = (seat.get_node(^"Pistol/SupportHand") as Node3D).global_position
	var xf := skeleton.global_transform
	var right := xf * skeleton.get_bone_global_pose(skeleton.find_bone(&"hand_r")).origin
	var left := xf * skeleton.get_bone_global_pose(skeleton.find_bone(&"hand_l")).origin
	print(
		(
			"HANDS lean %.2f right %.1f mm left %.1f mm muzzle %s"
			% [
				_player.peek_motion.amount,
				right.distance_to(right_place) * 1e3,
				left.distance_to(left_place) * 1e3,
				_player.weapon.muzzle.global_position
			]
		)
	)
