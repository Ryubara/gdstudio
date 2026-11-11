@tool
class_name HealEffect
extends ItemEffect
## Gives health back to whoever uses the item: its `Health` (found with `Health.of(user)`) gets
## `amount`. A user that is dead, has no `Health` or (with `only_when_hurt`) is at full health is
## refused, so a bandage is not wasted.

## How much health comes back.
@export_range(1.0, 1000.0, 1.0, "or_greater") var amount := 25.0
## On: refused at full health, so the item stays in the bag. Off: it is used up all the same.
@export var only_when_hurt := true


func can_apply(user: Node) -> bool:
	var health := Health.of(user)
	if health == null or health.is_dead():
		return false
	return not only_when_hurt or health.value < health.max_value


func apply(user: Node) -> bool:
	if not can_apply(user):
		return false
	Health.of(user).heal(amount)
	return true
