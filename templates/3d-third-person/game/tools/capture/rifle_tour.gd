## Films the rifle's floating pickup and the rifle in the hands from the game camera, with the HUD:
## the rifle spinning over its glow, the character walking into it (the pickup sound, the rifle
## brought out), the low ready, the aim, a long automatic burst at a target, the reload, a burst
## from the hip, a switch to the pistol and back. It presses the input actions the way a player
## would, for the pull request's captures.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --scene res://tools/capture/rifle_tour.tscn --seconds 17
## --fps 20`
## `RIFLE_VIEW=side|top|front` (or `-- side` after Godot's own arguments, through `gds godot --
## --write-movie`) films close-ups of the hands instead (a camera beside the right hand, above
## it, or in front of the character, drawn by a viewport of its own), for the weapons page's hand
## rules.
## It prints a `STAGE` line as each stage starts and `HOLD` lines with how far each hand is from
## its target on the gun. It lives in tools/, which the export leaves out, and nothing in the game
## refers to it.
extends Node

## A flat floor built high above the map, and where the character stands on it.
const FLOOR_AT := Vector3(0.0, 300.0, 0.0)
const START := Vector3(0.0, 300.1, 0.0)
const PICKUP_AT := Vector3(0.0, 300.0, -3.2)
const TARGET_AT := Vector3(0.6, 300.0, -15.0)
const PITCH := 6.0

## Each stage: `name`, `hold` the actions held, `seconds` how long, `taps`: actions pressed for 0.1
## s at each of the listed seconds into the stage, and `pitch`: the camera's pitch to go to.
const STAGES: Array[Dictionary] = [
	{"name": "floating", "hold": [], "seconds": 2.0},
	{"name": "walk in", "hold": [&"move_forward"], "seconds": 0.95},
	{"name": "draw", "hold": [], "seconds": 1.2},
	{"name": "low ready", "hold": [], "seconds": 1.0},
	{"name": "aim", "hold": [&"aim"], "seconds": 0.8},
	{"name": "burst", "hold": [&"aim", &"fire"], "seconds": 2.0},
	{"name": "aim up", "hold": [&"aim"], "seconds": 1.2, "pitch": 30.0},
	{"name": "aim down", "hold": [&"aim"], "seconds": 1.2, "pitch": -20.0},
	{"name": "reload", "hold": [], "seconds": 2.8, "taps": {&"reload": [0.1]}},
	{"name": "hip fire", "hold": [&"fire"], "seconds": 1.0},
	{"name": "to the pistol", "hold": [], "seconds": 1.3, "taps": {&"previous_weapon": [0.1]}},
	{"name": "back to the rifle", "hold": [], "seconds": 1.5, "taps": {&"next_weapon": [0.1]}},
]
## The close-up views: where the camera is from the right hand, in the character's space (+Z its
## front, +X its left), and what it looks at from the hand.
const VIEWS: Dictionary = {
	"side": [Vector3(-0.8, 0.05, 0.2), Vector3(0.0, -0.05, 0.2)],
	"top": [Vector3(-0.05, 0.85, 0.25), Vector3(0.0, 0.0, 0.25)],
	"front": [Vector3(0.25, 0.15, 1.1), Vector3(0.1, 0.0, 0.15)],
}

var _index := -1
var _clock := 0.0
var _pitch := PITCH
var _held: Array[StringName] = []
var _view := _view_asked()
var _close: Camera3D
var _hold: TwoHandHold

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	var floor_block := (load("res://world/blocks/proto_block.tscn") as PackedScene).instantiate()
	floor_block.size = Vector3(40.0, 1.0, 40.0)
	floor_block.position = FLOOR_AT - Vector3(0.0, 0.5, 0.0)
	add_child(floor_block)
	var pickup := (load("res://gameplay/pickup/rifle_pickup.tscn") as PackedScene).instantiate()
	pickup.position = PICKUP_AT
	add_child(pickup)
	var target := (load("res://gameplay/target/target.tscn") as PackedScene).instantiate()
	target.position = TARGET_AT
	add_child(target)
	_player.teleport(START, PI)
	(pickup as WeaponPickup).weapon_taken.connect(
		func(_who: Node3D, what: WeaponDef, _how: int) -> void: print("TAKEN ", what.display_name)
	)
	_player.loadout.weapon_changed.connect(
		func(definition: WeaponDef) -> void: print("WEAPON ", definition.display_name)
	)
	_player.weapon.reloaded.connect(func() -> void: print("RELOADED ", _player.weapon.reserve))
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


# The close-up view asked for: `RIFLE_VIEW` or a user argument after `--` (`-- side`).
static func _view_asked() -> String:
	for argument in OS.get_cmdline_user_args():
		if VIEWS.has(argument):
			return argument
	return OS.get_environment("RIFLE_VIEW")


func _physics_process(delta: float) -> void:
	_rig.orbit(Vector2(-clampf(wrapf(0.0 - _rig.yaw, -180.0, 180.0), -6.0, 6.0), 0.0))
	_rig.orbit(Vector2(0.0, clampf(_pitch - _rig.pitch, -2.0, 2.0)))
	if _index >= STAGES.size():
		return
	if _index < 0 or _clock >= float(STAGES[_index]["seconds"]):
		_index += 1
		_clock = 0.0
		if _index >= STAGES.size():
			_finish()
			return
		print("STAGE ", STAGES[_index]["name"])
		_pitch = STAGES[_index].get("pitch", PITCH)
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
	if _clock < delta * 1.5 and _rifle_out():
		_report.call_deferred()


func _process(_delta: float) -> void:
	if _close == null or not _rifle_out():
		return
	# The hand's target, where the IK puts the hand: outside `skeleton_updated` the bone reads the
	# clip's pose (the arm down).
	var hand := (_hold.find_child("RightHandTarget", true, false) as Node3D).global_transform
	var facing := _player.model.global_basis
	var view: Array = VIEWS[_view]
	var up := Vector3.UP if _view != "top" else facing.z
	_close.global_position = hand.origin + facing * (view[0] as Vector3)
	_close.look_at(hand.origin + facing * (view[1] as Vector3), up)


# Whether the rifle is in the hands. The loadout makes `RifleHeld` under `Model` only when the
# character first carries the rifle (`WeaponDef.view_scene`), so it is looked up then.
func _rifle_out() -> bool:
	if _hold == null:
		_hold = _player.model.get_node_or_null("RifleHeld") as TwoHandHold
	return _hold != null and _hold.visible


# How far each hand is from its target on the gun, read when the skeleton has its final pose.
func _report() -> void:
	var skeleton := _player.model.skeleton()
	await skeleton.skeleton_updated
	var line := "HOLD %s raised %.2f" % [STAGES[_index]["name"], _hold.raised_amount()]
	for side: String in ["r", "l"]:
		var target := (
			_hold.find_child("RightHandTarget" if side == "r" else "LeftHandTarget", true, false)
			as Node3D
		)
		var bone := skeleton.find_bone("hand_" + side)
		var hand := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
		line += " | %s %.1f cm" % [side, hand.origin.distance_to(target.global_position) * 100.0]
	var muzzle := _hold.find_child("Muzzle", true, false) as Node3D
	line += (
		" | facing %s muzzle %s"
		% [_player.model.global_basis.z.round(), (-muzzle.global_basis.z).round()]
	)
	print(line)


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
