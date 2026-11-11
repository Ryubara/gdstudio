class_name MinimapBaker
extends RefCounted
## Renders a top-down picture of a rectangle of the world with the camera the live minimap uses, for
## the `IMAGE` source: bake a finished level once (the tool in `tools/minimap/` does it and writes a
## PNG) and the minimap drops its second render pass. The picture has north at the top and covers
## `rect` (x, z in metres) exactly, which is what `Minimap.image_world_rect` and a section's
## `map_texture` expect. It needs a renderer: a headless run draws nothing.


## Renders `rect` of the world `host` is in, `px_per_metre` pixels to the metre, from `top` metres
## high down to `depth` metres below that, drawing only `layers`. Wait for it with `await`.
static func bake(
	host: Node,
	rect: Rect2,
	px_per_metre: float,
	top: float,
	depth: float,
	layers := 1,
	unshaded := true
) -> Image:
	var viewport := SubViewport.new()
	viewport.size = Vector2i((rect.size * px_per_metre).round())
	viewport.world_3d = host.get_viewport().world_3d
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.positional_shadow_atlas_size = 0
	if unshaded and Minimap.unshaded_available():
		viewport.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	var camera := Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = rect.size.y
	camera.near = 0.05
	camera.far = depth + 0.1
	camera.cull_mask = layers
	camera.environment = _flat_environment()
	viewport.add_child(camera)
	host.add_child(viewport)
	var centre := rect.get_center()
	camera.global_transform = Transform3D(
		Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), Vector3(centre.x, top, centre.y)
	)
	camera.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	return image


static func _flat_environment() -> Environment:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	return environment
