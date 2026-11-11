class_name NearHitShake
extends Node
## Shakes this rig's camera when a hit lands near it (gdstudio #1068): a round that strikes the
## wall beside the player, a hit on a body next to them, a hit on the player. It sits on the camera
## rig (`ui/player_rig/player_rig.tscn`, under `PlayerCamera`) and plays `preset` on the rig's
## `CameraShake` at the hit's point, so the shake fades with the distance from this camera to the
## hit and is gone past the preset's `radius`. The global `CameraShake.strength` (the player's
## camera shake setting) scales it, and 0 turns it off.
##
## Offline, every hit the level's `Impacts` plays reaches it through `Impacts.impact_made`. Online,
## `ClientCombat` plays each HIT the server sends through the same `Impacts` (and, when this screen
## finds no surface at the point, calls `play_near` itself), so every peer shakes its own camera
## from the event it already has. Nothing here is sent over a network.

## The group every near-hit shake joins, so `play_near` finds the ones in a viewport.
const GROUP := &"near_hit_shake"

## Off: no hit shakes this camera.
@export var enabled := true
## The shake a hit plays: its trauma, length, motion and `radius` (how far from the camera a hit
## is still felt, fading to nothing at the edge) are on the preset.
@export var preset: ShakePreset
## How much of the preset's trauma a hit adds, on top of the player's shake setting.
@export_range(0.0, 2.0, 0.05) var strength := 1.0
## The shake component of the camera it shakes. Empty takes the parent's `shaker` (a
## `PlayerCamera`), else a `CameraShake` among the siblings.
@export var shaker: CameraShake
## The level's impacts it listens to. Empty finds the one in its viewport when the level is ready.
@export var impacts: Impacts

var _listening_to: Impacts


## Plays a near hit at `point` on every near-hit shake drawn in the same viewport as `from`.
static func play_near(from: Node, point: Vector3) -> void:
	if from == null or not from.is_inside_tree():
		return
	var viewport := from.get_viewport()
	for node in from.get_tree().get_nodes_in_group(GROUP):
		var shake := node as NearHitShake
		if shake != null and shake.get_viewport() == viewport:
			shake.play(point)


func _enter_tree() -> void:
	add_to_group(GROUP)


func _exit_tree() -> void:
	remove_from_group(GROUP)
	_disconnect()


func _ready() -> void:
	# The level may be added after the rig: look for its impacts once both are in.
	_listen.call_deferred()


## Shakes this camera for a hit at the world point `point` (faded by its distance to the camera).
func play(point: Vector3) -> void:
	var target := _shaker()
	if not enabled or preset == null or target == null:
		return
	target.add(preset, point, strength)


## The impacts it listens to now (null before the level is in).
func listening_to() -> Impacts:
	return _listening_to


func _listen() -> void:
	var found := impacts if impacts != null else Impacts.find(self)
	if found == _listening_to:
		return
	_disconnect()
	_listening_to = found
	if found != null:
		found.impact_made.connect(_on_impact)


func _disconnect() -> void:
	if is_instance_valid(_listening_to) and _listening_to.impact_made.is_connected(_on_impact):
		_listening_to.impact_made.disconnect(_on_impact)
	_listening_to = null


func _on_impact(
	_surface: ImpactSurface, _collider: Object, point: Vector3, _normal: Vector3
) -> void:
	play(point)


func _shaker() -> CameraShake:
	if shaker != null:
		return shaker
	var parent := get_parent()
	if parent == null:
		return null
	var from_parent: Variant = parent.get(&"shaker")
	if from_parent is CameraShake:
		return from_parent
	for sibling in parent.get_children():
		if sibling is CameraShake:
			return sibling
	return null
