@tool
class_name ItemDef
extends Resource
## One kind of item as data: what it is called, its picture, how many fit in one slot and what is
## left in the world when it is dropped. An `Inventory` holds stacks of these; a pickup whose
## `item_id` is this `id` adds one to the inventory of whoever takes it (the inventory's
## `catalog` lists the kinds it knows). A new item is a new `.tres` of this class.

@export_group("Item")
## The name the game knows it by: a pickup's `item_id`, a save file's entry. Unique in a catalog.
@export var id: StringName = &""
## The name an inventory screen shows.
@export var display_name := "Item"
## One or two sentences the screen shows under the grid.
@export_multiline var description := ""
## The picture a slot shows. Empty: the slot shows the name on `tint`.
@export var icon: Texture2D
## The colour of the slot's plate when there is no icon, and of a dropped pickup that takes one.
@export var tint := Color(0.8, 0.8, 0.8)

@export_group("Stack")
## How many fit in one slot (1: each one takes a slot of its own).
@export_range(1, 9999, 1, "or_greater") var max_stack := 1

@export_group("Drop")
## Whether the player can drop it (a key to the story, the money in the pocket: off).
@export var droppable := true
## What is left in the world when it is dropped, placed in front of the inventory's owner. A scene
## whose root has `item_id`, `amount` and `tint` gets them (the template's `Pickup` does, so a
## dropped item can be taken again). Empty: a dropped item is gone.
@export var drop_scene: PackedScene


## The count shown on a slot: nothing for a single item, the number otherwise.
func count_text(count: int) -> String:
	return "" if max_stack <= 1 and count <= 1 else str(count)
