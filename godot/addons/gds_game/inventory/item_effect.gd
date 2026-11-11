@tool
class_name ItemEffect
extends Resource
## What using an item does, as data its `ItemDef` holds (`use_effect`): a bandage heals, a key
## opens, a flare lights. A subclass overrides `can_apply()` and `apply()`; a `Hotbar` (or any
## screen that uses an item) asks the first, calls the second and takes the item out of the bag
## when it worked and the item is `consumed_on_use`.
##
## The effect acts on the `user` it is handed (the character whose bag holds the item) and finds
## what it needs there by type (`Health.of(user)`), never by a method name.


## Whether using the item on `user` would do anything now (a bandage at full health would not).
func can_apply(_user: Node) -> bool:
	return false


## Does what the item does to `user`. True when it did something (the item is then used up).
func apply(_user: Node) -> bool:
	return false
