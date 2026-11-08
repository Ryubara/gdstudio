@tool
class_name ProtoBlock
extends MeshInstance3D
## A solid piece of the prototype level: its mesh and its collision come from one size, so
## resizing it in the inspector keeps both in step, and the grid material keeps its 1 m cells at any
## size.
##
## The block is the mesh itself (a lightmap only bakes meshes that belong to the scene, not ones a
## script adds under them) and keeps its collision in a `StaticBody3D` child. The mesh carries a
## second UV set (UV2), which a lightmap needs. Only the editor can unwrap UV2 (an exported game has
## no unwrapper), so the editor builds the mesh and the scene saves it; a running game uses the
## saved mesh and builds only the collision. Bake the level again after moving or resizing a block
## (select the level's `LightmapGI` node and press "Bake Lightmaps", with the Forward+ renderer).

enum Kind {
	BOX,  ## A cuboid: floors, walls, crates, platforms.
	CYLINDER,  ## A round pillar standing on the ground.
	RAMP,  ## A wedge that rises toward +X (turn the block to face it elsewhere).
	STAIRS,  ## Steps that rise toward +X, one box a step.
}

## UV2 texel size in metres: a smaller number gives a sharper (and larger) lightmap for this block.
const LIGHTMAP_TEXEL_M := 0.5
const MIN_SIZE_M := 0.25

@export_group("Shape")
## What the block is.
@export var kind: Kind = Kind.BOX:
	set(value):
		kind = value
		_rebuild()
## Width (x), height (y) and depth (z) in metres. A cylinder uses x as its diameter and y as its
## height.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var size := Vector3(2.0, 2.0, 2.0):
	set(value):
		size = value.max(Vector3.ONE * MIN_SIZE_M)
		_rebuild()
## How many steps a STAIRS block has (the rise of a step is the height over this).
@export_range(2, 40, 1) var steps := 8:
	set(value):
		steps = value
		_rebuild()

@export_group("Surface")
## The material on every face. The prototype grid materials are in `assets/materials/prototype/`.
@export var material: Material:
	set(value):
		material = value
		material_override = value

var _body: StaticBody3D


func _init() -> void:
	_body = StaticBody3D.new()
	_body.name = "Body"
	add_child(_body)


func _ready() -> void:
	material_override = material
	_rebuild_collision()
	if mesh == null:
		mesh = _build_mesh()


## The mesh is saved with the scene (it carries the lightmap's UV2) but not shown in the inspector;
## the material comes from `material`, so it is not saved.
func _validate_property(property: Dictionary) -> void:
	if property.name == "mesh":
		property.usage = PROPERTY_USAGE_STORAGE
	elif property.name == "material_override":
		property.usage = PROPERTY_USAGE_NONE


## A shape property changed in the editor or in code: make both again.
func _rebuild() -> void:
	if not is_node_ready():
		return
	mesh = _build_mesh()
	_rebuild_collision()


func _rebuild_collision() -> void:
	for old in _body.get_children():
		_body.remove_child(old)
		old.queue_free()
	for entry in _build_shapes():
		var collision := CollisionShape3D.new()
		collision.shape = entry[0]
		collision.transform = entry[1]
		_body.add_child(collision)


## The mesh, with UV2 for a lightmap.
func _build_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		Kind.BOX:
			var box := BoxMesh.new()
			box.size = size
			tool.append_from(box, 0, Transform3D.IDENTITY)
		Kind.CYLINDER:
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = size.x / 2.0
			cylinder.bottom_radius = size.x / 2.0
			cylinder.height = size.y
			cylinder.radial_segments = 24
			cylinder.rings = 1
			tool.append_from(cylinder, 0, Transform3D.IDENTITY)
		Kind.RAMP:
			var wedge := PrismMesh.new()
			wedge.left_to_right = 1.0
			wedge.size = size
			tool.append_from(wedge, 0, Transform3D.IDENTITY)
		Kind.STAIRS:
			for step in _stair_boxes():
				var box := BoxMesh.new()
				box.size = step["size"]
				tool.append_from(box, 0, Transform3D(Basis.IDENTITY, step["position"]))
	var built := tool.commit()
	if Engine.is_editor_hint():
		built.lightmap_unwrap(Transform3D.IDENTITY, LIGHTMAP_TEXEL_M)
	return built


## Collision as an array of [Shape3D, Transform3D].
func _build_shapes() -> Array:
	var shapes: Array = []
	match kind:
		Kind.BOX:
			var box := BoxShape3D.new()
			box.size = size
			shapes.append([box, Transform3D.IDENTITY])
		Kind.CYLINDER:
			var cylinder := CylinderShape3D.new()
			cylinder.radius = size.x / 2.0
			cylinder.height = size.y
			shapes.append([cylinder, Transform3D.IDENTITY])
		Kind.RAMP:
			var half := size / 2.0
			var hull := ConvexPolygonShape3D.new()
			hull.points = PackedVector3Array(
				[
					Vector3(-half.x, -half.y, -half.z),
					Vector3(-half.x, -half.y, half.z),
					Vector3(half.x, -half.y, -half.z),
					Vector3(half.x, -half.y, half.z),
					Vector3(half.x, half.y, -half.z),
					Vector3(half.x, half.y, half.z),
				]
			)
			shapes.append([hull, Transform3D.IDENTITY])
		Kind.STAIRS:
			for step in _stair_boxes():
				var box := BoxShape3D.new()
				box.size = step["size"]
				shapes.append([box, Transform3D(Basis.IDENTITY, step["position"])])
	return shapes


## The boxes of a staircase: each is as tall as its step's top above the floor, so there is no gap
## under a step.
func _stair_boxes() -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	var run := size.x / steps
	for step in steps:
		var height := size.y * (step + 1) / steps
		var centre := Vector3(-size.x / 2.0 + run * (step + 0.5), -size.y / 2.0 + height / 2.0, 0.0)
		boxes.append({"position": centre, "size": Vector3(run, height, size.z)})
	return boxes
