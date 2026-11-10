class_name MinimapProjector
extends RefCounted
## The map's maths, with no nodes: where a place on the map plane lands on the widget. The
## widget's middle is `centre`; `turn` is the rotation applied to every offset from it (zero is
## north up, the view heading's angle difference to north when the map turns); `px_per_metre`
## is the zoom. Offsets come back in pixels from the widget's middle, +x right, +y down.

## The place at the widget's middle, on the map plane (x, z in 3D).
var centre := Vector2.ZERO
## Radians added to every offset's angle. Zero is north up.
var turn := 0.0
## How many pixels one metre takes.
var px_per_metre := 1.0
## Half the widget's side in pixels.
var half_extent := 100.0
## True for a round widget (the border is a circle), false for a square one.
var circular := true


## The map plane's north: the direction up is on a north-up map (-Z in 3D, -Y in 2D).
static func north() -> Vector2:
	return Vector2(0.0, -1.0)


## The turn that puts `heading` at the top of the widget.
static func turn_for_heading(heading: Vector2) -> float:
	return north().angle() - heading.angle()


## Sets how far the widget reaches from the middle to the border.
func set_range(metres: float) -> void:
	px_per_metre = half_extent / maxf(metres, 0.001)


## The range in metres from the middle to the border.
func metres_to_border() -> float:
	return half_extent / maxf(px_per_metre, 0.000001)


## The pixel offset from the widget's middle of the map-plane place `at`.
func to_local(at: Vector2) -> Vector2:
	return (at - centre).rotated(turn) * px_per_metre


## The map-plane place under the pixel offset `offset`.
func to_world(offset: Vector2) -> Vector2:
	return centre + (offset / px_per_metre).rotated(-turn)


## True when `offset` is inside the widget's shape, `margin` pixels in from the border.
func contains(offset: Vector2, margin := 0.0) -> bool:
	var limit := half_extent - margin
	if circular:
		return offset.length() <= limit
	return absf(offset.x) <= limit and absf(offset.y) <= limit


## `offset` pulled onto the border `inset` pixels in, keeping its direction from the middle.
func clamp_to_border(offset: Vector2, inset := 0.0) -> Vector2:
	var limit := half_extent - inset
	if circular:
		var length := offset.length()
		return offset if length <= limit else offset * (limit / length)
	var reach := maxf(absf(offset.x), absf(offset.y))
	return offset if reach <= limit else offset * (limit / reach)


## The rotation (radians) for an icon whose art points up, so that it points along the map-plane
## direction `heading` on the widget.
func icon_rotation(heading: Vector2) -> float:
	return heading.angle() + turn + PI * 0.5


## The rotation for an icon whose art points up so that it points along the pixel offset.
static func outward_rotation(offset: Vector2) -> float:
	return offset.angle() + PI * 0.5


## Where a map-plane place falls in a snapshot, as a texture coordinate (0 to 1, y down): the
## snapshot's middle is `source_centre`, turned by `source_turn`, covering `source_half` metres
## either side.
## The map shader does the same sum for every pixel; a test holds the live camera to it.
static func snapshot_uv(
	at: Vector2, source_centre: Vector2, source_turn: float, source_half: Vector2
) -> Vector2:
	var local := (at - source_centre).rotated(source_turn)
	return Vector2(0.5, 0.5) + local / (source_half * 2.0)
