class_name MinimapMarker
extends Node
## Puts its parent on the minimap. Add it as a child of any `Node3D` (a pickup, an enemy, a door, a
## goal) or `Node2D`, set the icon, colour and rule in the inspector, and every `Minimap` in the
## scene shows it: there is nothing to register and nothing to wire. A marker is data only (the
## minimap draws it from a pool of icons), so it is local to each player and never synced.
##
## 3D parents sit on the map at (x, z) with north being -Z; 2D parents at (x, y) with north being
## -Y. The icon's up is the parent's forward (-Z in 3D, the +X axis of the rotation in 2D) when
## `rotates_with_node` is on.

## What a marker needs to be shown, besides being `active`.
enum Rule {
	ALWAYS,  ## Shown wherever it is.
	SAME_SECTION,  ## Shown only while the viewed target is in the same `MinimapSection`.
	NEAR,  ## Shown only within `near_distance` metres of the viewed target.
	FLAGGED,  ## Shown only while `revealed` is on (the game decides: scanned, spotted, found).
}

## The minimaps find markers by this group.
const GROUP := &"minimap_markers"

@export_group("Look")
## The icon, tinted by `color`. Empty uses the minimap's default dot.
@export var icon: Texture2D
## The icon's tint.
@export var color := Color(1.0, 1.0, 1.0, 1.0)
## The icon's size on a minimap at its normal scale.
@export_range(4.0, 96.0, 1.0, "suffix:px") var size := 14.0
## On: the icon turns with the parent's forward (an arrow for a character). Off: it points up.
@export var rotates_with_node := false
## What this marker is (`enemy`, `pickup`, `goal`...). A minimap can hide whole kinds.
@export var kind: StringName = &""
## Higher is drawn on top of lower.
@export_range(-10, 10, 1) var draw_order := 0

@export_group("Edge")
## On: a marker off the map sticks to its border and points toward the thing. Off: it hides.
@export var clamp_to_edge := false
## How far inside the border a clamped marker sits.
@export_range(0.0, 40.0, 1.0, "suffix:px") var edge_inset := 6.0
## The icon of a clamped marker, turned to point outward. Empty uses the minimap's arrow.
@export var edge_icon: Texture2D

@export_group("Show")
## Off hides the marker everywhere without removing it.
@export var active := true
## The rule that decides when it is shown.
@export var rule := Rule.ALWAYS
## For `NEAR`: the distance in metres.
@export_range(1.0, 500.0, 1.0, "suffix:m") var near_distance := 30.0
## For `FLAGGED`: the game turns this on (a scan, a pickup in sight) and off.
@export var revealed := false
## Fade the icon as the thing sits above or below the viewed target: 0 off, else the height
## in metres at which it is almost gone.
@export_range(0.0, 50.0, 0.5, "suffix:m") var height_fade := 0.0


func _enter_tree() -> void:
	add_to_group(GROUP)


func _exit_tree() -> void:
	remove_from_group(GROUP)


## The node the marker stands for: its parent.
func target() -> Node:
	return get_parent()


## Where the target is on the map plane: (x, z) in 3D, (x, y) in 2D. Zero when it has no place.
func plane_position() -> Vector2:
	var parent := get_parent()
	if parent is Node3D:
		var at: Vector3 = (parent as Node3D).global_position
		return Vector2(at.x, at.z)
	if parent is Node2D:
		return (parent as Node2D).global_position
	return Vector2.ZERO


## The target's height (y in 3D, 0 in 2D).
func height() -> float:
	var parent := get_parent()
	if parent is Node3D:
		return (parent as Node3D).global_position.y
	return 0.0


## The target's place in 3D (the map plane lifted to its height), for the section test.
func position_3d() -> Vector3:
	var at := plane_position()
	return Vector3(at.x, height(), at.y)


## The target's forward on the map plane, as a unit vector. A parent with a
## `get_minimap_heading() -> Vector2` method answers for itself (the player's body turns inside
## its node).
func heading() -> Vector2:
	var parent := get_parent()
	if parent != null and parent.has_method(&"get_minimap_heading"):
		return parent.call(&"get_minimap_heading")
	if parent is Node3D:
		var forward := -(parent as Node3D).global_basis.z
		var flat := Vector2(forward.x, forward.z)
		return flat.normalized() if flat.length_squared() > 0.000001 else Vector2(0.0, -1.0)
	if parent is Node2D:
		return Vector2.RIGHT.rotated((parent as Node2D).global_rotation)
	return Vector2(0.0, -1.0)


## True when the rule lets the marker show to a viewer at `viewer_plane` (and `viewer_section`).
func passes_rule(viewer_plane: Vector2, viewer_section: MinimapSection) -> bool:
	match rule:
		Rule.SAME_SECTION:
			return MinimapSection.at(get_tree(), position_3d()) == viewer_section
		Rule.NEAR:
			return plane_position().distance_to(viewer_plane) <= near_distance
		Rule.FLAGGED:
			return revealed
	return true
