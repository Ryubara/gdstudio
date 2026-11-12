## Films a character using a lever with each weapon in its hands (kit #1336), from the game
## camera with the HUD: the pistol carried and aimed, then the rifle at the low ready and aimed.
## It presses the input actions the way a player would, and the lever answers each pull.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --scene res://tools/capture/interact_held_tour.tscn
## --seconds 12 --fps 30`
## `INTERACT_VIEW=front|left|top` (or `-- front` after Godot's own arguments) films a close-up of
## the hands instead, from in front of the character, from its left or from above, drawn by a
## viewport of its own; `INTERACT_BODY=male` (a name of `CharacterBodies.BY_NAME`) dresses the
## player in that body, whose own fit of each hold is then filmed.
## It prints a `STAGE` line as each stage starts and a `FREE` line an update while a hand is let
## go. It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## A flat floor built high above the map, and where the character and the lever stand on it.
const FLOOR_AT := Vector3(0.0, 300.0, 0.0)
const START := Vector3(0.0, 300.1, 0.0)
const LEVER_AT := Vector3(-0.3, 300.0, -0.8)
const PITCH := 4.0
const RIFLE := "res://gameplay/weapon/rifle.tres"
## The camera's yaw for the stages filmed from the character's left, in degrees.
const SIDE_YAW := -70.0

## Each stage: `name`, `hold` the actions held, `seconds` how long, `taps`: actions pressed for
## 0.1 s at each of the listed seconds into the stage, `give`: the rifle is handed over, and
## `yaw`: where the camera orbits to (an aim turns the body to the camera, so those stay behind
## it; the others look from the character's left, where the reaching hand shows).
const STAGES: Array[Dictionary] = [
	{"name": "pistol", "hold": [], "seconds": 0.8, "yaw": SIDE_YAW},
	{
		"name": "pistol, use",
		"hold": [],
		"seconds": 1.4,
		"taps": {&"interact": [0.1]},
		"yaw": SIDE_YAW
	},
	{"name": "pistol, aim", "hold": [&"aim"], "seconds": 0.8},
	{"name": "pistol, aim, use", "hold": [&"aim"], "seconds": 1.5, "taps": {&"interact": [0.1]}},
	{"name": "rifle out", "hold": [], "seconds": 1.3, "give": true, "yaw": SIDE_YAW},
	{
		"name": "rifle, use",
		"hold": [],
		"seconds": 1.4,
		"taps": {&"interact": [0.1]},
		"yaw": SIDE_YAW
	},
	{"name": "rifle, aim", "hold": [&"aim"], "seconds": 0.8},
	{"name": "rifle, aim, use", "hold": [&"aim"], "seconds": 1.5, "taps": {&"interact": [0.1]}},
	{"name": "rifle", "hold": [], "seconds": 0.6},
]
## The close-up views: where the camera is from the chest, in the character's space (+Z its
## front, +X its left), and what it looks at from the chest.
const VIEWS: Dictionary = {
	"front": [Vector3(0.35, 0.05, 1.5), Vector3(0.05, -0.2, 0.3)],
	"left": [Vector3(1.3, 0.0, 0.5), Vector3(0.0, -0.2, 0.35)],
	"top": [Vector3(0.0, 1.3, 0.3), Vector3(0.0, 0.0, 0.3)],
}

var _index := -1
var _clock := 0.0
var _held: Array[StringName] = []
var _view := _view_asked()
var _close: Camera3D
var _handle: MeshInstance3D
var _pulls := 0
var _yaw := 0.0

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	var body := OS.get_environment("INTERACT_BODY")
	if CharacterBodies.BY_NAME.has(body):
		_player.model.variant = load(CharacterBodies.BY_NAME[body]) as PackedScene
	var floor_block := (load("res://world/blocks/proto_block.tscn") as PackedScene).instantiate()
	floor_block.size = Vector3(40.0, 1.0, 40.0)
	floor_block.position = FLOOR_AT - Vector3(0.0, 0.5, 0.0)
	add_child(floor_block)
	_add_lever()
	_player.teleport(START, PI)
	_player.interacted.connect(func(_target: Node3D) -> void: print("USED ", _pulls))
	if VIEWS.has(_view):
		# After the camera rig, which makes its own camera current again when the aim changes.
		process_priority = 1000
		# The close-up is drawn by a viewport of its own over the screen: the game aims along the
		# main viewport's camera, so a close-up made current there turned the character to it.
		var layer := CanvasLayer.new()
		layer.layer = 100
		add_child(layer)
		var container := SubViewportContainer.new()
		container.stretch = true
		container.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.add_child(container)
		var view := SubViewport.new()
		view.world_3d = get_viewport().world_3d
		container.add_child(view)
		_close = Camera3D.new()
		_close.fov = 40.0
		view.add_child(_close)


# The close-up view asked for: `INTERACT_VIEW` or a user argument after `--` (`-- front`).
static func _view_asked() -> String:
	for argument in OS.get_cmdline_user_args():
		if VIEWS.has(argument):
			return argument
	return OS.get_environment("INTERACT_VIEW")


# A lever as a person would build it: a post, a handle and an `Interactable` with a shape, a
# little to the character's left, where the interact clip's left hand reaches.
func _add_lever() -> void:
	var lever := Node3D.new()
	lever.name = "Lever"
	lever.position = LEVER_AT
	var post := MeshInstance3D.new()
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.2, 1.05, 0.2)
	post.mesh = post_mesh
	post.position.y = 0.525
	lever.add_child(post)
	_handle = MeshInstance3D.new()
	var handle_mesh := BoxMesh.new()
	handle_mesh.size = Vector3(0.06, 0.3, 0.06)
	_handle.mesh = handle_mesh
	_handle.position = Vector3(0.0, 1.15, 0.0)
	_handle.rotation.x = deg_to_rad(-30.0)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.9, 0.2, 0.15)
	_handle.material_override = paint
	lever.add_child(_handle)
	var usable := Interactable.new()
	usable.prompt = "Pull"
	usable.position.y = 1.0
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	usable.add_child(shape)
	lever.add_child(usable)
	usable.interacted.connect(_on_lever_pulled)
	_player.get_parent().add_child(lever)


func _on_lever_pulled(_by: Node3D) -> void:
	_pulls += 1
	var thrown := _pulls % 2 == 1
	_handle.rotation.x = deg_to_rad(30.0 if thrown else -30.0)
	var colour := Color(0.2, 0.85, 0.3) if thrown else Color(0.9, 0.2, 0.15)
	(_handle.material_override as StandardMaterial3D).albedo_color = colour


func _physics_process(delta: float) -> void:
	_rig.orbit(Vector2(-clampf(wrapf(_yaw - _rig.yaw, -180.0, 180.0), -6.0, 6.0), 0.0))
	_rig.orbit(Vector2(0.0, clampf(PITCH - _rig.pitch, -2.0, 2.0)))
	if _index >= STAGES.size():
		return
	if _index < 0 or _clock >= float(STAGES[_index]["seconds"]):
		_index += 1
		_clock = 0.0
		if _index >= STAGES.size():
			_finish()
			return
		print("STAGE ", STAGES[_index]["name"])
		_yaw = STAGES[_index].get("yaw", 0.0)
		if STAGES[_index].get("give", false):
			_player.loadout.give(load(RIFLE) as WeaponDef, 60)
	var stage := STAGES[_index]
	_clock += delta
	var actions: Array[StringName] = []
	actions.append_array(stage["hold"])
	var taps: Dictionary = stage.get("taps", {})
	for action: StringName in taps:
		for at: float in taps[action]:
			if _clock >= at and _clock < at + 0.1:
				actions.append(action)
	_hold_actions(actions)
	var rifle := _player.model.get_node_or_null("RifleHeld") as TwoHandHold
	if rifle != null and rifle.free_amount() > 0.0:
		print("FREE %s %.2f" % [stage["name"], rifle.free_amount()])


func _process(_delta: float) -> void:
	if _close == null:
		return
	var chest := _player.global_position + Vector3.UP * 1.25
	var facing := _player.model.global_basis
	var view: Array = VIEWS[_view]
	var up := Vector3.UP if _view != "top" else facing.z
	_close.global_position = chest + facing * (view[0] as Vector3)
	_close.look_at(chest + facing * (view[1] as Vector3), up)


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits.
func _finish() -> void:
	_hold_actions([])
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()


# Holds exactly these actions down and lets go of the rest.
func _hold_actions(actions: Array[StringName]) -> void:
	for action in _held:
		if not actions.has(action):
			Input.action_release(action)
	_held.clear()
	for action in actions:
		Input.action_press(action)
		_held.append(action)
