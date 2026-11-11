@tool
class_name AiMarker
extends Marker3D
## A place in the level that means something to AI characters: a patrol stop, a cover spot, a
## lookout, a spawn point or a scenario point. Placed in the scene and tuned in the inspector; the
## tasks find them by kind (and a patrol by `route`) through a list the markers keep themselves,
## never through the tree's groups. A cover marker's -Z (its blue arrow) points toward the side it
## covers from.

enum Kind { PATROL, COVER, LOOKOUT, SPAWN, SCENARIO }

const KIND_NAMES: Array[String] = ["Patrol", "Cover", "Lookout", "Spawn", "Scenario"]

static var _all: Array[AiMarker] = []

## What the place is for.
@export var kind := Kind.PATROL
## The patrol route it belongs to (a `Patrol` task walks the markers of its route); empty: any.
@export var route := &""
## Seconds a patrol waits here before it goes on.
@export_range(0.0, 60.0, 0.1, "suffix:s") var wait_seconds := 2.0
## Off: no task picks it.
@export var enabled := true

## The character using it now (a cover spot is taken by one at a time), or null.
var taken_by: Node = null


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		_all.append(self)


func _exit_tree() -> void:
	_all.erase(self)


## The enabled markers of `kind` (and of `route` when given) in the running game.
static func of_kind(wanted: Kind, on_route := &"") -> Array[AiMarker]:
	var found: Array[AiMarker] = []
	for marker in _all:
		if marker.enabled and marker.kind == wanted:
			if on_route == &"" or marker.route == on_route:
				found.append(marker)
	return found


## True when a cover marker here hides something at `from` from a threat at `threat`: the threat
## is on the side the marker faces (within 75° of its -Z).
func covers_from(threat: Vector3) -> bool:
	var toward := threat - global_position
	toward.y = 0.0
	if toward.length_squared() < 0.01:
		return false
	var facing := -global_basis.z
	facing.y = 0.0
	return facing.normalized().dot(toward.normalized()) > cos(deg_to_rad(75.0))


## True when `who` may take it (free, or already its own).
func is_free_for(who: Node) -> bool:
	return taken_by == null or taken_by == who or not is_instance_valid(taken_by)
