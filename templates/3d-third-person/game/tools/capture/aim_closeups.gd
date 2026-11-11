## Close-ups of the hands while the player's aim comes up and goes down (kit #1078): the game's own
## `player.tscn` on a floor, the aim action pressed and released, filmed from the gun's left on
## every frame. The body is between the carry pose and the aim pose for nine frames each way, the
## gun still out to the side, and the left arm too short for its place: this is where a hand that
## stops short of the gun shows.
##
## `gds godot -- --path game --fixed-fps 60 --write-movie <folder>/aim.png --resolution 1000x800
## res://tools/capture/aim_closeups.tscn` (`CLOSEUP_MODEL=male` for the male mannequin). With
## Movie Maker at 60 a frame is a physics tick: frame `WARM_UP` is the press, the aim is up nine
## frames later, and it is released at `WARM_UP + HELD`. It prints an `AIM` line a frame (the
## hold's aim weight and how far the left arm backed the hand off). It lives in tools/, which the
## export leaves out.
extends Node3D

## Frames before the aim is pressed, while it is held and after it is released.
const WARM_UP := 20
const HELD := 20
const AFTER := 16
## Where the camera is from the right hand, in the character's space (+Z its front, +X its left):
## `CLOSEUP_VIEW` picks one (`left` when it is not set).
const VIEWS: Dictionary = {
	"left": Vector3(0.6, 0.1, 0.3),
	"below": Vector3(0.25, -0.6, 0.3),
	"front": Vector3(0.2, 0.1, 0.8),
}

var _frame := -1
var _player: Player
var _camera: Camera3D


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
	if OS.get_environment("CLOSEUP_MODEL") == "male":
		var old := _player.model.rig()
		_player.model.remove_child(old)
		old.free()
		_player.model.add_child((load(HoldStage.MODELS["male"]) as PackedScene).instantiate())
	_camera = Camera3D.new()
	_camera.fov = 34.0
	_camera.near = 0.3
	# The body is drawn between two physics ticks; a camera that was too would trail the hand.
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_camera)
	_camera.make_current()


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame == WARM_UP:
		Input.action_press(&"aim")
	elif _frame == WARM_UP + HELD:
		Input.action_release(&"aim")
	elif _frame >= WARM_UP + HELD + AFTER:
		get_tree().quit()


func _process(_delta: float) -> void:
	var skeleton := _player.model.skeleton()
	if skeleton == null:
		return
	# The camera follows the hand as the modifiers leave it in this frame, where it is drawn: read
	# in `_process` the pose is the frame before's, and the hand moves centimetres a frame.
	if not skeleton.skeleton_updated.is_connected(_follow):
		skeleton.skeleton_updated.connect(_follow.bind(skeleton))
	var hold := _player.get_node_or_null(^"WeaponHold")
	if hold != null:
		var backed := 0.0
		if hold.has_method(&"support_backed"):
			backed = hold.call(&"support_backed")
		print("AIM %d aim %.2f backed %.1f mm" % [_frame, hold.get(&"aim_weight"), backed * 1e3])


func _follow(skeleton: Skeleton3D) -> void:
	var hand := (
		skeleton.get_global_transform_interpolated()
		* skeleton.get_bone_global_pose(skeleton.find_bone(&"hand_r"))
	)
	var model_basis := _player.model.get_global_transform_interpolated().basis.orthonormalized()
	var view: Vector3 = VIEWS.get(OS.get_environment("CLOSEUP_VIEW"), VIEWS["left"])
	_camera.global_position = hand.origin + model_basis * view
	_camera.look_at(hand.origin + model_basis * Vector3(0.05, 0.0, 0.1), Vector3.UP)
