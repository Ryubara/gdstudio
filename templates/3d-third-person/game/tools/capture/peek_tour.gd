## Films the peek lean around cover (gdstudio #1400) from the game camera, with the HUD: the
## character stands behind a pillar with a target past each of its edges, aims at the right one
## upright (the pillar is in the way), leans right with E and shoots it, then turns to the left one
## and leans left with Q and shoots it, the camera on the lean's shoulder each time; then the same
## crouched; then all of it again with the rifle. It presses the input actions the way a player
## would and prints each stage (`STAGE <name> <tick>`) and shot (`SHOT <tick> <lean>`).
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --scene res://tools/capture/peek_tour.tscn --seconds 26
## --fps 30`. `PEEK_ONLY=pistol` or `PEEK_ONLY=rifle` films one weapon (13 s). The pillar is as
## wide as a right lean's shot clears (0.8 m): on a left lean the weapon goes to the left side
## (gdstudio #1435) and its shot clears the other edge too; `LEFT_SHOULDER=0` films it as before,
## the weapon right of the head and the left shot in the pillar. Each hit prints `HIT <tick> <who>`.
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## A flat floor built high above the map, and where the character stands on it.
const FLOOR_AT := Vector3(0.0, 300.0, 0.0)
const START := Vector3(0.0, 300.1, 0.0)
## The pillar in front of the character, and the two targets past its edges.
const PILLAR_AT := Vector3(0.0, 300.0, -1.4)
const PILLAR_SIZE := Vector3(0.8, 2.6, 0.5)
const TARGETS: Array[Vector3] = [Vector3(3.5, 300.0, -10.0), Vector3(-3.5, 300.0, -10.0)]
const PITCH := 3.0
## The view's heading toward each target, degrees (positive turns left).
const RIGHT_YAW := -19.0
const LEFT_YAW := 19.0

## Each stage: `name`, `hold` the actions held, `yaw` the view's heading (and `pitch`, else
## `PITCH`), `seconds` how long and `fire` the seconds into it a shot is pressed (one tick).
const STAGES: Array[Dictionary] = [
	{
		"name": "upright, aimed past the right edge",
		"hold": [&"aim"],
		"yaw": RIGHT_YAW,
		"seconds": 1.5
	},
	{
		"name": "lean right",
		"hold": [&"aim", &"lean_right"],
		"yaw": RIGHT_YAW,
		"seconds": 2.0,
		"fire": [1.0],
	},
	{
		"name": "upright, aimed past the left edge",
		"hold": [&"aim"],
		"yaw": LEFT_YAW,
		"seconds": 1.2
	},
	{
		"name": "lean left",
		"hold": [&"aim", &"lean_left"],
		"yaw": LEFT_YAW,
		"seconds": 2.0,
		"fire": [1.0],
	},
	{"name": "crouch", "hold": [&"crouch"], "yaw": RIGHT_YAW, "seconds": 1.0},
	{
		"name": "crouched lean right",
		"hold": [&"crouch", &"aim", &"lean_right"],
		"yaw": RIGHT_YAW + 1.0,
		"pitch": PITCH - 1.5,
		"seconds": 2.0,
		"fire": [1.1],
	},
	{
		"name": "crouched lean left",
		"hold": [&"crouch", &"aim", &"lean_left"],
		"yaw": LEFT_YAW - 1.0,
		"pitch": PITCH - 1.5,
		"seconds": 2.3,
		"fire": [1.4],
	},
	{"name": "stand", "hold": [], "yaw": 0.0, "seconds": 1.0},
]

var _weapons: Array[String] = ["pistol", "rifle"]
var _weapon := 0
var _index := -1
var _clock := 0.0
var _held: Array[StringName] = []

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	var only := OS.get_environment("PEEK_ONLY")
	if only != "":
		_weapons = [only]
	var block := load("res://world/blocks/proto_block.tscn") as PackedScene
	var floor_block := block.instantiate()
	floor_block.size = Vector3(40.0, 1.0, 40.0)
	floor_block.position = FLOOR_AT - Vector3(0.0, 0.5, 0.0)
	add_child(floor_block)
	var pillar := block.instantiate()
	pillar.size = PILLAR_SIZE
	pillar.position = PILLAR_AT + Vector3.UP * PILLAR_SIZE.y / 2.0
	add_child(pillar)
	for spot in TARGETS:
		var target := (load("res://gameplay/target/target.tscn") as PackedScene).instantiate()
		target.position = spot
		add_child(target)
		_watch_hits(target, "target right" if spot.x > 0.0 else "target left")
	if OS.get_environment("LEFT_SHOULDER") == "0":
		_player.peek_tuning = _player.peek_tuning.duplicate()
		_player.peek_tuning.left_shoulder = false
	_watch_hits(pillar.get_node(^"Body"), "pillar")
	_player.loadout.give(load("res://gameplay/weapon/rifle.tres") as WeaponDef, 60)
	_player.teleport(START, PI)
	_player.weapon.fired.connect(
		func(_shot: Projectile) -> void:
			print("SHOT ", Engine.get_physics_frames(), " ", _player.peek_motion.amount)
	)


func _physics_process(delta: float) -> void:
	if _weapon >= _weapons.size():
		return
	if _index < 0 or _clock >= float(STAGES[_index]["seconds"]):
		_next_stage()
		if _weapon >= _weapons.size():
			return
	var stage := STAGES[_index]
	var want: float = stage["yaw"]
	_rig.orbit(Vector2(clampf(wrapf(_rig.yaw - want, -180.0, 180.0), -3.0, 3.0), 0.0))
	var down: float = stage.get("pitch", PITCH)
	_rig.orbit(Vector2(0.0, clampf(down - _rig.pitch, -2.0, 2.0)))
	var actions: Array[StringName] = []
	actions.append_array(stage["hold"])
	for at: float in stage.get("fire", []):
		if _clock >= at - 1e-4 and _clock < at + delta - 1e-4:
			actions.append(&"fire")
	_clock += delta
	_hold(actions)


func _next_stage() -> void:
	_index += 1
	_clock = 0.0
	if _index >= STAGES.size():
		_index = 0
		_weapon += 1
		if _weapon >= _weapons.size():
			_finish()
			return
	if _index == 0:
		# The pistol is slot 1, the rifle slot 2, asked for as the HUD's number keys ask.
		(_player.controller as PlayerInput).request_weapon(
			0 if _weapons[_weapon] == "pistol" else 1
		)
	print(
		"STAGE ", _weapons[_weapon], " ", STAGES[_index]["name"], " ", Engine.get_physics_frames()
	)


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits.
func _finish() -> void:
	_hold([])
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()


# Prints a line for each hit `node` takes: a `Health` of its own (one is given to the pillar).
func _watch_hits(node: Node, who: String) -> void:
	var health := node.get_node_or_null(^"Health") as Health
	if health == null:
		health = Health.new()
		health.name = &"Health"
		health.max_value = 1000.0
		node.add_child(health)
	health.damaged.connect(
		func(_amount: float, _hit: HitRecord) -> void:
			print("HIT ", Engine.get_physics_frames(), " ", who)
	)


# Holds exactly these actions down and lets go of the rest.
func _hold(actions: Array[StringName]) -> void:
	for action in _held:
		if not actions.has(action):
			Input.action_release(action)
	_held.clear()
	for action in actions:
		Input.action_press(action)
		_held.append(action)
