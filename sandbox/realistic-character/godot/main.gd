extends Node3D
## Test scene of the realistic character experiment (kit docs: tools/blender/realistic-characters.md#godot).
##
## Builds everything from code: the exported character from `res://asset/`, a material for each of its surfaces,
## an idle clip of the Universal Animation Library retargeted by bone name, three lighting setups, the captures
## and the frame cost. Run it once per renderer and hairstyle:
##
##   gds godot -- --path <project> [--rendering-method gl_compatibility] -- --out=<folder> [--hair=ponytail|long]
##
## `--rest` leaves her in the rest pose (no clip); `--only=day_face` takes one capture; `--skin-normal=0` draws the skin without its normal maps.
## `--shine` adds, per lighting, a bust capture with every highlight switched off next to the normal one, for
## `shine.py`. The roughness and specular each material ends up with are the constants below.

const ASSET := "res://asset/"
const LIGHTS: Array[String] = ["dark", "day", "warm"]
## shot: camera position, target, vertical field of view (the Blender renders' cameras, in Godot's axes)
const SHOTS := {
	"face": [Vector3(0.10, 1.605, 0.86), Vector3(0.0, 1.585, 0.08), 23.9],
	"bust": [Vector3(0.42, 1.30, 1.18), Vector3(0.0, 1.37, 0.0), 39.6],
	"full": [Vector3(0.9, 1.0, 3.7), Vector3(0.0, 0.87, 0.0), 39.6],
	"back": [Vector3(-0.5, 1.45, -1.25), Vector3(0.0, 1.35, 0.0), 39.6],
	"arm": [Vector3(0.78, 1.22, 1.02), Vector3(0.25, 1.14, 0.0), 22.0],
	"hands": [Vector3(0.50, 0.98, 0.72), Vector3(0.30, 0.86, 0.02), 20.0],
}
const CAPTURES := [
	["dark", "face"], ["dark", "bust"], ["dark", "full"], ["day", "face"], ["day", "bust"], ["day", "full"],
	["warm", "face"], ["warm", "bust"], ["warm", "full"], ["day", "arm"], ["warm", "arm"], ["day", "back"],
	["day", "hands"],
]
## Specular (Godot's scale: 0.5 is 4 % reflectance head on) and what the roughness comes from, per material.
## Skin: 0.35, roughness from the map (0.62 to 0.74 dry, 0.46 at the oiliest, lips 0.36 to 0.50).
## Cloth, leather, webbing: 0.25, roughness from the map (cloth 0.9, leather 0.6 to 0.8), never metal.
## Gear (polymer, steel): 0.5, the map's roughness and metal.
const SPECULAR_SKIN := 0.35
const SPECULAR_CLOTH := 0.25
const SPECULAR_GEAR := 0.5
const EYE_ROUGHNESS := 0.38

var _character: Node3D
var _camera := Camera3D.new()
var _env := Environment.new()
var _rig: Node3D
var _compat := false
var _shaded: Array[Material] = []
var _skin_normal := 1.0


func _ready() -> void:
	_compat = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	var out := "user://"
	var hair := "ponytail"
	var shine := false
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		if a.begins_with("--hair="):
			hair = a.trim_prefix("--hair=")
		if a == "--shine":
			shine = true
		if a.begins_with("--skin-normal="):
			_skin_normal = float(a.trim_prefix("--skin-normal="))
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	var world := WorldEnvironment.new()
	world.environment = _env
	add_child(world)
	add_child(_camera)
	_camera.current = true
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.2, 0.2, 0.2)
	floor_mat.roughness = 0.8
	floor_mesh.material_override = floor_mat
	add_child(floor_mesh)
	_light("day")
	_shot("bust")
	var empty := await _measure()
	_character = (load(ASSET + "heroine.glb") as PackedScene).instantiate()
	add_child(_character)
	# One hairstyle is worn: the other leaves the scene, so the cost below is of what is drawn.
	for node in _character.find_children("hair_*", "MeshInstance3D", true, false):
		if String(node.name) != "hair_" + hair:
			node.get_parent().remove_child(node)
			node.free()
	var skeleton: Skeleton3D = _character.find_children("*", "Skeleton3D", true, false)[0]
	var rig: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ASSET + "rig.json"))
	skeleton.motion_scale = rig["motion_scale"]
	_materials()
	var clip := "" if "--rest" in OS.get_cmdline_user_args() else _idle(skeleton)
	var tag := ("compat" if _compat else "forward") + "_" + hair
	for pair: Array in CAPTURES:
		if only != "" and only != "%s_%s" % [pair[0], pair[1]]:
			continue
		_light(pair[0])
		_shot(pair[1])
		await _settle()
		if pair[1] == "face":
			# The idle moves her head: the close-up follows the head bone, or it frames her forehead.
			var head := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Head")).origin
			_camera.position = head + Vector3(0.10, 0.085, 0.84)
			_camera.look_at(head + Vector3(0.0, 0.07, 0.06))
		if pair[1] == "hands":
			var hand := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hand_l")).origin
			_camera.position = hand + Vector3(0.22, 0.05, 0.62)
			_camera.look_at(hand + Vector3(0.0, -0.07, 0.0))
		_look(skeleton)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/godot_%s_%s_%s.png" % [out, tag, pair[0], pair[1]])
	if shine:
		# No clip for these: the two captures of a pair are compared pixel by pixel, and the numbers are compared
		# with the first build's, which `diag.gd` took in this pose (the rest, both arms turned down to her sides).
		var players := _character.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			(players[0] as AnimationPlayer).stop()
		skeleton.reset_bone_poses()
		for side: String in ["l", "r"]:
			var b := skeleton.find_bone("upperarm_" + side)
			var turn := Basis(Vector3(0, 0, 1), deg_to_rad(-72.0 if side == "l" else 72.0))
			var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(b))
			skeleton.set_bone_pose_rotation(b, (parent.basis.inverse() * turn * skeleton.get_bone_global_rest(b).basis).get_rotation_quaternion())
		for kind in LIGHTS:
			_light(kind)
			_shot("bust")
			for matt: float in [0.0, 1.0]:
				_matt(matt)
				await _settle()
				var name := "all_off" if matt > 0.5 else "reworked"
				get_viewport().get_texture().get_image().save_png("%s/shine_%s_%s_%s.png" % [out, tag, kind, name])
		_matt(0.0)
		if not players.is_empty():
			(players[0] as AnimationPlayer).play()
	_light("day")
	_shot("bust")
	var with := await _measure()
	var report := {
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"window": [get_viewport().size.x, get_viewport().size.y],
		"hair": hair,
		"clip": clip,
		"bones": skeleton.get_bone_count(),
		"empty": empty,
		"with_character": with,
	}
	var f := FileAccess.open("%s/godot_%s.json" % [out, tag], FileAccess.WRITE)
	f.store_string(JSON.stringify(report, " "))
	f.close()
	print("REPORT ", JSON.stringify(report))
	get_tree().quit()


func _settle() -> void:
	for i in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


## Frame cost of the view as it stands: CPU and GPU milliseconds the renderer measures, averaged over 240 frames.
func _measure() -> Dictionary:
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for i in 60:
		await get_tree().process_frame
	var cpu := 0.0
	var gpu := 0.0
	var frames := 240
	var start := Time.get_ticks_usec()
	for i in frames:
		await get_tree().process_frame
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var wall := (Time.get_ticks_usec() - start) / 1000.0 / frames
	return {
		"cpu_ms": snappedf(cpu / frames, 0.001),
		"gpu_ms": snappedf(gpu / frames, 0.001),
		"frame_ms": snappedf(wall, 0.001),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"texture_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.1),
	}


func _tex(name: String) -> Texture2D:
	return load(ASSET + name + ".png")


## Clothes and gear: the baked maps on a StandardMaterial3D. `metal` says whether the set has metal at all: a
## cloth set never reads its metal channel, so a stray value there cannot make cloth gleam.
func _pbr(set_name: String, specular: float, metal: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(set_name + "_albedo")
	m.normal_enabled = true
	m.normal_texture = _tex(set_name + "_normal")
	var orm := _tex(set_name + "_orm")
	m.ao_enabled = true
	m.ao_texture = orm
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness_texture = orm
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.metallic_specular = specular
	if metal:
		m.metallic = 1.0
		m.metallic_texture = orm
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	m.set_meta("specular", specular)
	_shaded.append(m)
	return m


func _skin(set_name: String, detail_tiles: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://skin.gdshader")
	m.set_shader_parameter("albedo_tex", _tex(set_name + "_albedo"))
	m.set_shader_parameter("normal_tex", _tex(set_name + "_normal"))
	m.set_shader_parameter("orm_tex", _tex(set_name + "_orm"))
	m.set_shader_parameter("mask_tex", _tex(set_name + "_mask"))
	m.set_shader_parameter("detail_tex", _tex("skin_detail_normal"))
	m.set_shader_parameter("detail_tiles", detail_tiles)
	m.set_shader_parameter("specular", SPECULAR_SKIN)
	m.set_shader_parameter("normal_strength", _skin_normal)
	_shaded.append(m)
	return m


func _wet_shell() -> StandardMaterial3D:
	# The cornea and the tear line: nothing but a sharp highlight, added over what is behind.
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_PREMULT_ALPHA
	m.albedo_color = Color(0, 0, 0, 0)
	m.roughness = 0.04
	m.metallic_specular = 0.6
	return m


func _materials() -> void:
	var hair := ShaderMaterial.new()
	hair.shader = load("res://hair.gdshader")
	hair.set_shader_parameter("albedo_tex", _tex("hair_albedo"))
	hair.set_shader_parameter("normal_tex", _tex("hair_normal"))
	hair.set_shader_parameter("orm_tex", _tex("hair_orm"))
	_shaded.append(hair)
	var eye := StandardMaterial3D.new()
	eye.albedo_texture = _tex("eye_albedo")
	eye.roughness = EYE_ROUGHNESS
	var occ := StandardMaterial3D.new()
	occ.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	occ.vertex_color_use_as_albedo = true
	occ.albedo_color = Color(0, 0, 0, 1)
	occ.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var outfit := _pbr("outfit", SPECULAR_CLOTH, false)
	outfit.cull_mode = BaseMaterial3D.CULL_DISABLED
	var by_name := {
		"skin_head": _skin("head", 24.0), "skin_body": _skin("body", 40.0), "eye": eye, "cornea": _wet_shell(),
		"tearline": _wet_shell(), "eye_occlusion": occ, "hair": hair, "outfit": outfit,
		"gear": _pbr("gear", SPECULAR_GEAR, true),
	}
	for node in _character.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var source := mi.mesh.surface_get_material(s)
			var key := source.resource_name if source else ""
			if not by_name.has(key):
				# A second mesh on a material arrives with an unnamed copy of it: go by the mesh's name.
				var n := String(mi.name)
				key = "hair" if n.begins_with("brows") else n.get_slice("_", 0)
				key = {"eyeocc": "eye_occlusion", "tear": "tearline"}.get(key, key)
				if key == "skin":
					key = "skin_head" if s == 0 else "skin_body"
			assert(by_name.has(key), "no material for surface '%s' of %s" % [key, mi.name])
			mi.set_surface_override_material(s, by_name[key])


## Switches every highlight of the skin, hair, clothes and gear off (1.0) or back on (0.0), and the reflected
## background with them: the difference between the two captures is what the highlights add.
func _matt(amount: float) -> void:
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED if amount > 0.5 else Environment.REFLECTION_SOURCE_BG
	for m in _shaded:
		if m is ShaderMaterial:
			(m as ShaderMaterial).set_shader_parameter("matt", amount)
		else:
			(m as StandardMaterial3D).metallic_specular = 0.0 if amount > 0.5 else float(m.get_meta("specular"))


## Plays the library's idle on her skeleton: the tracks are bone rotations by name, so they are only re-pathed.
func _idle(skeleton: Skeleton3D) -> String:
	if not ResourceLoader.exists(ASSET + "ual1.glb"):
		return ""
	var source: Node = (load(ASSET + "ual1.glb") as PackedScene).instantiate()
	var players := source.find_children("*", "AnimationPlayer", true, false)
	var from := players[0] as AnimationPlayer
	var pick := ""
	for n in from.get_animation_list():
		if "idle" in n.to_lower() and (pick == "" or n.length() < pick.length()):
			pick = n
	if pick == "":
		source.free()
		return ""
	var anim := from.get_animation(pick).duplicate() as Animation
	source.free()
	var player := AnimationPlayer.new()
	_character.add_child(player)
	var base := str(_character.get_path_to(skeleton))
	for t in range(anim.get_track_count() - 1, -1, -1):
		var bone := anim.track_get_path(t).get_concatenated_subnames()
		var moves := anim.track_get_type(t) != Animation.TYPE_ROTATION_3D and bone not in ["pelvis", "root"]
		# The library's file keys a position on every bone: those are its own body's bone lengths, not ours.
		if skeleton.find_bone(bone) < 0 or moves:
			anim.remove_track(t)
		else:
			anim.track_set_path(t, NodePath("%s:%s" % [base, bone]))
	anim.loop_mode = Animation.LOOP_LINEAR
	var library := AnimationLibrary.new()
	library.add_animation("idle", anim)
	player.add_animation_library("", library)
	player.play("idle")
	return pick


## Turns both eyes to the camera, by 25 degrees at most: the idle tips her head back, and eyes left at rest then
## stare over the lens. The eye bones are the rig's own; no clip keys them.
func _look(skeleton: Skeleton3D) -> void:
	for side: String in ["l", "r"]:
		var b := skeleton.find_bone("eye_" + side)
		var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(b))
		var rest := parent * skeleton.get_bone_rest(b)
		var forward := (skeleton.global_transform.basis * parent.basis * skeleton.get_bone_global_rest(skeleton.get_bone_parent(b)).basis.inverse() * Vector3(0, 0, 1)).normalized()
		var to := (_camera.global_position - skeleton.global_transform * rest.origin).normalized()
		var angle := minf(forward.angle_to(to), deg_to_rad(25.0))
		var axis := forward.cross(to)
		if axis.length() < 1e-5:
			continue
		var turn := Basis(axis.normalized(), angle)
		var aimed := skeleton.global_transform.basis.inverse() * turn * skeleton.global_transform.basis * rest.basis
		skeleton.set_bone_pose_rotation(b, (parent.basis.inverse() * aimed).get_rotation_quaternion())


func _shot(shot: String) -> void:
	var s: Array = SHOTS[shot]
	_camera.position = s[0]
	_camera.look_at(s[1])
	_camera.fov = s[2]


func _spot(pos: Vector3, energy: float, colour: Color, shadow := true) -> void:
	var l := SpotLight3D.new()
	l.position = pos
	l.light_energy = energy
	l.light_color = colour
	l.spot_range = 9.0
	l.spot_angle = 35.0
	l.shadow_enabled = shadow
	l.light_size = 0.15
	l.shadow_normal_bias = 2.0
	_rig.add_child(l)
	l.look_at(Vector3(0.0, 1.5, 0.03))


func _light(kind: String) -> void:
	if _rig:
		_rig.free()
	_rig = Node3D.new()
	add_child(_rig)
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.ssao_enabled = true
	_env.ssil_enabled = false
	_env.glow_enabled = false
	match kind:
		"dark":
			_env.background_color = Color(0.03, 0.055, 0.08)
			_env.ambient_light_color = Color(0.25, 0.38, 0.6)
			_env.ambient_light_energy = 0.12
			_spot(Vector3(0.95, 2.15, 1.7), 5.0, Color(0.72, 0.84, 1.0))
			_spot(Vector3(-1.25, 2.05, -1.2), 16.0, Color(0.55, 0.78, 1.0))
			_spot(Vector3(1.5, 1.75, -1.0), 9.0, Color(0.62, 0.82, 1.0), false)
		"day":
			_env.background_color = Color(0.42, 0.6, 1.0)
			_env.ambient_light_color = Color(0.5, 0.68, 1.0)
			_env.ambient_light_energy = 0.5
			var sun := DirectionalLight3D.new()
			sun.light_energy = 1.8
			sun.light_color = Color(1.0, 0.93, 0.82)
			sun.shadow_enabled = true
			sun.directional_shadow_max_distance = 12.0
			sun.shadow_normal_bias = 2.5
			sun.shadow_blur = 1.5
			_rig.add_child(sun)
			sun.rotation_degrees = Vector3(-38.0, 38.0, 0.0)
		"warm":
			_env.background_color = Color(0.07, 0.032, 0.013)
			_env.ambient_light_color = Color(1.0, 0.6, 0.35)
			_env.ambient_light_energy = 0.1
			_spot(Vector3(-1.05, 1.95, 1.25), 8.0, Color(1.0, 0.60, 0.30))
			_spot(Vector3(1.25, 1.95, -1.15), 10.0, Color(1.0, 0.68, 0.36))
