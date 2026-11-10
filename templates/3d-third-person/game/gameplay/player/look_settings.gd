@tool
class_name LookSettings
extends Node
## Carries the player's look options (mouse sensitivity, invert Y) from the `Settings` autoload to
## the camera rig: it sets `player_sensitivity` and `player_invert_y` at start and whenever the
## player changes them, so the rig's own `mouse_sensitivity` and `invert_y` stay the designer's.
## Without a `Settings` autoload (a scene opened on its own) it does nothing.

@export_group("Nodes")
## The camera rig the options reach.
@export var camera: PlayerCamera


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var settings := _settings()
	if settings == null:
		return
	settings.changed.connect(_on_changed)
	apply()


## Reads both options and puts them on the camera rig.
func apply() -> void:
	var settings := _settings()
	if settings == null or camera == null:
		return
	camera.player_sensitivity = float(settings.get_value(SettingsService.MOUSE_SENSITIVITY))
	camera.player_invert_y = bool(settings.get_value(SettingsService.INVERT_Y))


func _on_changed(key: StringName, _value: Variant) -> void:
	if key == SettingsService.MOUSE_SENSITIVITY or key == SettingsService.INVERT_Y:
		apply()


func _settings() -> SettingsService:
	return get_node_or_null("/root/Settings") as SettingsService


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if camera == null:
		warnings.append("Set `camera`: the PlayerCamera rig that turns the view.")
	return warnings
