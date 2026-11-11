class_name InventoryScreen
extends UIScreen
## The inventory: the player's live model on the left (`Preview`, turned by a drag or the right
## stick) and on the right the weapons it carries and the slots of its bag. Opened by the
## `ScreenHost` from the `inventory` action (I, a pad's right shoulder, the touch layer's Bag
## button) and closed by the same action, Esc, a pad's B or Close.
##
## - **Weapons** are read from the player's `WeaponLoadout` each time the screen draws (its slots,
##   then the empty hands), so a weapon added to the loadout shows. Pressing one asks the player's
##   `PlayerInput` for it (`request_weapon`): it is switched to by the same weapon presses a player
##   makes, so the screen adds nothing to the command and nothing to send.
## - **Items** are the player's `Inventory`. Press a slot to pick its stack up, then press another
##   to put it there (it fills a stack of the same kind or swaps); press it again or go back to put
##   it down where it was. A mouse or a finger can drag one slot onto another. Drop leaves the
##   picked or last shown stack in the world in front of the player.
##
## Whether the game stops behind it is the player's option `pause_setting` (Settings > Controls);
## the host asks `pauses_game()`. With the game running the player's own input is off while the
## screen is up (`stop_player_input`), so a click on a slot fires nothing.

## A weapon was chosen on the screen (`WeaponLoadout.UNARMED` for the empty hands).
signal weapon_chosen(slot: int)
## A bag slot was picked up (`slot`) or put down (-1).
signal item_picked(slot: int)

@export_group("Nodes")
## The player whose bag and weapons are shown. Empty: the first node of the group `player`.
@export var player: Player
## The scene each slot is made from.
@export var cell_scene: PackedScene = preload("res://ui/inventory/inventory_cell.tscn")

@export_group("Pausing")
## The `Settings` key that says whether the game stops while the screen is open.
@export var pause_setting: StringName = &"controls/pause_in_inventory"
## Whether the game stops when there is no such setting (a game without the `Settings` autoload).
@export var pauses_by_default := true
## Turns the player's input off while the screen is up, so a click or a stick on the screen does
## not also move, aim or fire (it matters when the game keeps running).
@export var stop_player_input := true

var _inventory: Inventory
var _loadout: WeaponLoadout
var _input: PlayerInput
var _weapon_cells: Array[InventoryCell] = []
var _item_cells: Array[InventoryCell] = []
var _weapon_round: Array[int] = []
var _picked := -1
var _shown_cell: InventoryCell
var _input_was := true
var _input_held := false

@onready var _preview: ModelPreview = %Preview
@onready var _weapons: Container = %Weapons
@onready var _grid: GridContainer = %Grid
@onready var _items_caption: Control = %ItemsCaption
@onready var _detail_name: Label = %DetailName
@onready var _detail_text: LinesLabel = %DetailText
@onready var _drop: Button = %DropButton
@onready var _close: Button = %CloseButton


func _ready() -> void:
	super._ready()
	_drop.pressed.connect(_on_drop)
	_close.pressed.connect(_on_close)
	bind(player if player != null else get_tree().get_first_node_in_group(&"player") as Player)


func _exit_tree() -> void:
	_give_input_back()


func _unhandled_input(event: InputEvent) -> void:
	# Going back with a stack picked up puts it down instead of closing the screen.
	if _picked >= 0 and event.is_action_pressed(&"ui_cancel"):
		pick(-1)
		get_viewport().set_input_as_handled()


## Whether the game stops while the screen is open: the player's option, else the default.
func pauses_game() -> bool:
	var settings := get_node_or_null(^"/root/Settings")
	if settings != null and settings.has_method(&"get_value"):
		var value: Variant = settings.call(&"get_value", pause_setting)
		if value is bool:
			return value
	return pauses_by_default


## Shows `who`'s bag and weapons (null shows nothing).
func bind(who: Player) -> void:
	_unlink()
	player = who
	_inventory = who.inventory if who != null else null
	_loadout = who.loadout if who != null else null
	_input = who.controller as PlayerInput if who != null else null
	_preview.model_slot = who.model if who != null else null
	_link()
	_build_items()
	refresh()


func screen_enter() -> void:
	refresh()
	if stop_player_input and player != null and not _input_held:
		_input_was = player.input_enabled
		_input_held = true
		player.input_enabled = false
	super.screen_enter()


## Reads the bag and the loadout again and redraws every cell.
func refresh() -> void:
	if not is_node_ready():
		return
	_build_weapons()
	for cell in _weapon_cells:
		_fill_weapon(cell)
	for cell in _item_cells:
		_fill_item(cell)
	_items_caption.visible = _inventory != null
	_grid.visible = _inventory != null
	_link_focus()
	_show_detail(_shown_cell)


## The weapon cells, in the loadout's round.
func weapon_cells() -> Array[InventoryCell]:
	return _weapon_cells.duplicate()


## The bag's cells, one a slot.
func item_cells() -> Array[InventoryCell]:
	return _item_cells.duplicate()


## The model preview.
func preview() -> ModelPreview:
	return _preview


## The bag slot picked up to be moved, or -1.
func picked() -> int:
	return _picked


## Picks up the stack in bag slot `slot` to move it (-1 puts it down).
func pick(slot: int) -> void:
	if slot >= 0 and (_inventory == null or _inventory.is_empty(slot)):
		slot = -1
	_picked = slot
	for cell in _item_cells:
		cell.set_held(cell.slot == _picked)
	_update_drop()
	item_picked.emit(_picked)


## Presses a weapon: asks the player for it.
func choose_weapon(slot: int) -> void:
	if _input == null or _loadout == null or not WeaponChooser.can_reach(_loadout, slot):
		return
	_input.request_weapon(slot)
	weapon_chosen.emit(slot)
	refresh()


## Presses a bag slot: picks it up, or puts the picked stack there.
func press_item(slot: int) -> void:
	if _inventory == null:
		return
	if _picked < 0:
		pick(slot)
	elif _picked == slot:
		pick(-1)
	else:
		_inventory.move(_picked, slot)
		pick(-1)
	_show_detail(_shown_cell)


## Drops the picked stack, or the stack of the last shown slot. Returns what was placed.
func drop_selected() -> Node:
	var slot := _drop_slot()
	if slot < 0:
		return null
	var placed := _inventory.drop(slot)
	pick(-1)
	_show_detail(_shown_cell)
	return placed


func _drop_slot() -> int:
	if _inventory == null:
		return -1
	if _picked >= 0:
		return _picked
	if _shown_cell != null and _shown_cell.kind == InventoryCell.Kind.ITEM:
		return _shown_cell.slot
	return -1


func _build_weapons() -> void:
	var round_now: Array[int] = WeaponChooser.round_of(_loadout) if _loadout != null else []
	if round_now == _weapon_round and _weapon_cells.size() == round_now.size():
		return
	_weapon_round = round_now
	for cell in _weapon_cells:
		cell.queue_free()
		_weapons.remove_child(cell)
	_weapon_cells.clear()
	for slot in _weapon_round:
		var cell := _make_cell(_weapons, InventoryCell.Kind.WEAPON, slot)
		_weapon_cells.append(cell)


func _build_items() -> void:
	for cell in _item_cells:
		_grid.remove_child(cell)
		cell.queue_free()
	_item_cells.clear()
	_picked = -1
	if _inventory == null:
		return
	for slot in _inventory.slot_count:
		_item_cells.append(_make_cell(_grid, InventoryCell.Kind.ITEM, slot))


func _make_cell(parent: Node, kind: InventoryCell.Kind, slot: int) -> InventoryCell:
	var cell := cell_scene.instantiate() as InventoryCell
	cell.kind = kind
	cell.slot = slot
	cell.name = (
		("Weapon%d" % slot if slot >= 0 else "Unarmed")
		if kind == InventoryCell.Kind.WEAPON
		else "Slot%d" % slot
	)
	parent.add_child(cell)
	cell.pressed.connect(_on_cell_pressed.bind(cell))
	cell.shown.connect(_on_cell_shown.bind(cell))
	cell.dragged_onto.connect(_on_dragged_onto.bind(cell))
	return cell


func _fill_weapon(cell: InventoryCell) -> void:
	var definition: WeaponDef = (
		_loadout.unarmed if cell.slot == WeaponLoadout.UNARMED else _loadout.slots[cell.slot]
	)
	var ammo := ""
	if definition.uses_ammo():
		var counts := _loadout.ammo_of(cell.slot)
		ammo = "%d/%d" % [counts[0], counts[1]]
	cell.show_thing(definition.icon, definition.display_name, ammo, Color(0.7, 0.72, 0.8))
	cell.set_equipped(cell.slot == _chosen_weapon())


func _fill_item(cell: InventoryCell) -> void:
	var item := _inventory.item_at(cell.slot)
	if item == null:
		cell.show_empty()
		return
	var count := _inventory.count_at(cell.slot)
	cell.show_thing(item.icon, item.display_name, item.count_text(count), item.tint)
	cell.set_held(cell.slot == _picked)


# The weapon in the hands, or the one a request or a switch is heading for.
func _chosen_weapon() -> int:
	if _input != null and _input.weapon_request() != PlayerInput.NO_REQUEST:
		return _input.weapon_request()
	return _loadout.target_slot() if _loadout != null else PlayerInput.NO_REQUEST


# Every cell's neighbours by hand: Godot's guess by geometry jumps between the weapons' row, the
# grid and the buttons when the rows are of different lengths. Left of the first column is Close
# (under the preview); below the grid is Drop.
func _link_focus() -> void:
	var columns := maxi(_grid.columns, 1)
	var rows := ceili(float(_item_cells.size()) / columns)
	var first_weapon: Control = _weapon_cells[0] if not _weapon_cells.is_empty() else null
	var first_item: Control = _item_cells[0] if not _item_cells.is_empty() else null
	for index in _weapon_cells.size():
		var below: Control = _drop
		if first_item != null:
			below = _item_cells[mini(index, mini(columns, _item_cells.size()) - 1)]
		var left: Control = _weapon_cells[index - 1] if index > 0 else _close
		var right: Control = _weapon_cells[index + 1] if index + 1 < _weapon_cells.size() else null
		_set_neighbours(_weapon_cells[index], null, below, left, right)
	for index in _item_cells.size():
		var row := index / columns
		var column := index % columns
		var above: Control = first_weapon
		if row > 0:
			above = _item_cells[index - columns]
		elif first_weapon != null:
			above = _weapon_cells[mini(column, _weapon_cells.size() - 1)]
		var below: Control = _drop
		if row + 1 < rows and index + columns < _item_cells.size():
			below = _item_cells[index + columns]
		var left: Control = _item_cells[index - 1] if column > 0 else _close
		var right: Control = null
		if column + 1 < columns and index + 1 < _item_cells.size():
			right = _item_cells[index + 1]
		_set_neighbours(_item_cells[index], above, below, left, right)
	var last_row_first: Control = first_item if first_item != null else first_weapon
	if first_item != null:
		last_row_first = _item_cells[(rows - 1) * columns]
	var start: Control = first_weapon if first_weapon != null else first_item
	_set_neighbours(_drop, last_row_first, null, _close, null)
	_set_neighbours(_close, null, null, null, start if start != null else _drop)
	initial_focus = get_path_to(start if start != null else _close)


# A side with no neighbour keeps the focus where it is (never a guess by geometry).
func _set_neighbours(
	cell: Control, up: Control, down: Control, left: Control, right: Control
) -> void:
	cell.focus_neighbor_top = cell.get_path_to(up if up != null else cell)
	cell.focus_neighbor_bottom = cell.get_path_to(down if down != null else cell)
	cell.focus_neighbor_left = cell.get_path_to(left if left != null else cell)
	cell.focus_neighbor_right = cell.get_path_to(right if right != null else cell)


func _show_detail(cell: InventoryCell) -> void:
	_shown_cell = cell
	var title := ""
	var text := ""
	if cell != null and cell.kind == InventoryCell.Kind.WEAPON and _loadout != null:
		var definition: WeaponDef = (
			_loadout.unarmed if cell.slot == WeaponLoadout.UNARMED else _loadout.slots[cell.slot]
		)
		title = definition.display_name
		text = "In your hands." if cell.slot == _chosen_weapon() else "Press to take it in hand."
		if definition.uses_ammo():
			var counts := _loadout.ammo_of(cell.slot)
			text = "%d in the magazine, %d more. %s" % [counts[0], counts[1], text]
	elif cell != null and cell.kind == InventoryCell.Kind.ITEM and _inventory != null:
		var item := _inventory.item_at(cell.slot)
		if item != null:
			title = item.display_name
			if _inventory.count_at(cell.slot) > 1:
				title = "%s  x%d" % [title, _inventory.count_at(cell.slot)]
			text = item.description
		elif _picked >= 0:
			title = "Empty slot"
			text = "Press to put it here."
	if _picked >= 0 and _inventory.item_at(_picked) != null and title.is_empty():
		title = _inventory.item_at(_picked).display_name
		text = "Picked up: press another slot to put it there."
	if title.is_empty():
		title = "Inventory"
		text = "Choose a weapon or an item."
	_detail_name.text = title
	_detail_text.text = text
	_update_drop()


func _update_drop() -> void:
	var slot := _drop_slot()
	_drop.disabled = slot < 0 or not _inventory.can_drop(slot)


func _link() -> void:
	if _inventory != null:
		_inventory.changed.connect(refresh)
	if _loadout != null:
		_loadout.weapon_changed.connect(_on_loadout_changed)
		_loadout.switch_started.connect(_on_loadout_changed)
		if _loadout.has_signal(&"slots_changed"):
			_loadout.connect(&"slots_changed", refresh)
	if _loadout != null and _loadout.weapon != null:
		_loadout.weapon.ammo_changed.connect(_on_ammo_changed)


func _unlink() -> void:
	if _inventory != null and _inventory.changed.is_connected(refresh):
		_inventory.changed.disconnect(refresh)
	if _loadout != null:
		for pair: Array in [
			[_loadout.weapon_changed, _on_loadout_changed],
			[_loadout.switch_started, _on_loadout_changed],
		]:
			if (pair[0] as Signal).is_connected(pair[1]):
				(pair[0] as Signal).disconnect(pair[1])
		if (
			_loadout.has_signal(&"slots_changed")
			and _loadout.is_connected(&"slots_changed", refresh)
		):
			_loadout.disconnect(&"slots_changed", refresh)
		if _loadout.weapon != null and _loadout.weapon.ammo_changed.is_connected(_on_ammo_changed):
			_loadout.weapon.ammo_changed.disconnect(_on_ammo_changed)


func _give_input_back() -> void:
	if _input_held and is_instance_valid(player):
		player.input_enabled = _input_was
	_input_held = false


func _on_loadout_changed(_definition: WeaponDef) -> void:
	refresh()


func _on_ammo_changed(_ammo: int, _reserve: Variant = null) -> void:
	refresh()


func _on_cell_pressed(cell: InventoryCell) -> void:
	if cell.kind == InventoryCell.Kind.WEAPON:
		choose_weapon(cell.slot)
	else:
		press_item(cell.slot)


func _on_cell_shown(on: bool, cell: InventoryCell) -> void:
	if on:
		_show_detail(cell)
	elif cell == _shown_cell:
		var focused := get_viewport().gui_get_focus_owner() as InventoryCell
		if focused != null and focused != cell:
			_show_detail(focused)


func _on_dragged_onto(from: InventoryCell, onto: InventoryCell) -> void:
	if _inventory != null:
		_inventory.move(from.slot, onto.slot)
	pick(-1)


func _on_drop() -> void:
	drop_selected()


func _on_close() -> void:
	if ScreenHost.current != null:
		ScreenHost.current.close()
	else:
		UIRouter.close()
