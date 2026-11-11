@tool
class_name ItemStack
extends Resource
## An item and how many of it: what an `Inventory` starts with (`start_items`), one entry each.

## The kind of item.
@export var item: ItemDef
## How many of it. More than the item's `max_stack` fills further slots.
@export_range(1, 9999, 1, "or_greater") var count := 1
