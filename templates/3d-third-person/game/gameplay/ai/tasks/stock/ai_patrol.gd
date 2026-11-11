@tool
class_name AiPatrol
extends AiStockTask
## Walks the `AiMarker` patrol stops of its route (the brain's `patrol_route`, or `route` when
## set), waiting at each its `wait_seconds`, for as long as it runs. The next stop is the third
## choice point that is scored (`AiChoice`): the one longest unvisited, less its walking cost, the
## stop already chosen keeping `commitment`. With no stop it ends, and the DEFAULT layer runs. It
## roams: it does not run while the character plays Safe. Interrupted, it walks on to the stop it
## was going to.

## The route it walks; empty: the brain's `patrol_route`.
@export var route := &""
## How fast it walks.
@export var speed := Speed.WALK
## The score the next stop keeps once chosen.
@export_range(0.0, 5.0, 0.05) var commitment := 0.3
## Metres of walk worth one second of not having visited a stop.
@export_range(0.1, 50.0, 0.1, "suffix:m") var metres_per_second := 4.0

## The stop it goes to, and the visits (marker instance id to the run time it was last reached).
var next: AiMarker = null
var visited: Dictionary[int, float] = {}

var _waiting := -1.0


func _init() -> void:
	id = &"patrol"
	layer = Layer.ROUTINE
	channels = Channel.MOVE
	hard_timeout = 0.0
	roams = true


func start() -> void:
	_waiting = -1.0
	next = null
	_pick()


func update(delta: float) -> Status:
	if next == null or not is_instance_valid(next):
		return Status.SUCCEEDED
	if _waiting >= 0.0:
		_waiting -= delta
		if _waiting < 0.0:
			_pick()
		return Status.RUNNING
	match walk_state():
		Walk.ARRIVED:
			visited[next.get_instance_id()] = run_time()
			_waiting = next.wait_seconds
		Walk.FAILED:
			# A stop it cannot reach counts as visited, so the next pick goes elsewhere.
			visited[next.get_instance_id()] = run_time()
			_pick()
	return Status.RUNNING


func resume() -> Resume:
	if next != null and is_instance_valid(next) and _waiting < 0.0:
		go(next.global_position, speed)
	return Resume.RESUME


func detail() -> String:
	return String(next.name) if next != null and is_instance_valid(next) else ""


## The stops of its route.
func stops() -> Array[AiMarker]:
	var name_of := route
	if name_of == &"" and brain() != null:
		name_of = brain().patrol_route
	return AiMarker.of_kind(AiMarker.Kind.PATROL, name_of)


# The next stop: longest unvisited less walking cost, not the one it stands at.
func _pick() -> void:
	var markers := stops()
	var at := (character as Node3D).global_position if character != null else Vector3.ZERO
	var map := (character as Node3D).get_world_3d().navigation_map if character != null else RID()
	var budget := body().budget if body() != null else null
	var ids: Array = []
	var scores := PackedFloat32Array()
	var current := next.get_instance_id() if next != null and is_instance_valid(next) else 0
	for marker in markers:
		var key := marker.get_instance_id()
		if key == current and markers.size() > 1:
			continue
		var since := run_time() - float(visited.get(key, -60.0))
		var cost := AiChoice.walk_cost(map, at, marker.global_position, budget)
		ids.append(key)
		scores.append(minf(since, 60.0) - cost / metres_per_second)
	var index := AiChoice.best(ids, scores, current if current != 0 else null, commitment)
	if index < 0:
		next = null
		return
	for marker in markers:
		if marker.get_instance_id() == ids[index]:
			next = marker
	_waiting = -1.0
	go(next.global_position, speed)
