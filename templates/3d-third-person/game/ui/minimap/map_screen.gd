class_name MapScreen
extends Control
## The full-screen map: a dimmed screen with one big `Minimap` that shows the whole map (every
## marker kind, north up) and opens and closes with an input action. It is the same widget as the
## small one with other settings (`Map` in `map_screen.tscn`), rendering once when it opens and
## again only now and then, and it costs nothing while closed.

## The map was opened.
signal opened
## The map was closed.
signal closed

## The input action that opens and closes the map (and closes it again from `ui_cancel`).
@export var toggle_action: StringName = &"map"
## The part of the map plane the screen shows, in metres: the map the game starts with. An empty
## rectangle leaves it to the sections.
@export var fit_bounds := Rect2(-26.0, -26.0, 52.0, 52.0)
## On: every `MinimapSection`'s footprint is added to `fit_bounds`, so a map that grows by sections
## is always shown whole.
@export var fit_to_sections := true
## How much room around the bounds, as a multiple of them.
@export_range(1.0, 1.5, 0.01) var fit_margin := 1.06
## How long the screen takes to fade in and out.
@export_range(0.0, 1.0, 0.01, "suffix:s") var fade_time := 0.15

var _tween: Tween
var _closing := false

@onready var _map: Minimap = %Map


func _ready() -> void:
	visible = false
	modulate.a = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if toggle_action != &"" and InputMap.has_action(toggle_action):
		if event.is_action_pressed(toggle_action):
			toggle()
			get_viewport().set_input_as_handled()
			return
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## The big map inside.
func minimap() -> Minimap:
	return _map


## True while the screen is up.
func is_open() -> bool:
	return visible and modulate.a > 0.0 and not _closing


## Opens the map when it is closed and closes it when it is open.
func toggle() -> void:
	if is_open():
		close()
	else:
		open()


## Shows the whole map.
func open() -> void:
	fit()
	visible = true
	_closing = false
	_map.request_refresh()
	_fade(1.0)
	opened.emit()


## Hides the map.
func close() -> void:
	if not visible:
		return
	_closing = true
	_fade(0.0)
	closed.emit()


## Centres the big map on the bounds and zooms it to cover them.
func fit() -> void:
	var bounds := fit_bounds
	var any := fit_bounds.has_area()
	if fit_to_sections:
		for node in get_tree().get_nodes_in_group(MinimapSection.GROUP):
			var section := node as MinimapSection
			if section == null:
				continue
			bounds = section.footprint() if not any else bounds.merge(section.footprint())
			any = true
	_map.range_max = maxf(_map.range_max, maxf(bounds.size.x, bounds.size.y))
	_map.fixed_centre = bounds.get_center()
	_map.jump_to_range(maxf(bounds.size.x, bounds.size.y) * 0.5 * fit_margin)


func _fade(to: float) -> void:
	if _tween != null:
		_tween.kill()
	if fade_time <= 0.0:
		modulate.a = to
		if to == 0.0:
			visible = false
		return
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", to, fade_time)
	if to == 0.0:
		_tween.tween_callback(func() -> void: visible = false)
