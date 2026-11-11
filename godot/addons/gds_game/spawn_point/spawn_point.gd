@tool
class_name SpawnPoint
extends Marker3D
## Where something starts: a player, a team, a wave of enemies. The node's forward direction
## (its -Z, the blue arrow in the editor) is the way the spawned thing faces. Put several in one
## group and ask `SpawnPoint.pick()` for one, or read `spawn_transform()` from one you chose
## yourself. The blue arrow is the point's `%Marker` child (a `MeshInstance3D` in the scene that
## carries this script, 3D Third Person's `spawn_point.tscn`): the editor shows it, and in the game
## it is hidden unless `show_in_game`.

@export_group("Spawn")
## Points with the same group name belong together (`player`, `red_team`, `wave_1`).
@export var spawn_group: StringName = &"player":
	set(value):
		if is_inside_tree() and spawn_group != &"":
			remove_from_group(_group_name(spawn_group))
		spawn_group = value
		if is_inside_tree():
			add_to_group(_group_name(spawn_group))
## Spawn anywhere inside this circle around the point. Zero spawns exactly on the point.
@export_range(0.0, 20.0, 0.1, "or_greater", "suffix:m") var radius := 0.0
## Whether the point is free to use. A level can switch points off and on.
@export var enabled := true

@export_group("Look")
## Shows the marker while the game runs (the editor always shows it).
@export var show_in_game := false:
	set(value):
		show_in_game = value
		_update_marker()

## The physics frame this point was last picked on (see `pick()`).
var _taken_frame := -1


func _ready() -> void:
	add_to_group(_group_name(spawn_group))
	_update_marker()


## The group a `spawn_group` name is stored under in the scene tree.
static func _group_name(spawn_group_name: StringName) -> StringName:
	return StringName("spawn_%s" % spawn_group_name)


## Picks an enabled point of `group_name` at random, or null when there is none. A point picked
## earlier in this physics frame is passed over while another is free, so two characters that
## start together do not stand on one point; with none left free the pick repeats one.
static func pick(tree: SceneTree, group_name: StringName, rng: RandomNumberGenerator) -> SpawnPoint:
	var frame := Engine.get_physics_frames()
	var free: Array[SpawnPoint] = []
	var all: Array[SpawnPoint] = []
	for node in tree.get_nodes_in_group(_group_name(group_name)):
		var point := node as SpawnPoint
		if point != null and point.enabled:
			all.append(point)
			if point._taken_frame != frame:
				free.append(point)
	if all.is_empty():
		return null
	var pool := free if not free.is_empty() else all
	var chosen := pool[rng.randi_range(0, pool.size() - 1)]
	chosen._taken_frame = frame
	return chosen


## Where and how to spawn: the point's transform, moved to a random spot inside `radius` when it
## has one.
func spawn_transform(rng: RandomNumberGenerator) -> Transform3D:
	var result := global_transform
	if radius > 0.0:
		var angle := rng.randf() * TAU
		var distance := radius * sqrt(rng.randf())
		result.origin += Vector3(cos(angle), 0.0, sin(angle)) * distance
	return result


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if _marker() == null:
		warnings.append(
			"The scene needs a `Marker` (MeshInstance3D): the arrow that shows the facing."
		)
	return warnings


func _marker() -> MeshInstance3D:
	return get_node_or_null("%Marker") as MeshInstance3D


# The arrow is always there in the editor and shows in the game only on request.
func _update_marker() -> void:
	var marker := _marker()
	if marker != null:
		marker.visible = Engine.is_editor_hint() or show_in_game
