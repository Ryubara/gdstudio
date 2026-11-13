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

@export_group("Use")
## What using it does (the bandage heals). Empty: it is carried, never used.
@export var use_effect: ItemEffect
## On: using it takes one out of the bag. Off: it stays (a torch switched on and off).
@export var consumed_on_use := true
## Seconds a use takes, from the press to the end of its clip: the hands are busy for that long
## and the use can be cut short (an `ItemUse` says how). Zero: the item works at the press.
@export_range(0.0, 10.0, 0.05, "or_greater", "suffix:s") var use_time := 0.0
## The share of `use_time` at which the item works: its effect lands and one leaves the bag on the
## same tick. A use cut short before it changes nothing.
@export_range(0.0, 1.0, 0.01) var use_apply_share := 0.75
## The clip a character plays over its upper body while it uses the item, stretched to
## `use_time` (a clip of its animation libraries: `ual2/Consume`). Empty: no clip.
@export var use_clip: StringName = &""
## The sound played as the use starts (an `AudioStreamRandomizer` for variants). Empty: none.
@export var use_sound: AudioStream


## True when using the item takes time (`use_time` above zero) rather than working at the press.
func takes_time() -> bool:
	return use_time > 0.0


## Whether the item does something when used (it has a `use_effect`).
func is_usable() -> bool:
	return use_effect != null


## The count shown on a slot: nothing for a single item, the number otherwise.
func count_text(count: int) -> String:
	return "" if max_stack <= 1 and count <= 1 else str(count)
