@tool
class_name LinesLabel
extends UILabel
## A wrapped label that keeps the height of `lines` lines of its own font whatever its text, so a
## container around it does not grow or shrink when the text changes (the inventory's details
## under the bag). A longer text is cut at the last line with an ellipsis. The height is read
## from the label's theme (font, size, line spacing and style), never typed in, so it follows the
## type scale and the interface size.

## How many lines the label always takes: set it to the longest text it shows.
@export_range(1, 12, 1) var lines := 4:
	set(value):
		lines = maxi(value, 1)
		_fit()


func _init() -> void:
	super._init()
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


func _ready() -> void:
	_fit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_fit()


## The height `count` lines of this label take, from its theme.
func height_of(count: int) -> float:
	var font := get_theme_font(&"font")
	var font_size := get_theme_font_size(&"font_size")
	var spacing := get_theme_constant(&"line_spacing")
	var box := get_theme_stylebox(&"normal")
	var height := count * font.get_height(font_size) + maxi(count - 1, 0) * spacing
	return ceilf(height + (box.get_minimum_size().y if box != null else 0.0))


## Whether the current text fits in `lines` without being cut.
func fits() -> bool:
	return get_line_count() <= lines


func _fit() -> void:
	max_lines_visible = lines
	custom_minimum_size.y = height_of(lines)
