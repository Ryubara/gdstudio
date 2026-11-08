@tool
class_name TouchStick
extends Control
## The look of the floating stick: a ring, a thinner ring where the push counts as a sprint, and
## a knob, all real nodes of `touch_stick.tscn` (restyle them there). The node itself is the
## stick's resting place: drag it in the 2D editor to move where the stick waits. While a thumb
## is down, `TouchControls` calls `touch()` and the rings move to where the thumb landed.

## How solid the ring is while a thumb is on it, and while the stick waits.
const RING_TOUCHING := 1.0
const RING_RESTING := 0.45
## How solid the knob is while a thumb is on it, and while the stick waits.
const KNOB_TOUCHING := 0.8
const KNOB_RESTING := 0.35
## The knob's size, as a share of the ring's radius.
const KNOB_SHARE := 0.36

## The ring's radius in pixels: how far the thumb goes for a full push. `TouchControls` sets it
## from its `stick_radius`.
var radius := 150.0
## Where the sprint ring is, as a share of the radius. Zero hides it. `TouchControls` sets it from
## its `sprint_ring`.
var sprint_ring := 0.92


func _ready() -> void:
	rest()


## Sizes the rings: `ring_radius` is the thumb's full push, `sprint_share` where the sprint ring is.
func configure(ring_radius: float, sprint_share: float) -> void:
	radius = ring_radius
	sprint_ring = sprint_share
	_lay_out()


## The stick waits at its place, faint.
func rest() -> void:
	var pad := _part("Pad")
	if pad == null:
		return
	pad.position = Vector2.ZERO
	_show_state(false, Vector2.ZERO)


## A thumb is down: the rings stand at `origin` and the knob at `thumb`, both in canvas pixels.
func touch(origin: Vector2, thumb: Vector2) -> void:
	var pad := _part("Pad")
	if pad == null:
		return
	pad.position = origin - global_position
	_show_state(true, (thumb - origin).limit_length(radius))


## The pad's middle in canvas pixels: the stick's resting place until a thumb lands.
func home() -> Vector2:
	return global_position


func _lay_out() -> void:
	_centre(_part("Ring"), radius)
	_centre(_part("SprintRing"), radius * sprint_ring)
	_centre(_part("Knob"), radius * KNOB_SHARE)
	var sprint := _part("SprintRing")
	if sprint != null:
		sprint.visible = sprint_ring > 0.0


func _centre(part: Control, part_radius: float) -> void:
	if part != null:
		part.size = Vector2.ONE * part_radius * 2.0
		part.position = -Vector2.ONE * part_radius


func _show_state(touching: bool, knob_offset: Vector2) -> void:
	var ring := _part("Ring")
	if ring != null:
		ring.modulate.a = RING_TOUCHING if touching else RING_RESTING
	var knob := _part("Knob")
	if knob != null:
		knob.position = knob_offset - knob.size / 2.0
		knob.modulate.a = KNOB_TOUCHING if touching else KNOB_RESTING
	var sprint := _part("SprintRing")
	if sprint != null:
		sprint.modulate.a = RING_RESTING


func _part(part_name: String) -> Control:
	return get_node_or_null("%" + part_name) as Control
