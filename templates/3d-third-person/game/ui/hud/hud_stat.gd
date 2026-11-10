@tool
class_name HudStat
extends HudWidget
## A number with an optional bar and a word: health, ammo, anything the player (or its weapon) has
## as a property. It reads `value_property` (and `max_property` for the bar and the "of" figure) of
## its source and shows nothing while the source has no such number, so the player can get health
## or the weapon ammo later with no change here. It refreshes on the signals listed in
## `refresh_signals`, looked up on the source first and on the player next (one the node does not
## have is passed over).
##
## `hud_health.tscn` and `hud_ammo.tscn` are this script with their names; a game adds a stat (a
## stamina bar, a shield) by instancing `hud_stat.tscn` and changing the exports.

enum Source {
	PLAYER,  ## The properties are the player's.
	WEAPON,  ## The properties are those of the player's `weapon`.
}

@export_group("Data")
## Whose properties are read.
@export var source := Source.PLAYER:
	set(value):
		source = value
		if is_node_ready() and not Engine.is_editor_hint():
			rebind()
## The property with the number to show. A source without it, or with a non-number, hides the
## part.
@export var value_property: StringName = &"health":
	set(value):
		value_property = value
		update()
## The property with the largest the number can be. Empty, or missing: no bar and no "of".
@export var max_property: StringName = &"max_health":
	set(value):
		max_property = value
		update()
## A third number shown in the text as `{extra}` (the ammo's reserve). Empty, or missing: none.
@export var extra_property: StringName = &"":
	set(value):
		extra_property = value
		update()
## The signals that make the part read again: the number changed, the weapon was swapped, the
## player died or got up.
@export
var refresh_signals: Array[StringName] = [&"health_changed", &"took_hit", &"died", &"revived"]

@export_group("Look")
## The word above the number.
@export var title := "Health":
	set(value):
		title = value
		_show_title()
## Shows the word. Off: the number alone.
@export var show_title := true:
	set(value):
		show_title = value
		_show_title()
## Draws the bar when there is a largest number.
@export var show_bar := true:
	set(value):
		show_bar = value
		update()
## The number as text: `{value}` is replaced.
@export var value_format := "{value}"
## The number as text when there is a largest number: `{value}`, `{max}` and `{extra}` are
## replaced.
@export var max_format := "{value} / {max}"
## Below this share of the largest number the bar takes the low colour.
@export_range(0.0, 1.0, 0.01) var low_share := 0.25
## The bar's tint while it is low.
@export var low_color := Color(1.0, 0.4, 0.35, 1.0)

@export_group("Parts")
## The word's label.
@export var title_label: Label
## The number's label.
@export var value_label: Label
## The bar.
@export var bar: ProgressBar

var _connected_source: Object


func _ready() -> void:
	_show_title()
	super()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	for part_name: String in ["title_label", "value_label", "bar"]:
		if get(part_name) == null:
			warnings.append("Set `%s` in the Parts group." % part_name)
	return warnings


# A weapon that was swapped is a new source: listen to it before reading.
func update() -> void:
	if _bound != null and _source() != _connected_source:
		rebind()
		return
	super()


func _on_bound(node: Node) -> void:
	_connected_source = _source()
	for signal_name in refresh_signals:
		refresh_on(_connected_source, signal_name)
		refresh_on(node, signal_name)


func _has_data() -> bool:
	return _bound != null and _number(value_property) != null


func _refresh() -> void:
	var value: Variant = _number(value_property)
	var largest: Variant = _number(max_property)
	var values := {"value": roundi(value)}
	if largest != null:
		values["max"] = roundi(largest)
	var extra: Variant = _number(extra_property)
	values["extra"] = roundi(extra) if extra != null else ""
	if value_label != null:
		value_label.text = (max_format if largest != null else value_format).format(values)
	if bar != null:
		bar.visible = show_bar and largest != null and largest > 0
		if bar.visible:
			bar.max_value = largest
			bar.value = value
			bar.self_modulate = low_color if value <= largest * low_share else Color.WHITE


func _source() -> Object:
	if _bound == null:
		return null
	if source == Source.WEAPON:
		return _bound.get(&"weapon") as Object
	return _bound


# A number the source has under `property`, or null.
func _number(property: StringName) -> Variant:
	var holder := _source()
	if holder == null or property == &"":
		return null
	var value: Variant = holder.get(property)
	return value if typeof(value) in [TYPE_INT, TYPE_FLOAT] else null


func _show_title() -> void:
	if title_label != null:
		title_label.text = title
		title_label.visible = show_title
