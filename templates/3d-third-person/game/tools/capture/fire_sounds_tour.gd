## Plays the weapons' fire sounds for a listening clip and a level measurement (gdstudio #1414):
## the pistol and then the rifle, each as single shots, a burst and held fire. Every section gives
## the character a copy of the weapon's definition in that fire mode (a burst is three shots at the
## definition's `burst_rate`, held fire the weapon's own `fire_rate` on automatic), brings it out at
## once and presses the input actions the way a player would, aimed at the open sky so no impact
## sound lands in the mix. It prints each section's start and each shot's time in seconds
## (`SECTION <name> <s>`, `SHOT <s>`), which the level script reads to cut the recording.
##
## Record it with Movie Maker through the kit (the frames and a WAV of the mix land in the folder):
## `gds godot -- --path <game> --write-movie <folder>/fire.png --fixed-fps 60
## res://tools/capture/fire_sounds_tour.tscn`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## A flat floor built high above the map, and where the character stands on it.
const FLOOR_AT := Vector3(0.0, 300.0, 0.0)
const START := Vector3(0.0, 300.1, 0.0)
## Degrees up: the shots go into the sky and hit nothing.
const PITCH := 35.0
## One physics tick: the shortest press a player can make.
const TAP := 1.0 / 60.0
## Seconds after a weapon is brought out before its first press, so the draw has died away.
const SETTLE := 0.8

## Each section: `name`, the weapon (`def`), its `mode`, how long it lasts, and the fire presses:
## `taps` at the listed seconds (one tick each) or `hold` from `hold[0]` to `hold[1]`.
const SECTIONS: Array[Dictionary] = [
	{
		"name": "pistol single",
		"def": "res://gameplay/weapon/pistol.tres",
		"mode": WeaponDef.FireMode.SINGLE,
		"seconds": 2.6,
		"taps": [0.0, 0.8, 1.6],
	},
	{
		"name": "pistol burst",
		"def": "res://gameplay/weapon/pistol.tres",
		"mode": WeaponDef.FireMode.BURST,
		"seconds": 2.0,
		"taps": [0.0, 1.0],
	},
	{
		"name": "pistol held",
		"def": "res://gameplay/weapon/pistol.tres",
		"mode": WeaponDef.FireMode.AUTOMATIC,
		"seconds": 2.8,
		"hold": [0.0, 2.0],
	},
	{
		"name": "rifle single",
		"def": "res://gameplay/weapon/rifle.tres",
		"mode": WeaponDef.FireMode.SINGLE,
		"seconds": 2.6,
		"taps": [0.0, 0.8, 1.6],
	},
	{
		"name": "rifle burst",
		"def": "res://gameplay/weapon/rifle.tres",
		"mode": WeaponDef.FireMode.BURST,
		"seconds": 2.0,
		"taps": [0.0, 1.0],
	},
	{
		"name": "rifle held",
		"def": "res://gameplay/weapon/rifle.tres",
		"mode": WeaponDef.FireMode.AUTOMATIC,
		"seconds": 3.0,
		"hold": [0.0, 2.0],
	},
]

var _index := -1
var _clock := 0.0
var _time := 0.0
var _slots: Array[int] = []
var _held: Array[StringName] = []

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	var floor_block := (load("res://world/blocks/proto_block.tscn") as PackedScene).instantiate()
	floor_block.size = Vector3(40.0, 1.0, 40.0)
	floor_block.position = FLOOR_AT - Vector3(0.0, 0.5, 0.0)
	add_child(floor_block)
	var loadout := _player.loadout
	loadout.switch_to_new = false
	for section in SECTIONS:
		var copy := (load(section["def"]) as WeaponDef).duplicate() as WeaponDef
		copy.fire_mode = section["mode"]
		copy.auto_reload = false
		loadout.give(copy, 0)
		_slots.append(loadout.slot_of(copy))
	_player.teleport(START, PI)
	_player.weapon.fired.connect(func(_shot: Projectile) -> void: print("SHOT %.4f" % _time))


func _physics_process(delta: float) -> void:
	_rig.orbit(Vector2(-clampf(wrapf(-_rig.yaw, -180.0, 180.0), -6.0, 6.0), 0.0))
	_rig.orbit(Vector2(0.0, clampf(PITCH - _rig.pitch, -2.0, 2.0)))
	_time += delta
	if _index >= SECTIONS.size():
		return
	if _index < 0 or _clock >= SETTLE + float(SECTIONS[_index]["seconds"]):
		_index += 1
		_clock = 0.0
		if _index >= SECTIONS.size():
			_finish()
			return
		_player.loadout.equip_now(_slots[_index])
		print("SECTION %s %.4f" % [SECTIONS[_index]["name"], _time + SETTLE])
	var section := SECTIONS[_index]
	var at := _clock - SETTLE
	var actions: Array[StringName] = [&"aim"]
	for tap: float in section.get("taps", []):
		if at >= tap - 1e-4 and at < tap + TAP - 1e-4:
			actions.append(&"fire")
	var hold: Array = section.get("hold", [])
	if not hold.is_empty() and at >= hold[0] - 1e-4 and at < hold[1] - 1e-4:
		actions.append(&"fire")
	_clock += delta
	_hold(actions)


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits.
func _finish() -> void:
	_hold([])
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()


# Holds exactly these actions down and lets go of the rest.
func _hold(actions: Array[StringName]) -> void:
	for action in _held:
		if not actions.has(action):
			Input.action_release(action)
	_held.clear()
	for action in actions:
		Input.action_press(action)
		_held.append(action)
