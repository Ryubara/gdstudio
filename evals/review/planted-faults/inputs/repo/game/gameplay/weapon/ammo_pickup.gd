class_name AmmoPickup
extends Area3D
## A box of rounds on the ground. A body that can carry ammo takes it and the box goes.

## Rounds in the box.
const ROUNDS := 30


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body.has_method("add_ammo"):
		return
	body.add_ammo(ROUNDS)
	queue_free()
