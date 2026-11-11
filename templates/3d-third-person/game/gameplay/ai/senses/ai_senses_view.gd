class_name AiSensesView
extends MeshInstance3D
## The debug view of an `AiSenses` (its `view`, a child in `ai_character.tscn`): the view cone on
## the ground out to `sight_range`, the `near_radius` ring, the `hearing_range` ring, a line from
## the eyes to each belief (green while seen, amber to where a memory was, blue for a noise or a
## telling) and above the head one awareness bar per belief, with the `suspicious_at` mark. Off
## by default; drawn every frame while on, never while off, and only where it is shown (it is
## cosmetic: nothing of it is sent).

static var _material: StandardMaterial3D
static var _ground_material: StandardMaterial3D

## The cone's fill and its edges.
@export var cone_color := Color(1.0, 0.85, 0.2, 0.16)
@export var edge_color := Color(1.0, 0.85, 0.2, 0.9)
## The near radius ring.
@export var near_color := Color(1.0, 0.45, 0.2, 0.9)
## The hearing radius ring.
@export var hearing_color := Color(0.4, 0.7, 1.0, 0.45)
## A line to a belief seen now, remembered, heard or told.
@export var seen_color := Color(0.3, 1.0, 0.35, 0.95)
@export var memory_color := Color(1.0, 0.7, 0.15, 0.95)
@export var heard_color := Color(0.4, 0.7, 1.0, 0.95)
## The bars' background.
@export var bar_back_color := Color(0.0, 0.0, 0.0, 0.55)
## Height of the lowest awareness bar above the feet, and of each bar.
@export_range(0.5, 5.0, 0.05, "suffix:m") var bar_height := 2.45
@export_range(0.02, 0.5, 0.01, "suffix:m") var bar_thickness := 0.09
## Length of a full bar.
@export_range(0.1, 3.0, 0.05, "suffix:m") var bar_length := 0.9
## Width of a drawn line.
@export_range(0.005, 0.2, 0.005, "suffix:m") var line_width := 0.04
## Segments of the cone's arc and of a ring.
@export_range(6, 96) var segments := 32

var _senses: AiSenses
var _mesh := ImmediateMesh.new()


## The material every debug drawing of the senses uses: unshaded vertex colours with alpha.
static func line_material() -> StandardMaterial3D:
	if _material == null:
		_material = _new_material(true)
	return _material


## The material of what lies on the ground (the cone, the rings, the crosses): drawn behind walls
## and bodies, so the cone reads as a patch of floor.
static func ground_material() -> StandardMaterial3D:
	if _ground_material == null:
		_ground_material = _new_material(false)
	return _ground_material


static func _new_material(on_top: bool) -> StandardMaterial3D:
	var made := StandardMaterial3D.new()
	made.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	made.vertex_color_use_as_albedo = true
	made.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	made.cull_mode = BaseMaterial3D.CULL_DISABLED
	made.no_depth_test = on_top
	made.render_priority = 1 if on_top else 0
	return made


## Adds a flat ring of `radius` around `center` on the ground plane, `width` wide, as triangles
## (the surface is open with `PRIMITIVE_TRIANGLES`).
static func add_ring(
	drawing: ImmediateMesh, center: Vector3, radius: float, width: float, color: Color, steps := 32
) -> void:
	drawing.surface_set_color(color)
	var inner := maxf(radius - width * 0.5, 0.0)
	var outer := radius + width * 0.5
	for step in steps:
		var a := TAU * step / steps
		var b := TAU * (step + 1) / steps
		var da := Vector3(sin(a), 0.0, cos(a))
		var db := Vector3(sin(b), 0.0, cos(b))
		_quad(
			drawing,
			center + da * inner,
			center + da * outer,
			center + db * outer,
			center + db * inner
		)


static func _quad(drawing: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	drawing.surface_add_vertex(a)
	drawing.surface_add_vertex(b)
	drawing.surface_add_vertex(c)
	drawing.surface_add_vertex(a)
	drawing.surface_add_vertex(c)
	drawing.surface_add_vertex(d)


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = _mesh
	_senses = get_parent() as AiSenses
	set_process(visible)
	visibility_changed.connect(func() -> void: set_process(visible))


func _process(_delta: float) -> void:
	redraw()


## Draws what the senses hold now.
func redraw() -> void:
	_mesh.clear_surfaces()
	if _senses == null or _senses._character == null or _senses._character.profile == null:
		return
	var character := _senses._character
	var profile := character.profile
	var camera := get_viewport().get_camera_3d()
	var feet := character.global_position + Vector3.UP * 0.06
	var looks := _senses.sight and not character.is_dead()
	if not looks and not _senses.hearing and _senses.beliefs.size() == 0:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, ground_material())
	if looks:
		_draw_cone(feet, _senses.look_direction(), profile)
		add_ring(_mesh, feet, profile.near_radius, line_width * 1.5, near_color, segments)
	if _senses.hearing or not looks:
		add_ring(_mesh, feet, profile.hearing_range, line_width, hearing_color, segments * 2)
	for belief: AiBelief in _senses.beliefs.by_id.values():
		if not belief.seen_now:
			_cross(belief.last_position + Vector3.UP * 0.06, _color_of(belief))
	_mesh.surface_end()
	if _senses.beliefs.size() == 0:
		return
	var eye := _senses.eye_position()
	var right := camera.global_basis.x if camera != null else Vector3.RIGHT
	var up := camera.global_basis.y if camera != null else Vector3.UP
	var row := 0
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, line_material())
	for belief: AiBelief in _senses.beliefs.by_id.values():
		var color := _color_of(belief)
		_ribbon(eye, belief.last_position + Vector3.UP * 1.2, color, camera)
		_bar(
			character.global_position + Vector3.UP * (bar_height + row * bar_thickness * 1.6),
			belief,
			color,
			right,
			up,
			profile.suspicious_at
		)
		row += 1
	_mesh.surface_end()


func _color_of(belief: AiBelief) -> Color:
	if belief.seen_now:
		return seen_color
	if belief.source == AiBelief.Source.SEEN or belief.source == AiBelief.Source.TOUCHED:
		return memory_color
	return heard_color


func _draw_cone(feet: Vector3, look: Vector3, profile: AiProfile) -> void:
	var flat := Vector3(look.x, 0.0, look.z)
	if flat.length_squared() < 0.000001:
		return
	flat = flat.normalized()
	var half := deg_to_rad(profile.half_angle)
	var reach := profile.sight_range
	var steps := maxi(segments / 2, 4)
	var previous := feet + flat.rotated(Vector3.UP, -half) * reach
	for step in range(1, steps + 1):
		var turn := -half + 2.0 * half * step / steps
		var point := feet + flat.rotated(Vector3.UP, turn) * reach
		_mesh.surface_set_color(cone_color)
		_mesh.surface_add_vertex(feet)
		_mesh.surface_add_vertex(previous)
		_mesh.surface_add_vertex(point)
		_flat_line(previous, point, edge_color)
		previous = point
	_flat_line(feet, feet + flat.rotated(Vector3.UP, -half) * reach, edge_color)
	_flat_line(feet, feet + flat.rotated(Vector3.UP, half) * reach, edge_color)


# A line on the ground, `line_width` wide.
func _flat_line(a: Vector3, b: Vector3, color: Color) -> void:
	var along := b - a
	if along.length_squared() < 0.000001:
		return
	var side := along.cross(Vector3.UP).normalized() * line_width * 0.5
	_mesh.surface_set_color(color)
	_quad(_mesh, a - side, a + side, b + side, b - side)


# A line in the air that faces the camera.
func _ribbon(a: Vector3, b: Vector3, color: Color, camera: Camera3D) -> void:
	var along := b - a
	if along.length_squared() < 0.000001:
		return
	var toward := (camera.global_position - a) if camera != null else Vector3.UP
	var side := along.cross(toward).normalized() * line_width * 0.5
	if not side.is_finite():
		return
	_mesh.surface_set_color(color)
	_quad(_mesh, a - side, a + side, b + side, b - side)


func _cross(at: Vector3, color: Color) -> void:
	var size := 0.3
	_flat_line(at + Vector3(-size, 0.0, -size), at + Vector3(size, 0.0, size), color)
	_flat_line(at + Vector3(-size, 0.0, size), at + Vector3(size, 0.0, -size), color)


func _bar(
	center: Vector3, belief: AiBelief, color: Color, right: Vector3, up: Vector3, mark: float
) -> void:
	var start := center - right * bar_length * 0.5
	var high := up * bar_thickness
	_mesh.surface_set_color(bar_back_color)
	_quad(_mesh, start, start + right * bar_length, start + right * bar_length + high, start + high)
	var fill := color if not belief.believed else Color(1.0, 0.2, 0.15, 0.95)
	var length := bar_length * clampf(belief.awareness, 0.0, 1.0)
	_mesh.surface_set_color(fill)
	_quad(_mesh, start, start + right * length, start + right * length + high, start + high)
	var tick := start + right * bar_length * mark
	_mesh.surface_set_color(Color(1.0, 1.0, 1.0, 0.9))
	_quad(
		_mesh,
		tick - up * 0.02,
		tick + right * 0.02 - up * 0.02,
		tick + right * 0.02 + high * 1.3,
		tick + high * 1.3
	)
