class_name InventoryCell
extends Button
## One slot of the inventory screen: a button that is one focus stop, showing an item's or a
## weapon's picture (`Icon`), its name when it has no picture (`Title`), a count or the ammunition
## (`Count`), a badge for the weapon in the hands (`Badge`) and a frame while it is picked up to be
## moved (`HeldFrame`). Its look is those nodes and the button's styles in `inventory_cell.tscn`;
## the script only fills them.
##
## A mouse or a finger can also drag one cell onto another (`dragged_onto`); a key, a pad or a tap
## press one cell, then the other.

## Another cell of the same screen was dragged onto this one.
signal dragged_onto(from: InventoryCell)
## The pointer or the focus came onto this cell (`on`) or left it.
signal shown(on: bool)

## What the cell stands for: `ITEM` a slot of the bag, `WEAPON` a slot of the loadout, `HOTBAR` a
## place of the player's `Hotbar` (a bag cell dropped on it is assigned there).
enum Kind { ITEM, WEAPON, HOTBAR }

## Whether the cell is a bag slot or a weapon.
var kind := Kind.ITEM
## The bag slot, the loadout slot (`WeaponLoadout.UNARMED` for the empty hands) or the hotbar place
## it shows.
var slot := 0
## Whether it shows something (an empty bag slot does not).
var filled := false

@onready var _icon: TextureRect = %Icon
@onready var _title: Label = %Title
@onready var _count: Label = %Count
@onready var _badge: Control = %Badge
@onready var _held_frame: Control = %HeldFrame


func _ready() -> void:
	focus_entered.connect(shown.emit.bind(true))
	focus_exited.connect(shown.emit.bind(false))
	mouse_entered.connect(shown.emit.bind(true))
	mouse_exited.connect(shown.emit.bind(false))


## Shows a picture (or `title` on a plate of `tint` when there is none) and `count_label`.
func show_thing(picture: Texture2D, title: String, count_label: String, tint: Color) -> void:
	filled = true
	_icon.texture = picture
	_icon.visible = picture != null
	_title.text = title
	_title.visible = picture == null
	_title.modulate = tint.lightened(0.4) if picture == null else Color.WHITE
	_count.text = count_label
	_count.visible = not count_label.is_empty()
	tooltip_text = title


## Shows an empty slot.
func show_empty() -> void:
	filled = false
	_icon.texture = null
	_icon.visible = false
	_title.visible = false
	_count.visible = false
	tooltip_text = ""
	set_held(false)


## Shows an empty slot with `caption` on it (a hotbar place's key).
func show_caption(caption: String) -> void:
	show_empty()
	_title.text = caption
	_title.modulate = Color(1.0, 1.0, 1.0, 0.6)
	_title.visible = not caption.is_empty()


## Shows or hides the badge of the weapon in the hands (or on its way there).
func set_equipped(on: bool) -> void:
	_badge.visible = on


## Whether the badge shows.
func is_equipped() -> bool:
	return _badge.visible


## Shows or hides the frame of a cell picked up to be moved.
func set_held(on: bool) -> void:
	_held_frame.visible = on


## Whether the cell is picked up.
func is_held() -> bool:
	return _held_frame.visible


## The count or ammunition text shown ("" when none).
func count_text() -> String:
	return _count.text if _count.visible else ""


func _get_drag_data(_at_position: Vector2) -> Variant:
	if kind != Kind.ITEM or not filled:
		return null
	var picture := TextureRect.new()
	picture.texture = _icon.texture
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size = size * 0.8
	picture.modulate.a = 0.8
	set_drag_preview(picture)
	return self


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var from := data as InventoryCell
	if from == null or from == self or from.kind != Kind.ITEM:
		return false
	return kind == Kind.ITEM or (kind == Kind.HOTBAR and from.filled)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	dragged_onto.emit(data as InventoryCell)
