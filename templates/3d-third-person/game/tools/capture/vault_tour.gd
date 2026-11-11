## Films the vault course on the map from the side with the game camera: the player runs the lane
## and presses jump at each wall (it vaults the three low ones and mantles the tall block), then
## runs at the dark wall that has no `Vaultable` and only jumps it. It presses the input actions
## the way a player would; it only puts the body at the start of each lane.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --scene res://tools/capture/vault_tour.tscn --seconds 9
## --fps 20`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## The camera's heading (0 looks along -Z, so a run toward +X crosses the frame left to right),
## pitch and distance (backed off so the whole body and the wall are in the frame).
const YAW := 0.0
const PITCH := 8.0
const DISTANCE := 4.2
## How far before a wall's face the jump is pressed, and for how long.
const PRESS_BEFORE := 0.6
const PRESS_SECONDS := 0.15

## The lanes: where the body starts (facing +X), the walls it presses jump at, in order, and how
## long the lane runs.
const LANES: Array[Dictionary] = [
	{
		"name": "vault course",
		"start": Vector3(-20.5, 0.0, -12.0),
		"walls":
		[
			"World/Level/VaultCourse/Vault05",
			"World/Level/VaultCourse/Vault09",
			"World/Level/VaultCourse/Vault12",
			"World/Level/VaultCourse/Mantle16",
		],
		"seconds": 5.5,
	},
	{
		"name": "no vaultable",
		"start": Vector3(-18.6, 0.0, -15.0),
		"walls": ["World/Level/VaultCourse/NoVault09"],
		"seconds": 3.0,
	},
]

var _lane := -1
var _wall := 0
var _clock := 0.0
var _press := 0.0

@onready var _main: Node = $Main
@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	_rig.distance = DISTANCE
	_player.state_changed.connect(func(state: Character.State) -> void: print("STATE ", state))


func _physics_process(delta: float) -> void:
	_rig.orbit(Vector2(-clampf(wrapf(YAW - _rig.yaw, -180.0, 180.0), -6.0, 6.0), 0.0))
	_rig.orbit(Vector2(0.0, clampf(PITCH - _rig.pitch, -2.0, 2.0)))
	if _lane >= LANES.size():
		return
	if _lane < 0 or _clock >= float(LANES[_lane]["seconds"]):
		_next()
		if _lane >= LANES.size():
			_finish()
			return
	_clock += delta
	var walls: Array = LANES[_lane]["walls"]
	if _wall < walls.size():
		var block := _main.get_node(walls[_wall] as String) as ProtoBlock
		var west := block.global_position.x - block.size.x / 2.0
		if _player.global_position.x >= west - _player.tuning.radius - PRESS_BEFORE:
			_press = PRESS_SECONDS
			_wall += 1
	_press = maxf(_press - delta, 0.0)
	Input.action_press(&"move_right")
	if _press > 0.0:
		Input.action_press(&"jump")
	else:
		Input.action_release(&"jump")


func _next() -> void:
	_lane += 1
	_clock = 0.0
	_wall = 0
	if _lane >= LANES.size():
		return
	print("LANE ", LANES[_lane]["name"])
	_player.teleport(LANES[_lane]["start"], PI / 2.0)


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits.
func _finish() -> void:
	Input.action_release(&"move_right")
	Input.action_release(&"jump")
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()
