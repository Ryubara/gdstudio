## Films the pistol held in one hand (kit #1085), or in two with `ONE_HAND=0`, from the game
## camera: the aim comes up, three shots, the look up and down the aim's range, a reload while
## aiming (the free hand comes in for it only) and the aim let go. It presses the input actions
## the way a player would, on a copy of the pistol's definition with `one_handed` set.
##
## `gds capture frames --project game --scene res://tools/capture/one_hand_tour.tscn --seconds 9
## --fps 30`, or `gds godot -- --path game --fixed-fps 60 --write-movie <folder>/f.png
## res://tools/capture/one_hand_tour.tscn`. `ONE_HAND_VIEW=side` films the body from its right,
## `front` from ahead and to the right, `hand` the shooting hand up close; `MODEL=male` holds it on
## the male mannequin. It prints a `KICK` line a physics tick: the hold's aim weight, the one-hand
## kick and the barrel's pitch in degrees, so the recoil of the two holds can be compared. It lives
## in tools/, which the export leaves out.
extends Node

const FLOOR_AT := Vector3(0.0, 300.0, 0.0)
const START := Vector3(0.0, 300.1, 0.0)
## Where the camera is from the shooting hand (`hand`) or the body (`side`, `front`), in the
## character's space (+Z its front, +X its left).
const VIEWS: Dictionary = {
	"hand": Vector3(-0.35, 0.12, 0.35),
	"side": Vector3(-3.2, 0.3, 0.6),
	"front": Vector3(-1.6, 0.2, 2.6),
}

## Each stage: `name`, `hold` the actions held, `seconds`, `pitch` the camera's pitch to turn to
## (degrees, positive looks down) and `taps`, actions pressed for 0.1 s at the listed seconds.
const STAGES: Array[Dictionary] = [
	{"name": "ready", "hold": [], "seconds": 0.6, "pitch": 6.0},
	{"name": "aim", "hold": [&"aim"], "seconds": 0.7, "pitch": 6.0},
	{
		"name": "shots",
		"hold": [&"aim"],
		"seconds": 1.6,
		"pitch": 6.0,
		"taps": {&"fire": [0.1, 0.6, 1.1]}
	},
	{"name": "look up", "hold": [&"aim"], "seconds": 1.0, "pitch": -35.0},
	{"name": "look down", "hold": [&"aim"], "seconds": 1.4, "pitch": 40.0},
	{"name": "level", "hold": [&"aim"], "seconds": 0.6, "pitch": 6.0},
	{"name": "reload", "hold": [&"aim"], "seconds": 2.3, "pitch": 6.0, "taps": {&"reload": [0.05]}},
	{"name": "let go", "hold": [], "seconds": 0.8, "pitch": 6.0},
]

var _index := -1
var _clock := 0.0
var _tick := 0
var _held: Array[StringName] = []
var _view: String = OS.get_environment("ONE_HAND_VIEW")
var _camera: Camera3D

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	var floor_block := (load("res://world/blocks/proto_block.tscn") as PackedScene).instantiate()
	floor_block.size = Vector3(40.0, 1.0, 40.0)
	floor_block.position = FLOOR_AT - Vector3(0.0, 0.5, 0.0)
	add_child(floor_block)
	if OS.get_environment("MODEL") == "male":
		var old := _player.model.rig()
		_player.model.remove_child(old)
		old.free()
		_player.model.add_child((load(HoldStage.MODELS["male"]) as PackedScene).instantiate())
	var pistol := _player.loadout.slots[0].duplicate() as WeaponDef
	pistol.one_handed = OS.get_environment("ONE_HAND") != "0"
	_player.loadout.slots[0] = pistol
	_player.weapon.definition = pistol
	_player.teleport(START, PI)
	if VIEWS.has(_view):
		_camera = Camera3D.new()
		_camera.fov = 30.0 if _view == "hand" else 40.0
		_camera.near = 0.05
		_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(_camera)
		_camera.make_current()


func _physics_process(delta: float) -> void:
	_tick += 1
	_report()
	if _index >= STAGES.size():
		return
	if _index < 0 or _clock >= float(STAGES[_index]["seconds"]):
		_index += 1
		_clock = 0.0
		if _index >= STAGES.size():
			_finish()
			return
		print("STAGE ", STAGES[_index]["name"])
	var stage := STAGES[_index]
	_rig.orbit(Vector2(-clampf(wrapf(-_rig.yaw, -180.0, 180.0), -6.0, 6.0), 0.0))
	_rig.orbit(Vector2(0.0, clampf(float(stage["pitch"]) - _rig.pitch, -2.5, 2.5)))
	_clock += delta
	var actions: Array[StringName] = []
	actions.append_array(stage["hold"])
	var taps: Dictionary = stage.get("taps", {})
	for action: StringName in taps:
		for at: float in taps[action]:
			if _clock >= at and _clock < at + 0.1:
				actions.append(action)
	_hold(actions)


func _process(_delta: float) -> void:
	if _camera == null:
		return
	var skeleton := _player.model.skeleton()
	if skeleton != null and not skeleton.skeleton_updated.is_connected(_follow):
		skeleton.skeleton_updated.connect(_follow.bind(skeleton))


# The camera follows the hand or the body as the modifiers leave them in this frame.
func _follow(skeleton: Skeleton3D) -> void:
	var model_basis := _player.model.get_global_transform_interpolated().basis.orthonormalized()
	var target := _player.model.get_global_transform_interpolated().origin + Vector3.UP * 1.3
	if _view == "hand":
		target = (
			(
				skeleton.get_global_transform_interpolated()
				* skeleton.get_bone_global_pose(skeleton.find_bone(&"hand_r"))
			)
			. origin
		)
	_camera.global_position = target + model_basis * (VIEWS[_view] as Vector3)
	_camera.look_at(target, Vector3.UP)


func _report() -> void:
	var hold := _player.get_node_or_null(^"WeaponHold") as WeaponHold
	var pistol := _player.get_node_or_null(^"Model/PistolHeld/Pistol") as Node3D
	if hold == null or pistol == null:
		return
	var barrel := (pistol.global_basis * Vector3.LEFT).normalized()
	print(
		(
			"KICK %d aim %.2f kick %.2f pitch %.1f"
			% [_tick, hold.aim_weight, hold.shot_kick, rad_to_deg(asin(barrel.y))]
		)
	)


func _finish() -> void:
	_hold([])
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()


func _hold(actions: Array[StringName]) -> void:
	for action in _held:
		if not actions.has(action):
			Input.action_release(action)
	_held.clear()
	for action in actions:
		Input.action_press(action)
		_held.append(action)
