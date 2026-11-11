## Holds fire with the pistol, lets go, puts the pistol away for the fists and holds fire again:
## the pistol's fire zooms the view in (its `fire_zooms` is on), the fists punch with the view
## left as it is (their `fire_zooms` is off). A label names the weapon and shows the field of view
## and the distance; every physics frame prints them (the line starts with `FIREZOOM`). It presses
## the same actions a player does.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --seconds 6 --fps 30 --name fire-zoom`
## with `--scene res://tools/capture/fire_zoom_tour.tscn`.
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## An open spot of the sample map, looking north (-Z).
const SPOT := Vector3(4.0, 0.0, 18.0)
## When each step starts, in seconds: pistol fire, let go, switch to the fists, fist fire, let go,
## the end.
const PISTOL_FIRE := 0.4
const PISTOL_LET_GO := 1.8
const SWITCH := 2.5
const FISTS_FIRE := 3.3
const FISTS_LET_GO := 4.7
const END := 5.6

var _clock := 0.0
var _label: Label
var _weapon_name := ""

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	_player.teleport(SPOT, 0.0)
	_rig.yaw = 0.0
	_rig.pitch = 6.0
	var layer := CanvasLayer.new()
	layer.layer = 50
	_label = Label.new()
	_label.position = Vector2(24.0, 24.0)
	_label.add_theme_font_size_override(&"font_size", 26)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 6)
	layer.add_child(_label)
	add_child(layer)
	_weapon_name = _player.weapon.definition.display_name
	_player.loadout.weapon_changed.connect(_on_weapon_changed)


func _physics_process(delta: float) -> void:
	var before := _clock
	_clock += delta
	if _crossed(before, PISTOL_FIRE) or _crossed(before, FISTS_FIRE):
		Input.action_press(&"fire")
	if _crossed(before, PISTOL_LET_GO) or _crossed(before, FISTS_LET_GO):
		Input.action_release(&"fire")
	if _crossed(before, SWITCH):
		Input.action_press(&"toggle_unarmed")
	if _crossed(before, SWITCH + 0.1):
		Input.action_release(&"toggle_unarmed")
	if _crossed(before, END):
		_finish()
		return
	var fire := "held" if Input.is_action_pressed(&"fire") else "up"
	print(
		"FIREZOOM t ",
		snappedf(_clock, 0.01),
		" weapon ",
		_weapon_name,
		" fire ",
		fire,
		" fov ",
		snappedf(_rig.current_fov(), 0.01),
		" distance ",
		snappedf(_rig.current_distance(), 0.01)
	)
	_label.text = (
		"%s, fire %s\nfield of view %.1f deg   distance %.2f m"
		% [_weapon_name, fire, _rig.current_fov(), _rig.current_distance()]
	)


func _on_weapon_changed(definition: WeaponDef) -> void:
	_weapon_name = definition.display_name


func _crossed(before: float, at: float) -> bool:
	return before < at and _clock >= at


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits
# (a voice still playing at exit is reported as a leak).
func _finish() -> void:
	set_physics_process(false)
	Input.action_release(&"fire")
	AudioSettings.stop_players(get_tree().root)
	for _frame_count in 8:
		await get_tree().process_frame
	get_tree().quit()
