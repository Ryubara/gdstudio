class_name ItemCounter
extends HudWidget
## Shows what the player has collected ("coin 3   gem 1"), updated when the player says it took an
## item. It has nothing to show until the first item, so the HUD starts without it. It reads the
## player's `items` and listens to `item_collected`.

@export_group("Look")
## What goes between two kinds of item.
@export var separator := "   "

@export_group("Parts")
## The label that holds the text.
@export var label: Label


func _get_configuration_warnings() -> PackedStringArray:
	if label == null:
		return PackedStringArray(
			["Set `label` in the Parts group: the counter writes its text there."]
		)
	return PackedStringArray()


func _on_bound(node: Node) -> void:
	refresh_on(node, &"item_collected")


func _has_data() -> bool:
	return _bound != null and not _items().is_empty()


func _refresh() -> void:
	var parts: PackedStringArray = []
	var items := _items()
	for item in items:
		parts.append("%s %d" % [item, items[item]])
	if label != null:
		label.text = separator.join(parts)


func _items() -> Dictionary:
	var items: Variant = _bound.get(&"items") if _bound != null else null
	return items as Dictionary if items is Dictionary else {}
