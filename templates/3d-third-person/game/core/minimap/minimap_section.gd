@tool
class_name MinimapSection
extends Node3D
## A box of the world the minimap treats as one place: a floor of a building, a wing of the map, a
## separate area. While the viewed target is inside it the minimap shows its `title`, slices the
## live camera to the box's height (so a roof or a floor above never covers the one below), uses
## its `map_texture` when it has one, and hides markers whose rule is `SAME_SECTION` and that
## stand somewhere else. Boxes are axis-aligned: the node's position is the box's centre and its
## rotation is ignored. Where boxes overlap the smaller one wins.

## The minimaps find sections by this group.
const GROUP := &"minimap_sections"

## The name shown on the minimap while the target is in the box.
@export var title := ""
## The box's size.
@export var size := Vector3(30.0, 8.0, 30.0):
	set(value):
		size = value.max(Vector3(0.1, 0.1, 0.1))
		_resize_preview()
## Which floor this is, bottom to top. A minimap with a floor switch uses it to order the sections.
@export_range(-10, 20, 1) var level := 0
## A top-down picture of the box (for the baked-image source), covering exactly its footprint,
## north at the top. Empty: the live camera draws it.
@export var map_texture: Texture2D


## The section that holds `point` (world place), the smallest when several do, or null.
static func at(tree: SceneTree, point: Vector3) -> MinimapSection:
	var best: MinimapSection = null
	for node in tree.get_nodes_in_group(GROUP):
		var section := node as MinimapSection
		if section != null and section.contains(point):
			if best == null or section.volume() < best.volume():
				best = section
	return best


func _enter_tree() -> void:
	add_to_group(GROUP)


func _exit_tree() -> void:
	remove_from_group(GROUP)


func _ready() -> void:
	var preview: MeshInstance3D = get_node_or_null("%Preview")
	if preview != null:
		preview.visible = Engine.is_editor_hint()
	_resize_preview()


## True when `point` is inside the box.
func contains(point: Vector3) -> bool:
	var local := point - global_position
	return (
		absf(local.x) <= size.x * 0.5
		and absf(local.y) <= size.y * 0.5
		and absf(local.z) <= size.z * 0.5
	)


## The box's footprint on the map plane, (x, z).
func footprint() -> Rect2:
	var centre := Vector2(global_position.x, global_position.z)
	var span := Vector2(size.x, size.z)
	return Rect2(centre - span * 0.5, span)


## The world height of the box's top.
func top_y() -> float:
	return global_position.y + size.y * 0.5


## The world height of the box's bottom.
func bottom_y() -> float:
	return global_position.y - size.y * 0.5


## The box's volume, to pick the smaller of two overlapping sections.
func volume() -> float:
	return size.x * size.y * size.z


func _resize_preview() -> void:
	var preview: MeshInstance3D = get_node_or_null("%Preview")
	if preview != null and preview.mesh is BoxMesh:
		(preview.mesh as BoxMesh).size = size
