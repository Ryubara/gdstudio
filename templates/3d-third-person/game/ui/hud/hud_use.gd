@tool
class_name HudUse
extends HudWidget
## The sign of an item being used (a bandage): its picture, its name and a bar that fills over the
## use's time, shown above the hotbar while the player's `ItemUse` runs and gone when it ends.
## When the item works the bar turns `applied_color`; a use cut short flashes `cancelled_color`
## for `linger_time` before the sign goes. It reads the `ItemUse` and never writes.

@export_group("Look")
## The bar's colour once the item has worked.
@export var applied_color := Color(0.55, 0.9, 0.55)
## The sign's colour for a moment after a use was cut short.
@export var cancelled_color := Color(1.0, 0.55, 0.45)
## How long the sign stays after a use ends or is cut short, in seconds.
@export_range(0.0, 2.0, 0.05, "suffix:s") var linger_time := 0.35

@export_group("Nodes")
## The item's picture.
@export var icon: TextureRect
## The item's name.
@export var name_label: Label
## The use's progress.
@export var bar: ProgressBar

var _use: ItemUse
var _linger := 0.0
var _last_item: ItemDef
var _was_cut := false


func _ready() -> void:
	super()
	set_process(false)


func _on_bound(node: Node) -> void:
	_use = ItemUse.of(node)
	if _use == null:
		return
	_use.started.connect(_on_started)
	_use.finished.connect(_on_finished)
	_use.cancelled.connect(_on_cancelled)


func _let_go() -> void:
	if is_instance_valid(_use) and _use.started.is_connected(_on_started):
		_use.started.disconnect(_on_started)
		_use.finished.disconnect(_on_finished)
		_use.cancelled.disconnect(_on_cancelled)
	super()
	_use = null


## The use shown (null: none).
func item_use() -> ItemUse:
	return _use


func _has_data() -> bool:
	if _bound == null or not is_instance_valid(_use):
		return false
	return _use.is_using() or _linger > 0.0


func _refresh() -> void:
	var shown := _use.item() if _use.is_using() else _last_item
	if shown == null:
		return
	if icon != null:
		icon.texture = shown.icon
	if name_label != null:
		name_label.text = shown.display_name
	if bar != null:
		bar.value = _use.progress() if _use.is_using() else (0.0 if _was_cut else 1.0)
		var tint := Color.WHITE
		if _use.is_using():
			tint = applied_color if _use.has_applied() else Color.WHITE
		else:
			tint = cancelled_color if _was_cut else applied_color
		bar.self_modulate = tint
	self_modulate = cancelled_color if not _use.is_using() and _was_cut else Color.WHITE


func _process(delta: float) -> void:
	if not is_instance_valid(_use):
		set_process(false)
		return
	if not _use.is_using():
		_linger = maxf(_linger - delta, 0.0)
		if _linger <= 0.0:
			set_process(false)
	update()


func _on_started(_place: int, item: ItemDef, _seconds: float) -> void:
	_last_item = item
	_was_cut = false
	_linger = 0.0
	set_process(true)
	update()


func _on_finished(_place: int, _item: ItemDef) -> void:
	_on_ended(false)


func _on_cancelled(_place: int, _item: ItemDef, _reason: StringName) -> void:
	_on_ended(true)


func _on_ended(cut: bool) -> void:
	_was_cut = cut
	_linger = linger_time
	set_process(true)
	update()
