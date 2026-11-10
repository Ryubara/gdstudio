class_name ImpactMark
extends MeshInstance3D
## One mark on a surface: a unit quad (+Z out of the surface) that `Impacts` places, scales and
## turns. It hangs on the body it landed on, so it goes where the body goes and with it when the
## body is freed. The only state it keeps is its age and how much of it is left (`fade`).

## Seconds since it was placed.
var age := 0.0
## The surface it was made for (its `ImpactSurface.surface_name`).
var surface_name: StringName = &""

var _fade := 1.0


## How much of the mark is left, from 1 (whole) to 0 (gone). The material draws it through its
## instance uniform `fade`.
func fade() -> float:
	return _fade


## Sets how much of the mark is left.
func set_fade(value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	if is_equal_approx(value, _fade):
		return
	_fade = value
	set_instance_shader_parameter(&"fade", value)


## Starts the mark again as a new one (a recycled mark is the oldest taken for a new hit).
func restart(surface: StringName) -> void:
	age = 0.0
	surface_name = surface
	_fade = 1.0
	set_instance_shader_parameter(&"fade", 1.0)
