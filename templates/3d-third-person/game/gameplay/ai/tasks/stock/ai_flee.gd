@tool
class_name AiFlee
extends AiStockTask
## Runs from its subject (where it is believed to be, or `goal`): of `directions` points
## `step_distance` away around it, the one farthest from the threat that the navigator can reach,
## again and again until it is `safe_distance` away; then it ends and the situation calms to Alert.
## With nowhere to run it fails `NO_PATH` (a row's fallback, a cower, runs).

## How far from the threat it is safe.
@export_range(1.0, 200.0, 1.0, "suffix:m") var safe_distance := 25.0
## How far each leg of the flight goes.
@export_range(1.0, 50.0, 0.5, "suffix:m") var step_distance := 10.0
## Directions tried for each leg.
@export_range(3, 16) var directions := 8
## How fast it runs.
@export var speed := Speed.SPRINT

var _legs := 0


func _init() -> void:
	id = &"flee"
	layer = Layer.RESPONSE
	channels = Channel.MOVE
	answers_threat = true
	ends_on_condition = true
	hard_timeout = 30.0


func start() -> void:
	_legs = 0
	last_known = _threat_at()
	if not _leg():
		_legs = -1


func update(_delta: float) -> Status:
	if _legs < 0:
		reason = Reason.NO_PATH
		return Status.FAILED
	last_known = _threat_at()
	if flat_distance(last_known) >= safe_distance:
		stop_walk()
		_calm()
		return Status.SUCCEEDED
	if walk_state() != Walk.GOING and not _leg():
		reason = Reason.NO_PATH
		return Status.FAILED
	return Status.RUNNING


func resume() -> Resume:
	return Resume.RESUME if _leg() else Resume.FAILED


func detail() -> String:
	return "leg %d" % _legs


func _threat_at() -> Vector3:
	var belief := belief_of(subject())
	return belief.last_position if belief != null else goal


# The next leg: the reachable point farthest from the threat.
func _leg() -> bool:
	var at := (character as Node3D).global_position
	var map := (character as Node3D).get_world_3d().navigation_map
	var away := at - last_known
	away.y = 0.0
	var base := atan2(away.x, away.z) if away.length_squared() > 0.01 else 0.0
	var best := Vector3.INF
	var best_score := -INF
	for index in directions:
		var angle := base + TAU * float(index) / float(directions)
		var point := at + Vector3(sin(angle), 0.0, cos(angle)) * step_distance
		var cost := AiChoice.walk_cost(map, at, point, body().budget if body() else null)
		if cost == INF or cost > step_distance * 2.5:
			continue
		var score := point.distance_to(last_known) - cost * 0.3
		if score > best_score:
			best_score = score
			best = point
	if best == Vector3.INF:
		return false
	_legs += 1
	return go(best, speed)


func _calm() -> void:
	var at := body()
	if at != null and at.situation.current == AiSituation.Situation.FLEEING:
		at.situation.request(AiSituation.Situation.ALERT)
