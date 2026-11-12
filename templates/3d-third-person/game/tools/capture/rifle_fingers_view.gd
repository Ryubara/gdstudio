## Films the fingers on the rifle as the player sees them (kit #1036): six views at once, each a
## viewport of its own over the game, every one from the game camera's eye. The game camera as it
## is, then each hand from its thumb's side and from its fingers' side (the trigger finger lies
## on the rifle's right) and both hands, each a long lens aimed at the hand from
## the game camera's eye swung round the character as the player swings the view (straight behind,
## the body hides both hands), at the camera's own distance and height: only the field narrows,
## so a close-up shows the hand as the game draws it from there. It presses the
## input actions a player would: the low ready, a walk, the aim, a burst, a crouch, a crouched aim
## and the reload, with the state's name on the frame. `rifle_hands.tscn` films the same states
## from round the rifle.
##
## Record it with Movie Maker through the kit (the frames land where `--write-movie` says):
## `gds godot -- --path game --resolution 1920x1080 --write-movie <folder>/f.png --fixed-fps 20
## --quit-after 230 res://tools/capture/rifle_fingers_view.tscn`
## At each stage it prints `STAGE` with its first frame, and two thirds in `FINGERS`: each part of
## each hand against the rifle in millimetres (below 0 inside; `HandContact`), so a still can be
## read against its numbers. `RIFLE_FINGERS_BODY=male` films the other body (the hold is solved on
## each, `HoldFit`). It lives in tools/, which the export leaves out, and nothing in the
## game refers to it.
extends Node

const FLOOR_AT := Vector3(0.0, 300.0, 0.0)
const START := Vector3(0.0, 300.1, 0.0)
const TARGET_AT := Vector3(0.6, 300.0, -15.0)
const RIFLE := "res://gameplay/weapon/rifle.tres"
## Each stage: `name`, `hold` the actions held, `seconds` how long, `taps`: actions pressed for
## 0.1 s at each of the listed seconds into the stage.
const STAGES: Array[Dictionary] = [
	{"name": "draw", "hold": [], "seconds": 1.2},
	{"name": "low ready", "hold": [], "seconds": 1.2},
	{"name": "walking", "hold": [&"move_forward"], "seconds": 1.2},
	{"name": "aiming", "hold": [&"aim"], "seconds": 1.2},
	{"name": "shooting", "hold": [&"aim", &"fire"], "seconds": 1.0},
	{"name": "crouched", "hold": [], "seconds": 1.4, "taps": {&"crouch": [0.05]}},
	{"name": "crouched, aiming", "hold": [&"aim"], "seconds": 1.2},
	{"name": "reload", "hold": [], "seconds": 2.6, "taps": {&"crouch": [0.05], &"reload": [0.3]}},
]
## The views: the name, what the lens frames (`game` the camera as it is; `r`, `l` a hand's palm;
## `both` the middle of the two), how much of the world it frames across, in metres at the hand's
## distance, and how many degrees the game camera's eye is swung round the character (to its
## right above 0).
const VIEWS: Array[Array] = [
	["the game camera", "game", 0.0, 0.0],
	["grip hand's thumb, game camera swung 125 degrees left", "r", 0.2, -125.0],
	["trigger finger, game camera swung 90 degrees right", "r", 0.2, 90.0],
	["support hand's fingers, game camera swung 70 degrees right", "l", 0.2, 70.0],
	["support hand's thumb, game camera swung 80 degrees left", "l", 0.2, -80.0],
	["both hands, game camera swung 35 degrees right", "both", 0.5, 35.0],
]
const COLUMNS := 3
## Where each hand's middle is from its bone, in the bone's space (the palm).
const PALM := Vector3(0.0, 0.08, 0.0)
## The parts printed for each hand, in this order.
const PARTS: Array[String] = [
	"palm",
	"thumb_mid",
	"thumb_tip",
	"index_mid",
	"index_tip",
	"middle_mid",
	"middle_tip",
	"ring_mid",
	"ring_tip",
	"pinky_mid",
	"pinky_tip",
]

var _index := -1
var _clock := 0.0
var _held: Array[StringName] = []
var _cameras: Array[Camera3D] = []
var _state: Label
var _hold: Node3D
var _contact: HandContact
var _reported := -1
var _frame := 0

@onready var _player: Player = $Main/PlayerRig/Player


func _ready() -> void:
	var floor_block := (load("res://world/blocks/proto_block.tscn") as PackedScene).instantiate()
	floor_block.size = Vector3(40.0, 1.0, 40.0)
	floor_block.position = FLOOR_AT - Vector3(0.0, 0.5, 0.0)
	add_child(floor_block)
	var target := (load("res://gameplay/target/target.tscn") as PackedScene).instantiate()
	target.position = TARGET_AT
	add_child(target)
	_player.teleport(START, PI)
	var body := OS.get_environment("RIFLE_FINGERS_BODY")
	if CharacterBodies.BY_NAME.has(body):
		_player.model.variant = load(CharacterBodies.BY_NAME[body]) as PackedScene
	_player.loadout.give(load(RIFLE) as WeaponDef, 90)
	# After the camera rig has placed the game camera this frame.
	process_priority = 1000
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid.add_theme_constant_override(&"h_separation", 2)
	grid.add_theme_constant_override(&"v_separation", 2)
	layer.add_child(grid)
	for view: Array in VIEWS:
		var container := SubViewportContainer.new()
		container.stretch = true
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		grid.add_child(container)
		var port := SubViewport.new()
		port.world_3d = get_viewport().world_3d
		container.add_child(port)
		var camera := Camera3D.new()
		camera.near = 0.02
		port.add_child(camera)
		_cameras.append(camera)
		var label := Label.new()
		label.text = view[0]
		label.position = Vector2(10.0, 6.0)
		label.add_theme_font_size_override(&"font_size", 16)
		label.add_theme_color_override(&"font_outline_color", Color.BLACK)
		label.add_theme_constant_override(&"outline_size", 6)
		container.add_child(label)
	_state = Label.new()
	_state.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_state.position.y = 34.0
	_state.add_theme_font_size_override(&"font_size", 30)
	_state.add_theme_color_override(&"font_color", Color.YELLOW)
	_state.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_state.add_theme_constant_override(&"outline_size", 8)
	layer.add_child(_state)


func _physics_process(delta: float) -> void:
	if _index >= STAGES.size():
		return
	if _index < 0 or _clock >= float(STAGES[_index]["seconds"]):
		_index += 1
		_clock = 0.0
		if _index >= STAGES.size():
			_finish()
			return
		print("STAGE ", STAGES[_index]["name"], " frame ", _frame)
		_state.text = STAGES[_index]["name"]
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


func _process(_delta: float) -> void:
	_frame += 1
	var eye := get_viewport().get_camera_3d()
	if eye == null or not _find_hold():
		return
	var places := {"r": _palm("RightHandTarget"), "l": _palm("LeftHandTarget")}
	places["both"] = ((places["r"] as Vector3) + (places["l"] as Vector3)) / 2.0
	for index in VIEWS.size():
		var view: Array = VIEWS[index]
		var camera := _cameras[index]
		var pivot := _player.global_position
		var swing := Transform3D(Basis(Vector3.UP, deg_to_rad(float(view[3]))), pivot)
		camera.global_transform = swing * Transform3D(Basis.IDENTITY, -pivot) * eye.global_transform
		if view[1] == "game":
			camera.fov = eye.fov
			continue
		var at: Vector3 = places[view[1]]
		var distance := camera.global_position.distance_to(at)
		camera.look_at(at, Vector3.UP)
		camera.fov = rad_to_deg(2.0 * atan(float(view[2]) / 2.0 / distance))
	if _index < 0 or _index >= STAGES.size():
		return
	if _reported != _index and _clock >= float(STAGES[_index]["seconds"]) * 0.66:
		_reported = _index
		_measure.call_deferred(String(STAGES[_index]["name"]))


# The made rifle hold, looked up once the rifle is first carried; the contact measure takes the
# rifle's meshes once they are shown.
func _find_hold() -> bool:
	if _hold == null:
		_hold = _player.model.get_node_or_null("RifleHeld") as Node3D
	if _hold != null and _contact == null and _hold.is_visible_in_tree():
		_contact = HandContact.new(_player.model.skeleton())
		_contact.set_weapon(_hold.find_child("Near", true, false) as Node3D)
	return _contact != null


# Where the palm of the hand at `target` is in the world.
func _palm(target: String) -> Vector3:
	return (_hold.find_child(target, true, false) as Node3D).global_transform * PALM


# Prints every part of both hands against the rifle, in the update the modifiers made.
func _measure(tag: String) -> void:
	await _player.model.skeleton().skeleton_updated
	_contact.snapshot()
	var line := "FINGERS %s frame %d" % [tag, _frame]
	for side: String in ["r", "l"]:
		var parts := _contact.measure(side)
		line += " | %s" % side
		for part in PARTS:
			line += " %s %.1f" % [part, float(parts[part].distance) * 1e3]
	print(line)


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits.
func _finish() -> void:
	_hold_actions([])
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _frame_left in 8:
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
