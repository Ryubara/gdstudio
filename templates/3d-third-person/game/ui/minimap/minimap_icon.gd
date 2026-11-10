class_name MinimapIcon
extends TextureRect
## One icon on the minimap: a tinted texture the widget moves, turns and resizes every update.
## The widget keeps a pool of these (`MinimapIconPool`) and gives one to each marker on the map, so
## hundreds of markers cost no allocation after the first updates. Style the look of every icon
## here, in `minimap_icon.tscn`.

var _shown_size := -1.0


## Puts the icon with its middle at `centre` (pixels in the widget), `side` pixels across, turned
## by `angle` radians, tinted `tint`, drawn above lower `order`. Writes only what changed.
func place(
	picture: Texture2D, centre: Vector2, side: float, angle: float, tint: Color, order: int
) -> void:
	if texture != picture:
		texture = picture
	if not is_equal_approx(_shown_size, side):
		_shown_size = side
		size = Vector2(side, side)
		pivot_offset = Vector2(side, side) * 0.5
	var corner := centre - Vector2(side, side) * 0.5
	if position != corner:
		position = corner
	if not is_equal_approx(rotation, angle):
		rotation = angle
	if modulate != tint:
		modulate = tint
	if z_index != order:
		z_index = order
	if not visible:
		visible = true


## Hides the icon (it goes back to the pool).
func put_away() -> void:
	visible = false
