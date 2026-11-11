@tool
class_name HudHotbar
extends HudSlotRow
## The hotbar: a row of quick-access places, as many as the player's `Hotbar` has (its
## `place_count`), each showing the item it names with the count the bag holds and the key that
## uses it (`hotbar_1`... : 3, 4, 5, 6, after the weapon keys). An empty place is its key alone, an
## item that has run out stays dim with its 0. A use flashes the place (`flash_time`).
##
## It reads the `Hotbar` beside the player's `Inventory` (the data the inventory screen shows and
## assigns from) and never writes: a key or a tap on the place uses it through `PlayerInput`.

@export_group("Look")
## How long a place flashes when it is used, in seconds. Zero: no flash.
@export_range(0.0, 2.0, 0.05, "suffix:s") var flash_time := 0.3
## How much a used place grows at the start of its flash.
@export_range(1.0, 2.0, 0.01) var flash_scale := 1.15

@export_group("Places")
## How many places the editor shows (in the game, the player's `Hotbar.place_count`).
@export_range(1, 12, 1) var editor_places := 4:
	set(value):
		editor_places = value
		if Engine.is_editor_hint() and is_node_ready():
			_show_in_editor()

var _hotbar: Hotbar


## The hotbar shown (null: none).
func hotbar() -> Hotbar:
	return _hotbar


func _on_bound(node: Node) -> void:
	_hotbar = Hotbar.of(node)
	refresh_on(_hotbar, &"changed")
	if _hotbar != null and not _hotbar.used.is_connected(_on_used):
		_hotbar.used.connect(_on_used)


func _let_go() -> void:
	if is_instance_valid(_hotbar) and _hotbar.used.is_connected(_on_used):
		_hotbar.used.disconnect(_on_used)
	super()
	_hotbar = null


func _has_data() -> bool:
	return _bound != null and _hotbar != null and is_instance_valid(_hotbar)


func _place_count() -> int:
	return _hotbar.place_count if _has_data() else 0


func _editor_place_count() -> int:
	return editor_places


func _fill_place(cell: HudSlot, place: int) -> void:
	var item := _hotbar.item_at(place)
	if item == null:
		cell.show_place(key_text(place), null, "", HudSlot.State.EMPTY)
		cell.tooltip_text = ""
		return
	var count := _hotbar.count_at(place)
	var state := HudSlot.State.IDLE if count > 0 else HudSlot.State.SPENT
	cell.show_place(key_text(place), item.icon, str(count), state)
	cell.tooltip_text = item.display_name


func _on_used(place: int, _item: ItemDef) -> void:
	update()
	if flash_time <= 0.0 or place < 0 or place >= _cells.size():
		return
	var cell := _cells[place]
	cell.pivot_offset = cell.size / 2.0
	cell.scale = Vector2.ONE * flash_scale
	cell.modulate = Color(1.6, 1.6, 1.6)
	var tween := cell.create_tween().set_parallel()
	tween.tween_property(cell, ^"scale", Vector2.ONE, flash_time)
	tween.tween_property(cell, ^"modulate", Color.WHITE, flash_time)
