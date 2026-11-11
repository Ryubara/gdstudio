class_name AiNavDebug
extends MeshInstance3D
## Draws an `AiNavigator`'s path (a line through its points, a link's stretch in another colour)
## and the point it steers to (a cross), in the world, on top of everything. The navigator makes
## it when its `debug` goes on and frees it when it goes off; it costs nothing while off.

## The path's colour.
const PATH_COLOUR := Color(0.2, 0.85, 1.0)
## A link's stretch.
const LINK_COLOUR := Color(1.0, 0.75, 0.2)
## The point it steers to.
const STEER_COLOUR := Color(1.0, 0.3, 0.6)
## A path that ends short of the goal: the line from its end to the goal.
const SHORT_COLOUR := Color(1.0, 0.25, 0.2)
## Lifted off the floor (metres) so the line is not hidden in it.
const LIFT := 0.12

var _lines := ImmediateMesh.new()


func _init() -> void:
	name = "NavDebug"
	top_level = true
	mesh = _lines
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	material.render_priority = 10
	material_override = material


## Draws `path` from point `from` on, the point `steer` and, when the path ends more than a metre
## from `goal`, the gap.
func draw(path: AiNavPath, from: Vector3, steer: Vector3, goal: Vector3) -> void:
	_lines.clear_surfaces()
	var points := path.points
	if points.is_empty():
		return
	_lines.surface_begin(Mesh.PRIMITIVE_LINES)
	var previous := from
	for index in range(maxi(path.index, 1), points.size()):
		var colour := LINK_COLOUR if path.link_at(index - 1) != 0 else PATH_COLOUR
		_segment(previous if index == path.index else points[index - 1], points[index], colour)
		previous = points[index]
	if steer.is_finite():
		var lifted := steer + Vector3.UP * LIFT
		for axis: Vector3 in [Vector3(0.25, 0, 0.25), Vector3(0.25, 0, -0.25)]:
			_lines.surface_set_color(STEER_COLOUR)
			_lines.surface_add_vertex(lifted - axis)
			_lines.surface_set_color(STEER_COLOUR)
			_lines.surface_add_vertex(lifted + axis)
	var last := points[points.size() - 1]
	if goal.is_finite() and AiNavPath.flat(goal - last).length() > 1.0:
		_segment(last, goal, SHORT_COLOUR)
	_lines.surface_end()


## Clears the drawing.
func clear() -> void:
	_lines.clear_surfaces()


func _segment(from: Vector3, to: Vector3, colour: Color) -> void:
	_lines.surface_set_color(colour)
	_lines.surface_add_vertex(from + Vector3.UP * LIFT)
	_lines.surface_set_color(colour)
	_lines.surface_add_vertex(to + Vector3.UP * LIFT)
