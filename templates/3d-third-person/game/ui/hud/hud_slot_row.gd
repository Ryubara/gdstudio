@tool
class_name HudSlotRow
extends HudWidget
## The base of a HUD row of numbered places (the weapon slots, the hotbar): one `HudSlot` a place,
## made from `cell_scene` in `row`, each showing the key of its action (`action_format` with the
## place's number, read from the Input Map, so a rebound key shows the new one). A subclass says
## how many places there are (`_place_count()`) and fills each (`_fill_place()`).
##
## The places are made by code because their number is a setting; the editor shows them too (a
## `@tool` script), filled with their keys. Restyle a place in `hud_slot.tscn` and the theme.
##
## On a touch screen each place is a place of the HUD a finger presses: `touch_zones()` gives the
## `Hud` (and through it the touch layer) each shown place's box and action.

@export_group("Keys")
## The input action of place `n` (from 1), as a format: `weapon_%d`, `hotbar_%d`.
@export var action_format := "weapon_%d"
## The number shown on place 1 when its action has no key (in the editor, or a game without the
## action): the next places count on from it.
@export_range(0, 9, 1) var first_key_number := 1

@export_group("Parts")
## The container the places go in.
@export var row: Container
## The scene each place is made from.
@export var cell_scene: PackedScene = preload("res://ui/hud/hud_slot.tscn")

var _cells: Array[HudSlot] = []


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		_show_in_editor.call_deferred()


## The places, in order.
func cells() -> Array[HudSlot]:
	return _cells.duplicate()


## The action of place `place` (from 0).
func action_of(place: int) -> StringName:
	return StringName(action_format % (place + 1))


## What place `place`'s key reads: the first key on its action, else its number.
func key_text(place: int) -> String:
	var action := action_of(place)
	if not Engine.is_editor_hint() and InputMap.has_action(action):
		for event in InputMap.action_get_events(action):
			var key := event as InputEventKey
			if key == null:
				continue
			if key.physical_keycode != KEY_NONE:
				return key.as_text_physical_keycode()
			return key.as_text_keycode()
	return str((first_key_number + place) % 10)


## Each shown place's box on the canvas and its action, for a finger: `{rect, action}`. A place
## whose action the project lacks is left out.
func touch_zones() -> Array[Dictionary]:
	var zones: Array[Dictionary] = []
	if not is_visible_in_tree():
		return zones
	for place in _cells.size():
		var action := action_of(place)
		var cell := _cells[place]
		if not cell.visible or not InputMap.has_action(action):
			continue
		var transform := cell.get_global_transform()
		zones.append(
			{"rect": Rect2(transform.origin, transform.basis_xform(cell.size)), "action": action}
		)
	return zones


func _refresh() -> void:
	_make_cells(_place_count())
	for place in _cells.size():
		_fill_place(_cells[place], place)


## Override: how many places to show.
func _place_count() -> int:
	return 0


## Override: shows place `place` in `cell` (`cell.show_place(...)`).
func _fill_place(cell: HudSlot, place: int) -> void:
	cell.show_place(key_text(place), null, "", HudSlot.State.EMPTY)


## Override: how many places the editor shows.
func _editor_place_count() -> int:
	return _place_count()


func _make_cells(count: int) -> void:
	if row == null or cell_scene == null:
		return
	while _cells.size() > count:
		var cell: HudSlot = _cells.pop_back()
		row.remove_child(cell)
		cell.queue_free()
	while _cells.size() < count:
		var cell := cell_scene.instantiate() as HudSlot
		cell.name = "Place%d" % (_cells.size() + 1)
		row.add_child(cell)
		_cells.append(cell)


func _show_in_editor() -> void:
	_make_cells(_editor_place_count())
	for place in _cells.size():
		_cells[place].show_place(key_text(place), null, "", HudSlot.State.EMPTY)
