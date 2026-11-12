extends Node3D
## Finds what draws lines along a limb (kit docs: tools/blender/realistic-characters.md#limb-lines): one close view
## of her left arm, the same frame once per variant of the body skin's material, each saved as a PNG that
## `tools/limb_lines.py` turns into one number (the fine-scale contrast inside the arm).
##
##   gds godot -- --path <project> res://diag.tscn -- --out=<folder> [--pose=idle|rest]
##
## The variants switch off one suspect at a time: the normal map, its GPU compression, the coat, subsurface
## scattering, the roughness map. The material here is the plain StandardMaterial3D the first build shipped, so
## the numbers compare an asset with itself and not with a later shader.

const ASSET := "res://asset/"
const VARIANTS: Array[String] = [
	"shipped", "no_normal_map", "normal_uncompressed", "no_coat", "no_coat_no_normal", "no_sss", "rough_flat",
	"grey_no_maps",
]

var _character: Node3D
var _skin: MeshInstance3D
var _surface := 1


func _ready() -> void:
	var out := "user://"
	var pose := "idle"
	var what := "limb"
	var light := "day"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		if a.begins_with("--what="):
			what = a.trim_prefix("--what=")
		if a.begins_with("--light="):
			light = a.trim_prefix("--light=")
		if a.begins_with("--pose="):
			pose = a.trim_prefix("--pose=")
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.42, 0.6, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.68, 1.0)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.8
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.shadow_enabled = true
	add_child(sun)
	sun.rotation_degrees = Vector3(-38.0, 38.0, 0.0)
	_character = (load(ASSET + "heroine.glb") as PackedScene).instantiate()
	add_child(_character)
	var skeleton: Skeleton3D = _character.find_children("*", "Skeleton3D", true, false)[0]
	for node in _character.find_children("*", "MeshInstance3D", true, false):
		if String(node.name).begins_with("skin"):
			_skin = node
		elif what == "limb":
			(node as MeshInstance3D).visible = false
	if pose == "idle":
		# The arm hanging at her side, as the library's idle holds it: both arm bones turned down by hand.
		for side: String in ["l", "r"]:
			var b := skeleton.find_bone("upperarm_" + side)
			var sx := 1.0 if side == "l" else -1.0
			var rest := skeleton.get_bone_global_rest(b)
			var turn := Basis(Vector3(0, 0, 1), deg_to_rad(-72.0 * sx))
			var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(b))
			skeleton.set_bone_pose_rotation(b, (parent.basis.inverse() * turn * rest.basis).get_rotation_quaternion())
	await get_tree().process_frame
	var hand := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hand_l")).origin
	var shoulder := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("upperarm_l")).origin
	var mid := (hand + shoulder) * 0.5
	var camera := Camera3D.new()
	add_child(camera)
	camera.fov = 22.0
	camera.position = mid + Vector3(0.55, 0.1, 1.05)
	camera.look_at(mid)
	camera.current = true
	var tag := "compat" if RenderingServer.get_current_rendering_method() == "gl_compatibility" else "forward"
	if what == "shine":
		await _shine(out, tag, env, camera, sun, light)
		get_tree().quit()
		return
	for v in VARIANTS:
		_skin.set_surface_override_material(_surface, _material(v))
		_skin.set_surface_override_material(0, _material(v))
		for i in 20:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/diag_%s_%s_%s.png" % [out, tag, pose, v])
	get_tree().quit()


func _tex(name: String) -> Texture2D:
	return load(ASSET + name + ".png")


func _material(variant: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if variant == "grey_no_maps":
		m.albedo_color = Color(0.5, 0.5, 0.5)
		m.roughness = 0.35
		return m
	m.albedo_texture = _tex("body_albedo")
	var orm := _tex("body_orm")
	m.ao_enabled = true
	m.ao_texture = orm
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	if variant == "rough_flat":
		m.roughness = 0.5
	else:
		m.roughness_texture = orm
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	if variant not in ["no_normal_map", "no_coat_no_normal"]:
		m.normal_enabled = true
		if variant == "normal_uncompressed":
			var img := Image.load_from_file(ProjectSettings.globalize_path(ASSET + "body_normal.png"))
			img.generate_mipmaps()
			m.normal_texture = ImageTexture.create_from_image(img)
		else:
			m.normal_texture = _tex("body_normal")
	if variant != "no_sss":
		m.subsurf_scatter_enabled = true
		m.subsurf_scatter_strength = 0.18
		m.subsurf_scatter_skin_mode = true
		m.subsurf_scatter_texture = _tex("body_mask")
	if variant not in ["no_coat", "no_coat_no_normal"]:
		m.clearcoat_enabled = true
		m.clearcoat = 0.22
		m.clearcoat_roughness = 0.16
		m.clearcoat_texture = _tex("body_coat")
	return m


## What makes her shine (kit docs: tools/blender/realistic-characters.md#shine): the bust in daylight, the whole
## character in the first build's materials, one suspect switched off per capture. `shine.py` counts the pixels
## of the character that a highlight has pushed near white.
const SHINE: Array[String] = ["shipped", "no_coat", "skin_rough_070", "specular_0", "no_env_reflection", "all_off"]


func _shine(out: String, tag: String, env: Environment, camera: Camera3D, sun: DirectionalLight3D, light: String) -> void:
	camera.position = Vector3(0.42, 1.30, 1.18)
	camera.look_at(Vector3(0.0, 1.37, 0.0))
	camera.fov = 39.6
	if light == "warm":
		# The warm interior of the captures: two spots, almost no ambient light. Highlights show most here.
		sun.visible = false
		env.background_color = Color(0.07, 0.032, 0.013)
		env.ambient_light_color = Color(1.0, 0.6, 0.35)
		env.ambient_light_energy = 0.1
		for spot: Array in [[Vector3(-1.05, 1.95, 1.25), 8.0, Color(1.0, 0.60, 0.30)], [Vector3(1.25, 1.95, -1.15), 10.0, Color(1.0, 0.68, 0.36)]]:
			var l := SpotLight3D.new()
			l.position = spot[0]
			l.light_energy = spot[1]
			l.light_color = spot[2]
			l.spot_range = 9.0
			l.spot_angle = 35.0
			l.shadow_enabled = true
			add_child(l)
			l.look_at(Vector3(0.0, 1.5, 0.03))
	for v in SHINE:
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED if v in ["no_env_reflection", "all_off"] else Environment.REFLECTION_SOURCE_BG
		for node in _character.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			var n := String(mi.name)
			for s in mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, _first_build(n, s, v))
		for i in 20:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/shine_%s_%s_%s.png" % [out, tag, light, v])


## The first build's material for a mesh's surface, with one suspect of the shine switched off.
func _first_build(mesh: String, surface: int, variant: String) -> Material:
	var flat := variant in ["specular_0", "all_off"]
	var key := mesh.get_slice("_", 0)
	if key == "skin":
		var set_name := "head" if surface == 0 else "body"
		var m := StandardMaterial3D.new()
		m.albedo_texture = _tex(set_name + "_albedo")
		m.normal_enabled = true
		m.normal_texture = _tex(set_name + "_normal")
		var orm := _tex(set_name + "_orm")
		m.ao_enabled = true
		m.ao_texture = orm
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		if variant in ["skin_rough_070", "all_off"]:
			m.roughness = 0.7
		else:
			m.roughness_texture = orm
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.subsurf_scatter_enabled = true
		m.subsurf_scatter_strength = 0.18
		m.subsurf_scatter_skin_mode = true
		m.subsurf_scatter_texture = _tex(set_name + "_mask")
		if variant not in ["no_coat", "all_off"] and ResourceLoader.exists(ASSET + set_name + "_coat.png"):
			m.clearcoat_enabled = true
			m.clearcoat = 0.22
			m.clearcoat_roughness = 0.16
			m.clearcoat_texture = _tex(set_name + "_coat")
		if flat:
			m.metallic_specular = 0.0
		return m
	if key in ["outfit", "gear"]:
		var m := StandardMaterial3D.new()
		m.albedo_texture = _tex(key + "_albedo")
		m.normal_enabled = true
		m.normal_texture = _tex(key + "_normal")
		var orm := _tex(key + "_orm")
		m.roughness_texture = orm
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.metallic = 1.0
		m.metallic_texture = orm
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if flat:
			m.metallic_specular = 0.0
		return m
	if key in ["hair", "brows"]:
		var m := StandardMaterial3D.new()
		m.albedo_texture = _tex("hair_albedo")
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.normal_enabled = true
		m.normal_texture = _tex("hair_normal")
		m.roughness = 0.55
		m.metallic_specular = 0.0 if flat else 0.25
		m.anisotropy_enabled = true
		m.anisotropy = 0.4
		return m
	var plain := StandardMaterial3D.new()
	if key == "eye":
		plain.albedo_texture = _tex("eye_albedo")
		plain.roughness = 0.38
	else:
		plain.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		plain.albedo_color = Color(0, 0, 0, 0)
	return plain
