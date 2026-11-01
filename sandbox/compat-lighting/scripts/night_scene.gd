class_name NightScene
extends RefCounted
## Builds the spike's night drive-in lot. Deterministic: the same node names and paths every time,
## because a baked lightmap finds its meshes by node path.

const LOT_SIZE := 60.0
const SCREEN_POS := Vector3(0.0, 6.5, -26.0)
const SCREEN_SIZE := Vector3(18.0, 8.0, 0.5)
const CAR_COLORS: Array[Color] = [
	Color(0.55, 0.08, 0.08), Color(0.1, 0.25, 0.5), Color(0.75, 0.7, 0.55),
	Color(0.12, 0.4, 0.2), Color(0.5, 0.5, 0.52), Color(0.6, 0.35, 0.1),
]
const LAMP_POS := Vector3(9.0, 0.0, -2.0)
const NEON_POS := Vector3(-14.0, 3.5, -10.0)


## Builds the lot under a new Node3D named "World". `ground_tiles` splits the ground into
## tiles x tiles meshes (Compatibility lights each mesh with at most 8 lights).
## `static_lights` makes the three base lights bake-only (the lightmap carries them).
static func build(ground_tiles: int, static_lights: bool) -> Node3D:
	var world := Node3D.new()
	world.name = "World"
	_add_ground(world, ground_tiles)
	_add_screen(world)
	_add_cars(world)
	_add_lamp(world, static_lights)
	_add_neon(world, static_lights)
	_add_screen_light(world, static_lights)
	return world


static func make_box(parent: Node, node_name: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.add_uv2 = true
	return _mesh_node(parent, node_name, mesh, pos, mat)


static func _mesh_node(parent: Node, node_name: String, mesh: PrimitiveMesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	node.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	parent.add_child(node)
	return node


static func _lit(color: Color, rough := 0.85) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	return mat


static func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color * 0.2
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat


static func _add_ground(world: Node3D, tiles: int) -> void:
	var tile_size := LOT_SIZE / float(tiles)
	var mat := _lit(Color(0.22, 0.22, 0.25), 0.6)
	for ix in tiles:
		for iz in tiles:
			var mesh := PlaneMesh.new()
			mesh.size = Vector2(tile_size, tile_size)
			mesh.add_uv2 = true
			var pos := Vector3(
				-LOT_SIZE * 0.5 + tile_size * (ix + 0.5), 0.0, -LOT_SIZE * 0.5 + tile_size * (iz + 0.5))
			_mesh_node(world, "Ground_%d_%d" % [ix, iz], mesh, pos, mat)


static func _add_screen(world: Node3D) -> void:
	var tex := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0.9, 0.55, 0.9), Color(0.35, 0.8, 1.0)])
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 1)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.1, 0.1)
	mat.emission_enabled = true
	mat.emission_texture = tex
	mat.emission_energy_multiplier = 0.9
	make_box(world, "Screen", SCREEN_SIZE, SCREEN_POS, mat)
	var post_mat := _lit(Color(0.05, 0.05, 0.06))
	make_box(world, "ScreenPostL", Vector3(0.6, 3.0, 0.6), SCREEN_POS + Vector3(-5.0, -5.5, 0.0), post_mat)
	make_box(world, "ScreenPostR", Vector3(0.6, 3.0, 0.6), SCREEN_POS + Vector3(5.0, -5.5, 0.0), post_mat)


static func _add_cars(world: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var index := 0
	for row in 3:
		for col in 5:
			var color := CAR_COLORS[rng.randi() % CAR_COLORS.size()]
			var pos := Vector3(-16.0 + col * 8.0 + rng.randf_range(-1.0, 1.0), 0.0, -14.0 + row * 9.0)
			var car := Node3D.new()
			car.name = "Car%d" % index
			car.position = pos
			car.rotation.y = rng.randf_range(-0.12, 0.12)
			world.add_child(car)
			var mat := _lit(color, 0.35)
			make_box(car, "Body", Vector3(2.0, 0.8, 4.2), Vector3(0.0, 0.7, 0.0), mat)
			make_box(car, "Cabin", Vector3(1.7, 0.7, 2.0), Vector3(0.0, 1.4, 0.3), _lit(color * 0.6, 0.2))
			if index % 4 == 0:  # tail lights on some cars
				make_box(car, "Tail", Vector3(1.6, 0.15, 0.1), Vector3(0.0, 0.8, 2.12), _glow(Color(1, 0.05, 0.05), 3.0))
			index += 1


static func _add_lamp(world: Node3D, static_light: bool) -> void:
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.1
	pole_mesh.bottom_radius = 0.14
	pole_mesh.height = 6.0
	pole_mesh.add_uv2 = true
	_mesh_node(world, "LampPole", pole_mesh, LAMP_POS + Vector3(0, 3.0, 0), _lit(Color(0.1, 0.1, 0.1)))
	var bulb := SphereMesh.new()
	bulb.radius = 0.3
	bulb.height = 0.6
	bulb.add_uv2 = true
	_mesh_node(world, "LampBulb", bulb, LAMP_POS + Vector3(0, 6.2, 0), _glow(Color(1.0, 0.7, 0.35), 6.0))
	var light := OmniLight3D.new()
	light.name = "LampLight"
	light.position = LAMP_POS + Vector3(0, 6.0, 0)
	light.light_color = Color(1.0, 0.72, 0.4)
	light.light_energy = 4.0
	light.omni_range = 16.0
	light.light_bake_mode = Light3D.BAKE_STATIC if static_light else Light3D.BAKE_DYNAMIC
	world.add_child(light)


static func _add_neon(world: Node3D, static_light: bool) -> void:
	make_box(world, "NeonSign", Vector3(5.0, 0.5, 0.2), NEON_POS, _glow(Color(1.0, 0.1, 0.6), 5.0))
	make_box(world, "NeonPostL", Vector3(0.2, 3.5, 0.2), NEON_POS + Vector3(-2.2, -1.75, 0), _lit(Color(0.1, 0.1, 0.1)))
	make_box(world, "NeonPostR", Vector3(0.2, 3.5, 0.2), NEON_POS + Vector3(2.2, -1.75, 0), _lit(Color(0.1, 0.1, 0.1)))
	var light := OmniLight3D.new()
	light.name = "NeonLight"
	light.position = NEON_POS + Vector3(0, 0, 1.0)
	light.light_color = Color(1.0, 0.15, 0.6)
	light.light_energy = 4.0
	light.omni_range = 12.0
	light.light_bake_mode = Light3D.BAKE_STATIC if static_light else Light3D.BAKE_DYNAMIC
	world.add_child(light)


static func _add_screen_light(world: Node3D, static_light: bool) -> void:
	var light := OmniLight3D.new()
	light.name = "ScreenLight"
	light.position = SCREEN_POS + Vector3(0, -2.0, 4.0)
	light.light_color = Color(0.6, 0.7, 1.0)
	light.light_energy = 5.0
	light.omni_range = 34.0
	light.light_bake_mode = Light3D.BAKE_STATIC if static_light else Light3D.BAKE_DYNAMIC
	world.add_child(light)
