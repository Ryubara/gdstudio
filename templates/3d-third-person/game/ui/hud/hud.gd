@tool
class_name Hud
extends CanvasLayer
## The heads-up display: a layer that holds its parts (`HudWidget` scenes) in screen regions. A part
## is added by dropping its scene into a region node in the editor (or `add_widget()` at run
## time); the region stacks it and the part finds the player and its data by itself.
##
## Regions, all in `Root`:
## - `Center`: the whole screen, never inset (the crosshair sits at the true middle, which is where
##   the weapon aims).
## - `SafeArea`: the screen less the device's safe area and `margin`, holding `TopLeft`,
##   `TopCenter`, `TopRight`, `BottomLeft`, `BottomCenter` and `BottomRight`: columns that grow
##   away from their corner and take no room for a hidden part. `MinimapSlot` (in `TopRight`) is
##   where the minimap scene goes.
##
## One `Theme` (`theme`) styles every part: edit `hud_theme.tres` or point `theme` at another one
## to restyle the whole HUD. On a phone the HUD grows until its smallest text is `min_text_size`
## CSS pixels high, and while the touch controls show, a part with a `touch_region` moves there
## (the bottom corners are the thumbs').

## The touch controls came up or went away.
signal touch_layout_changed(on: bool)

## The regions of the `SafeArea`, by node name.
const REGIONS: Array[StringName] = [
	&"TopLeft", &"TopCenter", &"TopRight", &"BottomLeft", &"BottomCenter", &"BottomRight"
]

@export_group("Look")
## Styles every part. Parts get their sizes, colours and cards from here and from nowhere else.
@export var theme: Theme:
	set(value):
		theme = value
		if root != null:
			root.theme = value
## The room kept between the parts and the screen edge, on top of the device's safe area.
@export_range(0.0, 200.0, 1.0, "suffix:px") var margin := 32.0:
	set(value):
		margin = value
		fit()

@export_group("Phone")
## The HUD grows until its smallest text is this high on the device, in CSS pixels (a page's
## pixels, not the screen's). On a desktop it stays at its size.
@export_range(8.0, 40.0, 0.5, "suffix:px") var min_text_size := 14.0:
	set(value):
		min_text_size = value
		fit()
## The most the HUD grows.
@export_range(1.0, 6.0, 0.1) var max_scale := 3.0:
	set(value):
		max_scale = value
		fit()
## Device pixels per CSS pixel. Zero asks the device (the page's ratio on the web); a capture or
## a test sets it to look like a phone.
@export_range(0.0, 6.0, 0.05) var pixel_ratio := 0.0:
	set(value):
		pixel_ratio = value
		fit()
## The touch controls whose showing moves the parts that have a `touch_region`.
@export var touch_controls: TouchControls

@export_group("Data")
## The player every part reads. Empty leaves each part to look for the first node of the `player`
## group, which is right for a game with one player; a game with more than one sets this to the
## one this screen shows (the rig's `Player`).
@export var player: Node:
	set(value):
		var replaced := player
		player = value
		_bind_parts(replaced)

@export_group("Parts")
## The box everything is scaled in: the screen divided by the HUD's scale.
@export var root: Control
## The part of the screen a safe area leaves.
@export var safe_area: Control
## Where the minimap scene goes: it is shown while it holds something.
@export var minimap_slot: Control

## True while the touch controls show.
var touch_layout := false

var _homes: Dictionary[Control, Control] = {}


func _ready() -> void:
	if root != null:
		root.theme = theme
	if minimap_slot != null:
		minimap_slot.child_order_changed.connect(_show_minimap_slot)
		_show_minimap_slot()
	if Engine.is_editor_hint():
		return
	get_viewport().size_changed.connect(fit)
	fit()
	_bind_parts()
	if touch_controls != null:
		touch_controls.shown_changed.connect(set_touch_layout)
		set_touch_layout(touch_controls.is_shown())


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	for part_name: String in ["root", "safe_area"]:
		if get(part_name) == null:
			warnings.append(
				"Set `%s` in the Parts group: the HUD places its regions in it." % part_name
			)
	return warnings


## The region node called `region_name` (one of `REGIONS`), or null.
func region(region_name: StringName) -> Control:
	if safe_area == null:
		return null
	return safe_area.get_node_or_null(NodePath(region_name)) as Control


## Puts `widget` (a node, or a scene to instance) at the end of a region and returns it.
func add_widget(widget: Variant, region_name: StringName) -> Control:
	var node: Control = (widget as PackedScene).instantiate() if widget is PackedScene else widget
	var target := region(region_name)
	assert(target != null, "No HUD region called %s." % region_name)
	target.add_child(node)
	_bind_parts()
	return node


## Every part in the regions, wherever it stands now.
func widgets() -> Array[HudWidget]:
	var found: Array[HudWidget] = []
	if root != null:
		for node in root.find_children("*", "HudWidget", true, false):
			found.append(node as HudWidget)
	return found


## The part of the canvas a device's safe area leaves, in canvas pixels (`margin` is applied by
## `fit()`).
func safe_rect() -> Rect2:
	var view := get_viewport().get_visible_rect()
	var screen := Vector2(DisplayServer.screen_get_size())
	var window := Vector2(DisplayServer.window_get_size())
	if screen.x <= 0.0 or screen.y <= 0.0 or window.distance_to(screen) > 2.0:
		return view
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if safe.size.x <= 0.0:
		return view
	var view_scale := view.size / screen
	var left := maxf(safe.position.x, 0.0) * view_scale.x
	var top := maxf(safe.position.y, 0.0) * view_scale.y
	var right := maxf(screen.x - safe.end.x, 0.0) * view_scale.x
	var bottom := maxf(screen.y - safe.end.y, 0.0) * view_scale.y
	return Rect2(
		view.position + Vector2(left, top), view.size - Vector2(left + right, top + bottom)
	)


## How high the screen is for a person, in CSS pixels: a page's own height on the web (the canvas
## element's box, so a phone's pixel ratio and an iframe do not matter), else the window's pixels
## over `pixel_ratio` (or the device's scale).
func css_height() -> float:
	var window_height := float(get_window().size.y)
	if pixel_ratio > 0.0:
		return window_height / pixel_ratio
	if OS.has_feature("web"):
		var box: Variant = JavaScriptBridge.eval(
			"document.querySelector('canvas').getBoundingClientRect().height"
		)
		if typeof(box) in [TYPE_FLOAT, TYPE_INT] and box > 0.0:
			return float(box)
	return window_height / maxf(DisplayServer.screen_get_scale(), 0.5)


## How much the HUD is enlarged now: 1 on a desktop, more where its smallest text would be under
## `min_text_size` CSS pixels.
func text_scale() -> float:
	var smallest := _smallest_font_size()
	var css_per_canvas := css_height() / maxf(get_viewport().get_visible_rect().size.y, 1.0)
	if smallest <= 0.0 or css_per_canvas <= 0.0:
		return 1.0
	return clampf(min_text_size / (smallest * css_per_canvas), 1.0, max_scale)


## Sizes the root to the screen at the HUD's scale and insets the safe area. Called when the
## window changes size or an export changes.
func fit() -> void:
	if root == null or not is_inside_tree() or Engine.is_editor_hint():
		return
	var view := get_viewport().get_visible_rect()
	var grow := text_scale()
	root.scale = Vector2.ONE * grow
	root.position = Vector2.ZERO
	root.size = view.size / grow
	if safe_area != null:
		var inner := safe_rect()
		safe_area.offset_left = (inner.position.x - view.position.x + margin) / grow
		safe_area.offset_top = (inner.position.y - view.position.y + margin) / grow
		safe_area.offset_right = (inner.end.x - view.end.x - margin) / grow
		safe_area.offset_bottom = (inner.end.y - view.end.y - margin) / grow


## Moves the parts that have a `touch_region` there (on) or back where they were (off).
func set_touch_layout(on: bool) -> void:
	if on == touch_layout:
		return
	touch_layout = on
	if on:
		for widget in widgets():
			if widget.touch_region != "Stay" and not _homes.has(widget):
				var target := region(StringName(widget.touch_region))
				if target != null and target != widget.get_parent():
					_homes[widget] = widget.get_parent() as Control
					widget.reparent(target, false)
	else:
		for widget: Control in _homes.keys():
			if is_instance_valid(widget) and is_instance_valid(_homes[widget]):
				widget.reparent(_homes[widget], false)
		_homes.clear()
	touch_layout_changed.emit(on)


# Points the parts that have no player of their own (or had the one `player` replaced) at
# `player`. A part given a player in the editor or in code keeps it.
func _bind_parts(replaced: Node = null) -> void:
	if (player == null and replaced == null) or Engine.is_editor_hint():
		return
	for widget in widgets():
		if widget.player == null or widget.player == replaced:
			widget.player = player


func _smallest_font_size() -> float:
	if theme == null:
		return 0.0
	var smallest := float(theme.default_font_size)
	for type_name in theme.get_font_size_type_list():
		for item in theme.get_font_size_list(type_name):
			smallest = minf(smallest, float(theme.get_font_size(item, type_name)))
	return smallest


func _show_minimap_slot() -> void:
	if minimap_slot != null:
		minimap_slot.visible = Engine.is_editor_hint() or minimap_slot.get_child_count() > 0
