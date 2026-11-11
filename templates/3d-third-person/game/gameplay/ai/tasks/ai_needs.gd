@tool
class_name AiNeeds
extends Resource
## The table of needs against orders: whether an order a character follows gives way to a task
## that serves a need (fetch ammo, heal), row by row, so a game adds a need by adding a row and no
## branch in a brain (the research for kit #882, section 3.6). A need nobody wrote a row for never
## beats an order. Example rows: an empty gun (`ammo` at 1) goes for ammo whatever the order;
## `hold` gives way to `ammo` only at 1; `roam` gives way at once (0).

## The rows; the first that matches the order and the need decides.
@export var rows: Array[AiNeedRow] = []


## True when the order with id `order_id` gives way to `need` felt at `urgency` (0 to 1).
func gives_way(order_id: StringName, need: StringName, urgency: float) -> bool:
	if urgency <= 0.0:
		return false
	for row in rows:
		if row == null or row.need != need:
			continue
		if row.order == order_id or row.order == &"*":
			return urgency >= row.gives_way_at
	return false
