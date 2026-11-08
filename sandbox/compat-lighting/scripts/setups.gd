class_name Setups
extends RefCounted
## Applies a setup, a "+"-joined list of tokens, to the night scene. See docs/engines/godot/compat-lighting.md
## for what each token measures.

const DYNAMIC_COLORS: Array[Color] = [
	Color(1.0, 0.1, 0.6), Color(0.2, 0.8, 1.0), Color(1.0, 0.7, 0.3), Color(0.4, 1.0, 0.4),
]

var world: Node3D
var camera: Camera3D
var environment: Environment
var overlay_parent: Node
var tokens: PackedStringArray


func _init(p_tokens: PackedStringArray) -> void:
	tokens = p_tokens


func has(token: String) -> bool:
	return tokens.has(token)


func ground_tiles() -> int:
	return 1 if has("bigground") else 6


func uses_lightmap() -> bool:
	for t in tokens:
		if t.begins_with("lm_"):
			return true
	return false


func apply(p_world: Node3D, p_camera: Camera3D, p_env: Environment, p_overlay_parent: Node) -> void:
	world = p_world
	camera = p_camera
	environment = p_env
	overlay_parent = p_overlay_parent
	for token in tokens:
		_apply_token(token)


func _apply_token(token: String) -> void:
	match token:
		"tm_linear": environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		"tm_reinhard": environment.tonemap_mode = Environment.TONE_MAPPER_REINHARDT
		"tm_filmic": environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		"tm_aces": environment.tonemap_mode = Environment.TONE_MAPPER_ACES
		"tm_agx": environment.tonemap_mode = Environment.TONE_MAPPER_AGX
		"glow":
			environment.glow_enabled = true
			environment.glow_intensity = 0.8
			environment.glow_strength = 1.0
			environment.glow_bloom = 0.0
			environment.glow_hdr_threshold = 1.0
			environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
		"fog":
			environment.fog_enabled = true
			environment.fog_light_color = Color(0.05, 0.07, 0.14)
			environment.fog_density = 0.025
			environment.fog_sky_affect = 0.5
		"adj":
			environment.adjustment_enabled = true
			environment.adjustment_brightness = 1.05
			environment.adjustment_contrast = 1.2
			environment.adjustment_saturation = 0.85
		"volfog": environment.volumetric_fog_enabled = true
		"ssao": environment.ssao_enabled = true
		"ssr": environment.ssr_enabled = true
		"sdfgi": environment.sdfgi_enabled = true
		"bigground", "base": pass
		"post_grade": _add_post("res://shaders/post_grade.gdshader")
		"post_overlay": _add_post("res://shaders/post_overlay.gdshader")
		"shadow_spot": _add_shadow_spot()
		"shadow_omni": _add_shadow_omni()
		"shadow_moon": _add_moon()
		"projector": _add_projector()
		_:
			if token.begins_with("omni"):
				_add_lights(int(token.trim_prefix("omni")), false)
			elif token.begins_with("spot"):
				_add_lights(int(token.trim_prefix("spot")), true)
			elif token.begins_with("lm_"):
				_add_lightmap(token.trim_prefix("lm_"))
			else:
				push_error("unknown setup token: " + token)


func _add_post(shader_path: String) -> void:
	var layer := CanvasLayer.new()
	layer.name = "Post"
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = load(shader_path)
	rect.material = mat
	layer.add_child(rect)
	overlay_parent.add_child(layer)


## Extra dynamic lights spread over the lot, no shadows. Deterministic positions.
func _add_lights(count: int, as_spot: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for i in count:
		var pos := Vector3(rng.randf_range(-24.0, 24.0), 2.5, rng.randf_range(-18.0, 20.0))
		var color := DYNAMIC_COLORS[i % DYNAMIC_COLORS.size()]
		var light: Light3D
		if as_spot:
			var spot := SpotLight3D.new()
			spot.spot_range = 12.0
			spot.spot_angle = 55.0
			spot.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
			light = spot
		else:
			var omni := OmniLight3D.new()
			omni.omni_range = 9.0
			light = omni
		light.name = "Extra%d" % i
		light.position = pos
		light.light_color = color
		light.light_energy = 3.0
		world.add_child(light)


func _add_shadow_spot() -> void:
	var spot := SpotLight3D.new()
	spot.name = "ShadowSpot"
	spot.position = Vector3(0.0, 4.0, 24.0)
	spot.spot_range = 50.0
	spot.spot_angle = 30.0
	spot.light_energy = 6.0
	spot.shadow_enabled = true
	world.add_child(spot)
	spot.look_at(Vector3(0.0, 1.0, -10.0))


func _add_shadow_omni() -> void:
	var omni := OmniLight3D.new()
	omni.name = "ShadowOmni"
	omni.position = Vector3(-6.0, 5.0, 4.0)
	omni.omni_range = 22.0
	omni.light_energy = 3.0
	omni.light_color = Color(0.9, 0.8, 1.0)
	omni.shadow_enabled = true
	world.add_child(omni)


func _add_moon() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Moon"
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.light_color = Color(0.5, 0.6, 1.0)
	sun.light_energy = 0.5
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	world.add_child(sun)


## Projector beam from the booth toward the screen: a spot with a projector texture.
func _add_projector() -> void:
	var spot := SpotLight3D.new()
	spot.name = "Projector"
	spot.position = Vector3(0.0, 4.5, 26.0)
	spot.spot_range = 60.0
	spot.spot_angle = 22.0
	spot.light_energy = 14.0
	spot.light_color = Color(0.85, 0.9, 1.0)
	var tex := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 0.6, 0.2), Color(0.3, 0.7, 1)])
	tex.gradient = grad
	tex.fill_to = Vector2(1, 1)
	spot.light_projector = tex
	world.add_child(spot)
	spot.look_at(Vector3(0.0, 0.0, -10.0))


func _add_lightmap(quality: String) -> void:
	var path := "res://bakes/bake_%s.lmbake" % quality
	var gi := LightmapGI.new()
	gi.name = "LightmapGI"
	gi.light_data = load(path)
	world.add_child(gi)
