@tool
class_name SpawnPoint
extends Marker3D
## Where something starts: a player, a team, a wave of enemies. The node's forward direction
## (its -Z, the blue arrow in the editor) is the way the spawned thing faces. Put several in one
## group and ask `SpawnPoint.pick()` for one, or read `spawn_transform()` from one you chose
## yourself. In the game the marker is invisible unless `show_in_game`.

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

var _marker: MeshInstance3D


func _ready() -> void:
	add_to_group(_group_name(spawn_group))
	_update_marker()


## The group a `spawn_group` name is stored under in the scene tree.
static func _group_name(spawn_group_name: StringName) -> StringName:
	return StringName("spawn_%s" % spawn_group_name)


## Picks an enabled point of `group_name` at random, or null when there is none.
static func pick(tree: SceneTree, group_name: StringName, rng: RandomNumberGenerator) -> SpawnPoint:
	var free: Array[SpawnPoint] = []
	for node in tree.get_nodes_in_group(_group_name(group_name)):
		var point := node as SpawnPoint
		if point != null and point.enabled:
			free.append(point)
	if free.is_empty():
		return null
	return free[rng.randi_range(0, free.size() - 1)]


## Where and how to spawn: the point's transform, moved to a random spot inside `radius` when it
## has one.
func spawn_transform(rng: RandomNumberGenerator) -> Transform3D:
	var result := global_transform
	if radius > 0.0:
		var angle := rng.randf() * TAU
		var distance := radius * sqrt(rng.randf())
		result.origin += Vector3(cos(angle), 0.0, sin(angle)) * distance
	return result


func _update_marker() -> void:
	var wanted := Engine.is_editor_hint() or show_in_game
	if not wanted:
		if _marker != null:
			_marker.queue_free()
			_marker = null
		return
	if _marker != null:
		return
	_marker = MeshInstance3D.new()
	_marker.name = "Marker"
	var arrow := PrismMesh.new()
	arrow.size = Vector3(0.6, 0.6, 0.1)
	_marker.mesh = arrow
	_marker.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_marker.position = Vector3(0.0, 0.05, -0.3)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.2, 0.55, 1.0)
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker.material_override = paint
	add_child(_marker)
