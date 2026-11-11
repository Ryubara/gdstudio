## Films the hands on the rifle up close, in every state the rifle has, for the weapons page's hand
## rules (kit #889): six views at once, each drawn by a viewport of its own over the game, with
## the state's name on the frame. The grip hand from the rifle's right and from its left (the
## thumb's side), the support hand from the left and from the right (the fingers' side), both
## from above, and the whole stance from the right. The cameras ride the rifle, so a view shows
## the same side of the hand at the low ready and at the shoulder. It presses the input actions
## the way a player would: the low ready, a walk, the aim, a burst, a crouch, a crouched aim,
## the reload, a switch to the pistol and one back.
##
## Record it with Movie Maker through the kit (the frames land where `--write-movie` says):
## `gds godot -- --path game --write-movie <folder>/f.png --fixed-fps 20 --quit-after 330
## res://tools/capture/rifle_hands.tscn`
## At the middle of each stage it prints `HOLD` (how far each hand's bone is from its place on the
## rifle, and how far each arm fell short), `CONTACT` (the skin of each hand against the rifle:
## the deepest part and the holding part farthest off, `HandContact`) and `ARMS` (each arm's
## shoulder and elbow in the rifle's space, which `tools/hold/solve_rifle_hold.py` takes as
## `SHOULDERS`); through the two switches it prints `SWITCH` on every frame (which weapon is
## shown and where the hands are). It lives in tools/, which the export leaves out, and nothing
## in the game refers to it.
extends Node

const FLOOR_AT := Vector3(0.0, 300.0, 0.0)
const START := Vector3(0.0, 300.1, 0.0)
const TARGET_AT := Vector3(0.6, 300.0, -15.0)
const RIFLE := "res://gameplay/weapon/rifle.tres"
const PITCH := 0.0
## Each stage: `name`, `hold` the actions held, `seconds` how long, `taps`: actions pressed for
## 0.1 s at each of the listed seconds into the stage, `switch`: print every frame.
const STAGES: Array[Dictionary] = [
	{"name": "draw", "hold": [], "seconds": 1.0},
	{"name": "low ready", "hold": [], "seconds": 1.0},
	{"name": "walking", "hold": [&"move_forward"], "seconds": 1.2},
	{"name": "aiming", "hold": [&"aim"], "seconds": 1.0},
	{"name": "shooting", "hold": [&"aim", &"fire"], "seconds": 1.0},
	{"name": "after the burst", "hold": [], "seconds": 1.0},
	{"name": "crouched", "hold": [], "seconds": 1.2, "taps": {&"crouch": [0.05]}},
	{"name": "crouched, aiming", "hold": [&"aim"], "seconds": 1.0},
	{"name": "standing up", "hold": [], "seconds": 0.8, "taps": {&"crouch": [0.05]}},
	{"name": "reload", "hold": [], "seconds": 2.6, "taps": {&"reload": [0.1]}},
	{
		"name": "to the pistol",
		"hold": [],
		"seconds": 1.5,
		"taps": {&"previous_weapon": [0.3]},
		"switch": true
	},
	{
		"name": "to the rifle",
		"hold": [],
		"seconds": 1.5,
		"taps": {&"next_weapon": [0.3]},
		"switch": true
	},
]
## The views: the name, which hand's place the camera looks at (`r`, `l`, both: the middle, or
## `body`: the chest, from a camera that rides the body, not the rifle), where the camera is from
## there and which way is up, in the rifle's space (the muzzle along -X, up +Y, the rifle's left
## +Z).
const VIEWS: Array[Array] = [
	["grip hand, from the right", "r", Vector3(-0.1, 0.06, -0.55), Vector3.UP],
	["grip hand, from the left and below", "r", Vector3(-0.12, -0.28, 0.42), Vector3.UP],
	["both hands, from above", "", Vector3(0.0, 0.8, 0.0), Vector3.LEFT],
	["support hand, from the left", "l", Vector3(-0.05, 0.1, 0.55), Vector3.UP],
	["support hand, from the right", "l", Vector3(-0.12, -0.08, -0.55), Vector3.UP],
	["the stance, from the right", "body", Vector3(-0.25, 0.0, -2.1), Vector3.UP],
]
const COLUMNS := 3
## Where each hand's middle is from its bone, in the bone's space (the palm).
const PALM := Vector3(0.0, 0.08, 0.0)

var _index := -1
var _clock := 0.0
var _held: Array[StringName] = []
var _cameras: Array[Camera3D] = []
var _state: Label
var _hold: TwoHandHold
var _contact: HandContact
var _reported := -1
var _frame := 0

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	var floor_block := (load("res://world/blocks/proto_block.tscn") as PackedScene).instantiate()
	floor_block.size = Vector3(40.0, 1.0, 40.0)
	floor_block.position = FLOOR_AT - Vector3(0.0, 0.5, 0.0)
	add_child(floor_block)
	var target := (load("res://gameplay/target/target.tscn") as PackedScene).instantiate()
	target.position = TARGET_AT
	add_child(target)
	_player.teleport(START, PI)
	_player.loadout.give(load(RIFLE) as WeaponDef, 90)
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
		camera.fov = 32.0
		camera.near = 0.02
		port.add_child(camera)
		_cameras.append(camera)
		var label := Label.new()
		label.text = view[0]
		label.position = Vector2(10.0, 6.0)
		label.add_theme_font_size_override(&"font_size", 20)
		label.add_theme_color_override(&"font_outline_color", Color.BLACK)
		label.add_theme_constant_override(&"outline_size", 6)
		container.add_child(label)
	_state = Label.new()
	_state.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_state.position.y = 4.0
	_state.add_theme_font_size_override(&"font_size", 30)
	_state.add_theme_color_override(&"font_color", Color.YELLOW)
	_state.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_state.add_theme_constant_override(&"outline_size", 8)
	layer.add_child(_state)


func _physics_process(delta: float) -> void:
	_rig.orbit(Vector2(-clampf(wrapf(0.0 - _rig.yaw, -180.0, 180.0), -6.0, 6.0), 0.0))
	_rig.orbit(Vector2(0.0, clampf(PITCH - _rig.pitch, -2.0, 2.0)))
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
	if not _find_hold():
		return
	var gun := (_hold.find_child("RightHandTarget", true, false) as Node3D).get_parent() as Node3D
	var places := {
		"r": _palm("RightHandTarget"),
		"l": _palm("LeftHandTarget"),
	}
	places[""] = ((places["r"] as Vector3) + (places["l"] as Vector3)) / 2.0
	places["body"] = _player.global_position + Vector3.UP * 1.15
	# The body's axes named as the rifle's are: the front is -X, the left +Z.
	var facing := _player.model.global_basis.orthonormalized()
	var body := Basis(-facing.z, facing.y, facing.x)
	for index in VIEWS.size():
		var view: Array = VIEWS[index]
		var at: Vector3 = places[view[1]]
		var basis := body if view[1] == "body" else gun.global_basis.orthonormalized()
		_cameras[index].global_position = at + basis * (view[2] as Vector3)
		_cameras[index].look_at(at, basis * (view[3] as Vector3))
	if _index < 0 or _index >= STAGES.size():
		return
	var stage := STAGES[_index]
	if stage.get("switch", false):
		_measure.call_deferred("SWITCH %.2f" % _clock, false)
	elif _reported != _index and _clock >= float(stage["seconds"]) * 0.6:
		_reported = _index
		_measure.call_deferred("HOLD " + String(stage["name"]), true)


# The made rifle hold, looked up once the rifle is first carried.
func _find_hold() -> bool:
	if _hold == null:
		_hold = _player.model.get_node_or_null("RifleHeld") as TwoHandHold
	# The contact measure takes the rifle's meshes once they are shown.
	if _hold != null and _contact == null and _hold.is_visible_in_tree():
		_contact = HandContact.new(_player.model.skeleton())
		_contact.set_weapon(_hold.find_child("Near", true, false) as Node3D)
	return _contact != null


# Where the palm of the hand at `target` is in the world.
func _palm(target: String) -> Vector3:
	return (_hold.find_child(target, true, false) as Node3D).global_transform * PALM


# Reads the hands when the skeleton has its final pose: how far each hand's bone is from its
# place on the rifle, and with `full` the skin against the rifle and the arms in its space.
func _measure(tag: String, full: bool) -> void:
	var skeleton := _player.model.skeleton()
	await skeleton.skeleton_updated
	_contact.snapshot()
	var pistol := _player.model.find_child("PistolHeld", true, false) as Node3D
	var line := (
		"%s | rifle %s pistol %s reach %.2f"
		% [
			tag,
			"shown" if _hold.is_visible_in_tree() else "hidden",
			"shown" if pistol != null and pistol.is_visible_in_tree() else "hidden",
			_hold.reach_amount(),
		]
	)
	for side: String in ["r", "l"]:
		var target := (
			_hold.find_child("RightHandTarget" if side == "r" else "LeftHandTarget", true, false)
			as Node3D
		)
		var hand := skeleton.global_transform * _contact.bone_pose("hand_" + side)
		line += " | %s %.1f mm" % [side, hand.origin.distance_to(target.global_position) * 1e3]
	var short := _hold.shortfall()
	line += " | short %.1f %.1f mm" % [short.x * 1e3, short.y * 1e3]
	print(line)
	if not full:
		return
	await get_tree().process_frame
	print(
		(
			"CONTACT %s | right %s | left %s"
			% [
				STAGES[_reported]["name"],
				HandContact.summary(_contact.measure("r"), RifleStage.RIFLE_RIGHT_CONTACTS),
				HandContact.summary(_contact.measure("l"), RifleStage.RIFLE_LEFT_CONTACTS),
			]
		)
	)
	var gun := (_hold.find_child("RightHandTarget", true, false) as Node3D).get_parent() as Node3D
	var inverse := gun.global_transform.affine_inverse() * skeleton.global_transform
	var arms := "ARMS %s" % STAGES[_reported]["name"]
	for bone: String in ["upperarm_r", "lowerarm_r", "upperarm_l", "lowerarm_l"]:
		arms += " %s %s" % [bone, (inverse * _contact.bone_pose(bone).origin).snappedf(0.001)]
	print(arms)


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
