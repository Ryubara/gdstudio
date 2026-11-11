@tool
class_name AiNeedRow
extends Resource
## One row of `AiNeeds`: how badly the character must feel `need` before the order `order` gives
## way to a task that serves it.

## The need: a belief of the runner (`AiTaskRunner.beliefs`) holding how badly it is felt, 0 to 1
## (`&"ammo"` 1 is an empty gun).
@export var need := &""
## The order's task id it applies to; `*` is every order.
@export var order := &"*"
## How badly the need must be felt for the order to give way: 0 at the first sign of it, 1 only at
## its worst.
@export_range(0.0, 1.0, 0.01) var gives_way_at := 0.5
