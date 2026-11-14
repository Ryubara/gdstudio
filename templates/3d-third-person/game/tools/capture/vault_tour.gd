## Films the vault course on the map with the game camera, one wall at a time and each from
## three places: `player` (behind the body, where the player's own camera sits), `side` (the whole
## crossing from the body's right) and `close` (near the planted hand, at half speed, so the hand
## on the top and the feet over it show). After the walls it mantles the tall block and runs at
## the dark wall that has no `Vaultable`, which is only jumped. It presses the input actions the
## way a player would; it only puts the body at the start of each run.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --scene res://tools/capture/vault_tour.tscn --seconds 42
## --fps 30`. `WALLS=Vault09` films only that wall (a comma list of the course's node names),
## `VIEWS=player,close` only those views, `MODEL=male` the template's male body, `WEAPON=rifle`
## that weapon of `gameplay/weapon/` in the hands (the rifle's vault: gdstudio #1409).
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

const COURSE := "World/Level/VaultCourse/"
const MALE := CharacterBodies.MALE
## How far before a wall's face the run starts and the jump is pressed, and for how long.
const RUN_IN := 1.7
const PRESS_BEFORE := 0.6
const PRESS_SECONDS := 0.15
## Seconds the run goes on after a crossing ends.
const RUN_ON := 0.2
## Ticks the body stands at the start while the camera comes round.
const SETTLE_TICKS := 40
## The views: the camera's heading (0 looks along -Z, so a run toward +X crosses the frame left
## to right), pitch and distance, the game's speed and how long the run is filmed (game seconds).
const VIEWS := {
	"player": {"yaw": -90.0, "pitch": 12.0, "distance": 3.2, "speed": 1.0, "seconds": 2.0},
	"side": {"yaw": 0.0, "pitch": 8.0, "distance": 4.2, "speed": 1.0, "seconds": 2.0},
	"close": {"yaw": 200.0, "pitch": 16.0, "distance": 1.9, "speed": 0.4, "seconds": 1.5},
}
## What is filmed, in order: a wall of the course and the views it is filmed from.
const SHOTS: Array[Dictionary] = [
	{"wall": "Vault05", "views": ["player", "side", "close"]},
	{"wall": "Vault09", "views": ["player", "side", "close"]},
	{"wall": "Vault12", "views": ["player", "side", "close"]},
	{"wall": "Mantle16", "views": ["side"]},
	{"wall": "NoVault09", "views": ["side"]},
]

var _runs: Array[Dictionary] = []
var _run := -1
var _tick := 0
var _clock := 0.0
var _press := 0.0
var _pressed := false
var _crossed := false
var _after := 0.0
var _label: Label

@onready var _main: Node = $Main
@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	var walls := _asked("WALLS")
	var views := _asked("VIEWS")
	for shot in SHOTS:
		if not walls.is_empty() and not walls.has(shot["wall"]):
			continue
		for view: String in shot["views"]:
			if views.is_empty() or views.has(view):
				_runs.append({"wall": shot["wall"], "view": view})
	if OS.get_environment("MODEL") == "male":
		var old := _player.model.rig()
		_player.model.remove_child(old)
		old.queue_free()
		_player.model.add_child((load(MALE) as PackedScene).instantiate())
	var weapon := OS.get_environment("WEAPON")
	if weapon != "":
		_arm.call_deferred(load("res://gameplay/weapon/%s.tres" % weapon) as WeaponDef)
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(32, 24)
	_label.add_theme_font_size_override("font_size", 30)
	layer.add_child(_label)
	_player.state_changed.connect(func(state: Character.State) -> void: print("STATE ", state))


func _physics_process(delta: float) -> void:
	if _run >= _runs.size():
		return
	if _run < 0 or _clock >= float(_view()["seconds"]):
		_next()
		if _run >= _runs.size():
			_finish()
			return
	var view := _view()
	_rig.distance = view["distance"]
	_rig.orbit(Vector2(-clampf(wrapf(float(view["yaw"]) - _rig.yaw, -180.0, 180.0), -9.0, 9.0), 0))
	_rig.orbit(Vector2(0.0, clampf(float(view["pitch"]) - _rig.pitch, -3.0, 3.0)))
	_tick += 1
	if _tick <= SETTLE_TICKS or _player.loadout.is_switching():
		return
	Engine.time_scale = view["speed"]
	_clock += delta
	var block := _main.get_node(COURSE + str(_runs[_run]["wall"])) as ProtoBlock
	var west := block.global_position.x - block.size.x / 2.0
	if not _pressed and _player.global_position.x >= west - _player.tuning.radius - PRESS_BEFORE:
		_press = PRESS_SECONDS
		_pressed = true
	_press = maxf(_press - delta, 0.0)
	# Runs on through the step out of the landing, then stands (the next wall is close).
	var crossing := _player.vault_motion.is_active()
	if _crossed and not crossing:
		_after += delta
	_crossed = _crossed or crossing
	if _after < RUN_ON:
		_walk_east()
	else:
		_release()
	if _press > 0.0:
		Input.action_press(&"jump")
	else:
		Input.action_release(&"jump")


# Puts `definition` in the hands: its slot, or given with a magazine's worth.
func _arm(definition: WeaponDef) -> void:
	var loadout := _player.loadout
	for index in loadout.slots.size():
		var slot := loadout.slots[index] as WeaponDef
		if slot != null and slot.resource_path == definition.resource_path:
			loadout.select(index)
			return
	loadout.give(definition, 60)


# The names an environment variable lists (comma separated), or none.
func _asked(variable: String) -> PackedStringArray:
	var value := OS.get_environment(variable)
	return value.split(",", false) if value != "" else PackedStringArray()


func _view() -> Dictionary:
	return VIEWS[_runs[_run]["view"]]


# Holds the move actions that take the body toward +X, wherever the camera looks from.
func _walk_east() -> void:
	var camera := get_viewport().get_camera_3d()
	var right := Vector3.RIGHT
	var ahead := Vector3.FORWARD
	if camera != null:
		right = camera.global_basis.x
		ahead = -camera.global_basis.z
	var flat_right := Vector2(right.x, right.z).normalized()
	var flat_ahead := Vector2(ahead.x, ahead.z).normalized()
	_hold(&"move_right", &"move_left", flat_right.x)
	_hold(&"move_forward", &"move_back", flat_ahead.x)


func _hold(positive: StringName, negative: StringName, amount: float) -> void:
	Input.action_release(positive)
	Input.action_release(negative)
	if absf(amount) > 0.05:
		Input.action_press(positive if amount > 0.0 else negative, absf(amount))


func _release() -> void:
	for action: StringName in [&"move_right", &"move_left", &"move_forward", &"move_back", &"jump"]:
		Input.action_release(action)


func _next() -> void:
	_run += 1
	_clock = 0.0
	_tick = 0
	_press = 0.0
	_pressed = false
	_crossed = false
	_after = 0.0
	Engine.time_scale = 1.0
	_release()
	if _run >= _runs.size():
		return
	var wall: String = _runs[_run]["wall"]
	var block := _main.get_node(COURSE + wall) as ProtoBlock
	print("RUN ", wall, " ", _runs[_run]["view"])
	_label.text = "%s   %s" % [wall, _runs[_run]["view"]]
	var west := block.global_position.x - block.size.x / 2.0
	_player.teleport(Vector3(west - RUN_IN, 0.0, block.global_position.z), PI / 2.0)


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits.
func _finish() -> void:
	_release()
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()
