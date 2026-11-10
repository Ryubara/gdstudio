class_name MinimapIcon
extends Sprite2D
## One icon on the minimap: a tinted sprite the widget moves, turns and resizes every update. The
## widget keeps a pool of these (`MinimapIconPool`) and gives one to each marker on the map, so
## hundreds of markers cost no allocation after the first updates. It is a `Sprite2D` and not a
## `Control` because moving a sprite costs a fraction of moving a control (the cost numbers are in
## the minimap docs). Style the look of every icon here, in `minimap_icon.tscn`.

## The marker pass of the widget that last placed this icon (a pass that does not place it
## gives the icon back to the pool).
var seen_in_pass := 0
var _side := -1.0


## Puts the icon with its middle at `centre` (pixels in the widget), `side` pixels across, turned
## by `angle` radians, tinted `tint`, drawn above lower `order`. Writes only what changed.
func place(
	picture: Texture2D, centre: Vector2, side: float, angle: float, tint: Color, order: int
) -> void:
	if texture != picture:
		texture = picture
		_side = -1.0
	if picture != null and not is_equal_approx(_side, side):
		_side = side
		var extent := maxf(picture.get_width(), picture.get_height())
		scale = Vector2.ONE * (side / maxf(extent, 1.0))
	if position != centre:
		position = centre
	if not is_equal_approx(rotation, angle):
		rotation = angle
	if modulate != tint:
		modulate = tint
	if z_index != order:
		z_index = order
	if not visible:
		visible = true


## How many pixels across the icon is drawn (its longer side).
func drawn_side() -> float:
	if texture == null:
		return 0.0
	return maxf(texture.get_width(), texture.get_height()) * scale.x


## Hides the icon (it goes back to the pool).
func put_away() -> void:
	visible = false
