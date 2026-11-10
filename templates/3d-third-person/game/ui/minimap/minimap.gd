class_name Minimap
extends Control
## A minimap widget: a round or square map of the world around a target, with an icon for every
## `MinimapMarker` in the scene. Put `minimap.tscn` anywhere in a HUD, set it up in the inspector
## and it works alone: it finds the target (the node in the `target_group` group), the markers and
## the sections by itself.
##
## The picture comes from the live camera (an orthographic camera looking down into a small
## `SubViewport`, rendered at `map_update_rate`) or from a baked image; both are drawn by one shader
## that also cuts the shape, the background and the border, and that slides the last snapshot
## into place, so the map moves smoothly even when it is rendered a few times a second.
## Markers are drawn by a pool of icon nodes, `marker_update_rate` times a second.
##
## The live camera needs a 3D world; the markers, the target and the image source also work in a
## 2D game (`Node2D` targets and markers; a map picture you draw yourself). The map plane is (x, z)
## in 3D with north -Z, (x, y) in 2D with north -Y.

## The target went into or out of a `MinimapSection` (null when it left them all).
signal section_changed(section: MinimapSection)

## The widget's shape.
enum Shape {
	CIRCLE,  ## A disc, the usual minimap.
	SQUARE,  ## A square with rounded corners (`corner_ratio`).
}

## What turns the map.
enum RotationMode {
	NORTH_UP,  ## North is always at the top; the player's arrow turns.
	TARGET_FACING,  ## The way the target faces is the top.
	CAMERA_FACING,  ## The way the screen's 3D camera looks is the top: what is ahead on screen is up.
}

## Where the picture comes from.
enum Source {
	LIVE_CAMERA,  ## A top-down camera renders the world as it is.
	IMAGE,  ## A texture laid over a rectangle of the map plane (or the section's own texture).
}

@export_group("Nodes")
## The node the map follows, a `Node3D` or a `Node2D`. Empty: the first node in `target_group`.
@export var target: Node
## The group searched when `target` is empty.
@export var target_group: StringName = &"player"

@export_group("Shape")
## The widget's shape.
@export var shape := Shape.CIRCLE:
	set(value):
		shape = value
		_apply_look()
## The widget's side in pixels (at the 1080 high canvas).
@export_range(64.0, 640.0, 1.0, "suffix:px") var map_size := 220.0:
	set(value):
		map_size = value
		_fit_size()
## The most of the screen's short side the widget may take, however far its parents scale it up
## (a HUD grows on a phone until its text reads, and a map that grew with it would cover the
## screen). Zero leaves the size alone.
@export_range(0.0, 0.8, 0.01) var max_screen_fraction := 0.25:
	set(value):
		max_screen_fraction = value
		_fit_size()
## For the square: how round the corners are, 0 sharp to 1 a disc.
@export_range(0.0, 1.0, 0.01) var corner_ratio := 0.25:
	set(value):
		corner_ratio = value
		_apply_look()

@export_group("View")
## How many metres the map shows from its middle to its border. Zoom changes it.
@export_range(2.0, 500.0, 0.5, "suffix:m") var range_m := 30.0:
	set(value):
		range_m = clampf(value, range_min, range_max)
		_range_goal = range_m
		if not is_node_ready():
			_range_now = range_m
## The closest zoom.
@export_range(2.0, 100.0, 0.5, "suffix:m") var range_min := 12.0
## The farthest zoom.
@export_range(10.0, 500.0, 0.5, "suffix:m") var range_max := 90.0
## What one zoom step multiplies the range by.
@export_range(1.05, 3.0, 0.05) var zoom_step := 1.3
## How quickly the range moves to its goal (per second); zero jumps.
@export_range(0.0, 40.0, 0.5) var zoom_smoothing := 10.0
## What turns the map.
@export var rotation_mode := RotationMode.CAMERA_FACING:
	set(value):
		rotation_mode = value
		if is_node_ready():
			_apply_look()
## How quickly a turning map follows (per second); zero follows at once.
@export_range(0.0, 40.0, 0.5) var turn_smoothing := 8.0
## On: the map is centred on the target. Off: it stays at `fixed_centre`.
@export var follow_target := true
## The map-plane place at the middle when the map does not follow.
@export var fixed_centre := Vector2.ZERO
## An input action that zooms in (empty: none). Ignored when the project has no such action.
@export var zoom_in_action: StringName = &"map_zoom_in"
## An input action that zooms out.
@export var zoom_out_action: StringName = &"map_zoom_out"

@export_group("Map source")
## Where the picture comes from.
@export var source := Source.LIVE_CAMERA
## The image of the `IMAGE` source: top-down, north at the top.
@export var image: Texture2D
## The rectangle of the map plane the image covers, in metres.
@export var image_world_rect := Rect2(-25.0, -25.0, 50.0, 50.0)
## The render layers the live camera draws. Put characters and props on another layer to leave
## them out.
@export_flags_3d_render var live_layers := 1:
	set(value):
		live_layers = value
		if is_node_ready():
			_camera.cull_mask = value
## How far above the target the live camera sits when no section decides.
@export_range(5.0, 200.0, 1.0, "suffix:m") var live_height := 40.0
## How far below the target the live camera still draws.
@export_range(1.0, 200.0, 1.0, "suffix:m") var live_depth := 30.0
## The live render's pixels per widget pixel. Lower is cheaper and blurrier.
@export_range(0.25, 2.0, 0.05) var live_resolution_scale := 1.0
## On: the live camera draws flat colours with no lights and no shadows (not in the Compatibility
## renderer, which cannot draw that way: there the camera draws the lit scene).
@export var live_unshaded := true:
	set(value):
		live_unshaded = value
		_apply_live()

@export_group("Look")
## The colour behind the map.
@export var background_color := Color(0.04, 0.06, 0.09, 0.85):
	set(value):
		background_color = value
		_apply_look()
## The border's colour.
@export var border_color := Color(0.9, 0.93, 1.0, 0.9):
	set(value):
		border_color = value
		_apply_look()
## The border's width; zero draws none.
@export_range(0.0, 20.0, 0.5, "suffix:px") var border_width := 3.0:
	set(value):
		border_width = value
		_apply_look()
## How far in from the border the picture fades out, as a part of the radius.
@export_range(0.0, 1.0, 0.01) var edge_fade := 0.12:
	set(value):
		edge_fade = value
		_apply_look()
## The whole widget's opacity.
@export_range(0.0, 1.0, 0.01) var opacity := 1.0:
	set(value):
		opacity = value
		_apply_look()
## On: the picture is recoloured from dark to light by its brightness (one style for any level).
@export var tint_enabled := true:
	set(value):
		tint_enabled = value
		_apply_look()
## The colour of the picture's darkest parts.
@export var tint_dark := Color(0.1, 0.14, 0.2, 1.0):
	set(value):
		tint_dark = value
		_apply_look()
## The colour of the picture's brightest parts.
@export var tint_light := Color(0.62, 0.76, 0.85, 1.0):
	set(value):
		tint_light = value
		_apply_look()
## Multiplies every marker icon's size.
@export_range(0.25, 4.0, 0.05) var marker_scale := 1.0
## Shows the letter N at north while the map turns.
@export var show_north := true
## Shows an arrow for the target at the middle while the map follows it (its own marker is then
## left out, so the target is not drawn twice).
@export var show_self := true

@export_group("Markers")
## The icon of a marker with none of its own.
@export var default_icon: Texture2D = preload("res://assets/ui/minimap/dot.png")
## The icon of a marker that sticks to the border and has no edge icon: it points outward.
@export var default_edge_icon: Texture2D = preload("res://assets/ui/minimap/arrow.png")
## Marker kinds this map leaves out (a small map may skip `pickup`, the full-screen one show it).
@export var hidden_kinds: PackedStringArray = []
## Icons made ahead of the first busy moment.
@export_range(0, 1000, 1) var pool_prewarm := 32
## At most this many markers are drawn.
@export_range(1, 5000, 1) var max_markers := 1000

@export_group("Update")
## How many times a second the live camera renders; zero renders every frame.
@export_range(0.0, 60.0, 1.0, "suffix:Hz") var map_update_rate := 0.0
## While the view stands still the live camera renders again only this often (a door may have
## moved); zero never. A moving view renders at `map_update_rate`.
@export_range(0.0, 10.0, 0.1, "suffix:s") var still_refresh_seconds := 1.0
## How many times a second the markers are placed; zero places them every frame.
@export_range(0.0, 60.0, 1.0, "suffix:Hz") var marker_update_rate := 0.0

var _projector := MinimapProjector.new()
var _pool: MinimapIconPool
var _assigned: Dictionary = {}
var _pass := 0
var _section: MinimapSection
var _heading_angle := 0.0
var _heading_ready := false
var _range_now := 30.0
var _range_goal := 30.0
var _map_clock := 0.0
var _snapshot_count := 0
var _marker_pass_usec := 0
var _refresh_requested := false
var _still_clock := 0.0
var _view_section: MinimapSection
var _marker_clock := 0.0
var _snapshot_ready := false
var _snapshot_turn := 0.0
var _snapshot_centre := Vector2.ZERO
var _snapshot_half := 30.0
var _shown_texture: Texture2D
var _viewer_height := 0.0

@onready var _square: Control = %Square
@onready var _icons: Control = %Icons
@onready var _map: ColorRect = %Map
@onready var _self_arrow: TextureRect = %Self
@onready var _north: Control = %North
@onready var _title: Label = %SectionTitle
@onready var _live_view: SubViewport = %LiveView
@onready var _camera: Camera3D = %MapCamera


func _ready() -> void:
	_range_now = range_m
	_range_goal = range_m
	_fit_size()
	_pool = MinimapIconPool.new(preload("res://ui/minimap/minimap_icon.tscn"), _icons)
	_pool.prewarm(pool_prewarm)
	_square.resized.connect(_apply_look)
	_apply_look()
	_apply_live()
	_camera.cull_mask = live_layers
	_title.visible = false


func _exit_tree() -> void:
	_assigned.clear()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if zoom_in_action != &"" and InputMap.has_action(zoom_in_action):
		if event.is_action_pressed(zoom_in_action):
			zoom_in()
			get_viewport().set_input_as_handled()
			return
	if zoom_out_action != &"" and InputMap.has_action(zoom_out_action):
		if event.is_action_pressed(zoom_out_action):
			zoom_out()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_fit_size()
	_tick(delta)


## True when the running renderer can draw a viewport unshaded. The Compatibility renderer (the web
## build, phones) cannot: Godot 4.7 prints an error every frame and draws nothing.
static func unshaded_available() -> bool:
	return RenderingServer.get_current_rendering_method() != "gl_compatibility"


## The map maths of the current frame (centre, turn, scale), for a test or a game that needs to
## ask where a place lands.
func projector() -> MinimapProjector:
	return _projector


## The icon pool, for its counts.
func pool() -> MinimapIconPool:
	return _pool


## The section the target is in, or null.
func current_section() -> MinimapSection:
	return _section


## The range the map shows now (the smoothed one), in metres.
func current_range() -> float:
	return _range_now


## Shows `section` whatever the target is in (a floor switch, a full-screen map of one floor);
## null goes back to the section the target is in.
func show_section(section: MinimapSection) -> void:
	_view_section = section


## Zooms in one step (the range gets smaller).
func zoom_in() -> void:
	_range_goal = clampf(_range_goal / zoom_step, range_min, range_max)


## Zooms out one step.
func zoom_out() -> void:
	_range_goal = clampf(_range_goal * zoom_step, range_min, range_max)


## Sets the range at once, without smoothing.
func jump_to_range(metres: float) -> void:
	_range_goal = clampf(metres, range_min, range_max)
	_range_now = _range_goal


## Does a whole update now, at once (the heading and zoom jump to their goals, the live camera
## renders and the markers are placed). A full-screen map calls it when it opens.
func refresh_now() -> void:
	request_refresh()
	_tick(0.0, true)


## Makes the next update a whole one (the heading and zoom jump, the live camera renders, the
## markers are placed), without doing it yet: for a map that is not on screen or not laid out.
func request_refresh() -> void:
	_range_now = _range_goal
	_heading_ready = false
	_snapshot_ready = false
	_map_clock = 0.0
	_marker_clock = 0.0
	_refresh_requested = true


## True when the live camera's last render is the one being shown.
func has_snapshot() -> bool:
	return _snapshot_ready


## How many times the live camera was asked to render, for a test or a cost report.
func snapshots_taken() -> int:
	return _snapshot_count


## The icon drawn for `marker` on the last update, or null when it is not on the map.
func icon_for(marker: MinimapMarker) -> MinimapIcon:
	var icon: MinimapIcon = _assigned.get(marker.get_instance_id())
	return icon if is_instance_valid(icon) else null


## The microseconds the last marker pass took (the rules, the maths and the icon updates).
func marker_pass_usec() -> int:
	return _marker_pass_usec


## How many markers were drawn on the last update.
func shown_count() -> int:
	return _assigned.size()


func _tick(delta: float, requested := false) -> void:
	if _square.size.x < 1.0:
		return
	var force := requested or _refresh_requested
	_refresh_requested = false
	var subject := _subject()
	_step_zoom(delta)
	var subject_plane := _plane_of(subject)
	var view_centre := subject_plane if (follow_target and subject != null) else fixed_centre
	_step_heading(delta, subject)
	_projector.circular = shape == Shape.CIRCLE
	_projector.half_extent = _square.size.x * 0.5
	_projector.centre = view_centre
	_projector.turn = MinimapProjector.turn_for_heading(Vector2.from_angle(_heading_angle))
	_projector.set_range(_range_now)
	var target_3d := _position_3d_of(subject, view_centre)
	_viewer_height = target_3d.y
	_update_section(target_3d)
	_update_map(delta, target_3d, force)
	_push_view()
	_update_decorations(subject)
	_marker_clock += delta
	var interval := 0.0 if marker_update_rate <= 0.0 else 1.0 / marker_update_rate
	if force or _marker_clock >= interval:
		_marker_clock = 0.0
		_place_markers(subject_plane, _section, subject)


func _subject() -> Node:
	if target != null and is_instance_valid(target):
		return target
	return get_tree().get_first_node_in_group(target_group)


func _plane_of(node: Node) -> Vector2:
	if node is Node3D:
		var at := (node as Node3D).global_position
		return Vector2(at.x, at.z)
	if node is Node2D:
		return (node as Node2D).global_position
	return fixed_centre


func _position_3d_of(node: Node, plane: Vector2) -> Vector3:
	if node is Node3D:
		return (node as Node3D).global_position
	return Vector3(plane.x, 0.0, plane.y)


# The way a node faces on the map plane: its own answer, its -Z (3D) or its rotation (2D).
func _forward_of(node: Node) -> Vector2:
	if node == null:
		return MinimapProjector.north()
	if node.has_method(&"get_minimap_heading"):
		return node.call(&"get_minimap_heading")
	if node is Node3D:
		var forward := -(node as Node3D).global_basis.z
		var flat := Vector2(forward.x, forward.z)
		if flat.length_squared() > 0.000001:
			return flat.normalized()
	elif node is Node2D:
		return Vector2.RIGHT.rotated((node as Node2D).global_rotation)
	return MinimapProjector.north()


# Sets the minimum size: `map_size`, less when a scaled-up parent would take too much of the screen.
func _fit_size() -> void:
	var side := map_size
	if max_screen_fraction > 0.0 and is_inside_tree():
		var shown := get_viewport().get_visible_rect().size
		var grown := maxf(get_global_transform().get_scale().x, 0.01)
		side = minf(side, max_screen_fraction * minf(shown.x, shown.y) / grown)
	var wanted := Vector2(side, side)
	if custom_minimum_size != wanted:
		custom_minimum_size = wanted


func _step_zoom(delta: float) -> void:
	if zoom_smoothing <= 0.0 or delta <= 0.0:
		_range_now = _range_goal
	else:
		_range_now = lerpf(_range_now, _range_goal, 1.0 - exp(-zoom_smoothing * delta))


func _view_heading(subject: Node) -> Vector2:
	match rotation_mode:
		RotationMode.TARGET_FACING:
			return _forward_of(subject)
		RotationMode.CAMERA_FACING:
			var camera := get_viewport().get_camera_3d()
			if camera != null:
				var look := -camera.global_basis.z
				var flat := Vector2(look.x, look.z)
				if flat.length_squared() > 0.000001:
					return flat.normalized()
	return MinimapProjector.north()


func _step_heading(delta: float, subject: Node) -> void:
	var goal := _view_heading(subject).angle()
	if not _heading_ready or turn_smoothing <= 0.0 or delta <= 0.0:
		_heading_angle = goal
		_heading_ready = true
	else:
		_heading_angle = lerp_angle(_heading_angle, goal, 1.0 - exp(-turn_smoothing * delta))


func _update_section(target_3d: Vector3) -> void:
	var found: MinimapSection = _view_section
	var searching := follow_target and get_tree().get_node_count_in_group(MinimapSection.GROUP) > 0
	if found == null and searching:
		found = MinimapSection.at(get_tree(), target_3d)
	if found == _section:
		return
	_section = found
	_snapshot_ready = false
	_title.text = "" if found == null else found.title
	_title.visible = not _title.text.is_empty()
	section_changed.emit(found)


func _update_map(delta: float, target_3d: Vector3, force: bool) -> void:
	var picture: Texture2D = null
	var rect := image_world_rect
	if _section != null and _section.map_texture != null:
		picture = _section.map_texture
		rect = _section.footprint()
	elif source == Source.IMAGE:
		picture = image
	if picture != null:
		_show_image(picture, rect)
		return
	if source == Source.IMAGE:
		_map.material.set_shader_parameter(&"has_map", false)
		return
	_map_clock += delta
	var interval := 0.0 if map_update_rate <= 0.0 else 1.0 / map_update_rate
	if not (force or not _snapshot_ready or _map_clock >= interval):
		return
	var limited := interval > 0.0
	if not force and _snapshot_ready and _view_matches_snapshot(limited):
		# The view has not moved: the picture only needs a new render now and then.
		_still_clock += _map_clock
		_map_clock = 0.0
		if still_refresh_seconds <= 0.0 or _still_clock < still_refresh_seconds:
			return
	_map_clock = 0.0
	_still_clock = 0.0
	_snapshot(target_3d, limited)


func _overscan_for(limited: bool) -> float:
	if not limited:
		return 1.0
	return 1.15 if _projector.circular else 1.5


func _view_matches_snapshot(limited: bool) -> bool:
	return (
		_projector.centre.is_equal_approx(_snapshot_centre)
		and is_equal_approx(_projector.turn, _snapshot_turn)
		and is_equal_approx(_range_now * _overscan_for(limited), _snapshot_half)
	)


func _show_image(picture: Texture2D, rect: Rect2) -> void:
	var shader_material := _map.material as ShaderMaterial
	if _shown_texture != picture:
		_shown_texture = picture
		shader_material.set_shader_parameter(&"map_texture", picture)
	shader_material.set_shader_parameter(&"has_map", true)
	shader_material.set_shader_parameter(&"source_centre", rect.get_center())
	shader_material.set_shader_parameter(&"source_turn", 0.0)
	shader_material.set_shader_parameter(&"source_half", rect.size * 0.5)


func _snapshot(target_3d: Vector3, rate_limited: bool) -> void:
	var overscan := _overscan_for(rate_limited)
	var half := _range_now * overscan
	var side := _square.size.x * overscan * live_resolution_scale * _canvas_scale()
	var pixels := clampi(int(round(side)), 32, 1536)
	if _live_view.size != Vector2i(pixels, pixels):
		_live_view.size = Vector2i(pixels, pixels)
	var top := target_3d.y + live_height
	var depth := live_height + live_depth
	if _section != null:
		top = _section.top_y()
		depth = _section.size.y
	var up := MinimapProjector.north().rotated(-_projector.turn)
	_camera.size = half * 2.0
	_camera.near = 0.05
	_camera.far = depth + 0.1
	_camera.global_transform = Transform3D(
		Basis.looking_at(Vector3.DOWN, Vector3(up.x, 0.0, up.y)),
		Vector3(_projector.centre.x, top, _projector.centre.y)
	)
	_live_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	_snapshot_count += 1
	_snapshot_ready = true
	_snapshot_centre = _projector.centre
	_snapshot_turn = _projector.turn
	_snapshot_half = half
	var shader_material := _map.material as ShaderMaterial
	var texture := _live_view.get_texture()
	if _shown_texture != texture:
		_shown_texture = texture
		shader_material.set_shader_parameter(&"map_texture", texture)
	shader_material.set_shader_parameter(&"has_map", true)
	shader_material.set_shader_parameter(&"source_centre", _snapshot_centre)
	shader_material.set_shader_parameter(&"source_turn", _snapshot_turn)
	shader_material.set_shader_parameter(&"source_half", Vector2(half, half))


func _canvas_scale() -> float:
	return maxf(get_global_transform_with_canvas().get_scale().x, 0.01)


func _push_view() -> void:
	var shader_material := _map.material as ShaderMaterial
	shader_material.set_shader_parameter(&"view_centre", _projector.centre)
	shader_material.set_shader_parameter(&"view_turn", _projector.turn)
	shader_material.set_shader_parameter(&"view_range", _range_now)


func _update_decorations(subject: Node) -> void:
	var middle := _icons.size * 0.5
	var heading := _forward_of(subject)
	_self_arrow.position = middle - _self_arrow.size * 0.5
	_self_arrow.pivot_offset = _self_arrow.size * 0.5
	_self_arrow.rotation = _projector.icon_rotation(heading)
	_self_arrow.visible = _self_shown(subject)
	var turning := rotation_mode != RotationMode.NORTH_UP
	_north.visible = show_north and turning
	if _north.visible:
		var toward := _projector.clamp_to_border(
			MinimapProjector.north().rotated(_projector.turn) * 10000.0, 12.0
		)
		_north.position = middle + toward - _north.size * 0.5


func _self_shown(subject: Node) -> bool:
	return show_self and follow_target and subject != null


func _place_markers(viewer_plane: Vector2, viewer_section: MinimapSection, subject: Node) -> void:
	var started := Time.get_ticks_usec()
	_pass += 1
	var self_shown := _self_shown(subject)
	var middle := _icons.size * 0.5
	var shown := 0
	var turn := _projector.turn
	var scale_px := _projector.px_per_metre
	var centre := _projector.centre
	var check_kinds := not hidden_kinds.is_empty()
	for node in get_tree().get_nodes_in_group(MinimapMarker.GROUP):
		var marker := node as MinimapMarker
		if marker == null or not marker.active or shown >= max_markers:
			continue
		if check_kinds and hidden_kinds.has(String(marker.kind)):
			continue
		if self_shown and marker.get_parent() == subject:
			continue
		if marker.rule != MinimapMarker.Rule.ALWAYS:
			if not marker.passes_rule(viewer_plane, viewer_section):
				continue
		var offset := (marker.plane_position() - centre).rotated(turn) * scale_px
		var clamped := false
		if not _projector.contains(offset):
			if not marker.clamp_to_edge:
				continue
			offset = _projector.clamp_to_border(offset, marker.edge_inset)
			clamped = true
		var id := marker.get_instance_id()
		var icon: MinimapIcon = _assigned.get(id)
		if icon == null or not is_instance_valid(icon):
			icon = _pool.acquire()
			_assigned[id] = icon
		icon.seen_in_pass = _pass
		shown += 1
		_place(icon, marker, offset + middle, offset, clamped)
	_release_unseen()
	_marker_pass_usec = Time.get_ticks_usec() - started


func _place(
	icon: MinimapIcon, marker: MinimapMarker, centre: Vector2, offset: Vector2, clamped: bool
) -> void:
	var picture: Texture2D = marker.icon if marker.icon != null else default_icon
	var side := marker.size * marker_scale
	var angle := 0.0
	if clamped:
		picture = marker.edge_icon if marker.edge_icon != null else default_edge_icon
		side *= 0.85
		angle = MinimapProjector.outward_rotation(offset)
	elif marker.rotates_with_node:
		angle = _projector.icon_rotation(marker.heading())
	var tint := marker.color
	if marker.height_fade > 0.0:
		var dy := absf(marker.height() - _viewer_height)
		tint.a *= 1.0 - 0.85 * smoothstep(marker.height_fade * 0.4, marker.height_fade, dy)
	icon.place(picture, centre, side, angle, tint, marker.draw_order)


func _release_unseen() -> void:
	var gone: Array[int] = []
	for id: int in _assigned:
		var icon: MinimapIcon = _assigned[id]
		if not is_instance_valid(icon) or icon.seen_in_pass != _pass:
			gone.append(id)
	for id in gone:
		_pool.release(_assigned[id])
		_assigned.erase(id)


func _apply_look() -> void:
	if not is_node_ready():
		return
	var shader_material := _map.material as ShaderMaterial
	shader_material.set_shader_parameter(&"circular", shape == Shape.CIRCLE)
	shader_material.set_shader_parameter(&"corner_ratio", corner_ratio)
	shader_material.set_shader_parameter(&"background_color", background_color)
	shader_material.set_shader_parameter(&"border_color", border_color)
	shader_material.set_shader_parameter(&"border_px", border_width)
	shader_material.set_shader_parameter(&"widget_px", maxf(_square.size.x, 1.0))
	shader_material.set_shader_parameter(&"edge_fade", edge_fade)
	shader_material.set_shader_parameter(&"opacity", opacity)
	shader_material.set_shader_parameter(&"tint_enabled", tint_enabled)
	shader_material.set_shader_parameter(&"tint_dark", tint_dark)
	shader_material.set_shader_parameter(&"tint_light", tint_light)
	_icons.modulate.a = opacity


func _apply_live() -> void:
	if not is_node_ready():
		return
	var flat := live_unshaded and unshaded_available()
	_live_view.debug_draw = Viewport.DEBUG_DRAW_UNSHADED if flat else Viewport.DEBUG_DRAW_DISABLED
