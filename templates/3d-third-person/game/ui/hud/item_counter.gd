class_name ItemCounter
extends Label
## Shows what the player has collected ("coin 3   gem 1"), updated when the player says it took
## an item. It finds the player by its group, so it needs no wiring.


func _ready() -> void:
	text = ""
	var player := get_tree().get_first_node_in_group(Player.GROUP) as Player
	if player != null:
		player.item_collected.connect(_on_item_collected.bind(player))


func _on_item_collected(_item: StringName, _amount: int, _total: int, player: Player) -> void:
	var parts: PackedStringArray = []
	for item in player.items:
		parts.append("%s %d" % [item, player.items[item]])
	text = "   ".join(parts)
