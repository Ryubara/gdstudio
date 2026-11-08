@tool
class_name CameraZone
extends Node
## Hands the view to another Phantom Camera while something stands in a `TriggerZone`, and back
## when it leaves. The host picks the camera with the highest `priority`, so this only raises
## the zone's camera above the follow camera (and lowers it again): the blend between them is
## the camera's own tween (`PhantomCamera3D.tween_resource`: duration, transition, ease), set on
## the camera.

## The view changed to the zone's camera (true) or back (false).
signal view_changed(zone_view: bool)

@export_group("Zone")
## The trigger that decides when the view changes.
@export var zone: TriggerZone:
	set(value):
		zone = value
		update_configuration_warnings()
## The camera that takes the view while the zone is occupied.
@export var camera: PhantomCamera3D:
	set(value):
		camera = value
		update_configuration_warnings()

@export_group("Priority")
## The camera's priority while the zone is occupied: higher than the follow camera's.
@export_range(0, 100, 1) var priority_inside := 20
## The camera's priority the rest of the time.
@export_range(0, 100, 1) var priority_outside := 0:
	set(value):
		priority_outside = value
		if camera != null and not _occupied and not Engine.is_editor_hint():
			camera.priority = priority_outside

var _occupied := false


func _ready() -> void:
	if Engine.is_editor_hint() or zone == null or camera == null:
		return
	camera.priority = priority_outside
	zone.activated.connect(_on_activated)
	zone.deactivated.connect(_on_deactivated)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if zone == null:
		warnings.append("Set `zone`: the TriggerZone that decides when the view changes.")
	if camera == null:
		warnings.append("Set `camera`: the PhantomCamera3D that takes the view.")
	return warnings


func _on_activated(_body: Node3D) -> void:
	_occupied = true
	camera.priority = priority_inside
	view_changed.emit(true)


func _on_deactivated() -> void:
	_occupied = false
	camera.priority = priority_outside
	view_changed.emit(false)
