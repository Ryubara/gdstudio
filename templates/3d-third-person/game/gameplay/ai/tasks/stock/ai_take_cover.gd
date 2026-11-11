@tool
class_name AiTakeCover
extends AiStockTask
## Runs to a cover spot (an `AiMarker` of kind COVER) and fights from it: crouched for
## `hide_seconds`, then up for `peek_seconds` to shoot at the threat with the aim model of
## `AiAim`, and down again. Playing Safe, it only hides. It ends `hold_seconds` after the threat
## was last believed; with no free spot that covers from the threat within `search_radius` it fails
## `NO_PATH` (a row's fallback runs).
##
## Which spot is the second choice point that is scored (`AiChoice`): walking cost first, a spot
## facing the threat preferred, the spot already chosen keeping `commitment`. A spot is taken by
## one character at a time.

## How far it looks for a spot.
@export_range(1.0, 100.0, 0.5, "suffix:m") var search_radius := 15.0
## Seconds crouched between two peeks.
@export_range(0.1, 30.0, 0.1, "suffix:s") var hide_seconds := 1.5
## Seconds up at each peek.
@export_range(0.1, 30.0, 0.1, "suffix:s") var peek_seconds := 1.5
## Seconds with no threat believed before it leaves the spot.
@export_range(0.5, 60.0, 0.5, "suffix:s") var hold_seconds := 4.0
## The score of the spot already chosen.
@export_range(0.0, 5.0, 0.05) var commitment := 0.3
## Peeks to shoot; off it only hides (the answer to a dry gun).
@export var peek := true

## The spot, and whether it is there; peeks made.
var spot: AiMarker = null
var in_cover := false
var peeks := 0
var gun := AiAim.new()

var _phase := 0.0
var _peeking := false
var _calm := 0.0


func _init() -> void:
	id = &"cover"
	layer = Layer.RESPONSE
	channels = Channel.MOVE | Channel.ACTION | Channel.LOOK
	answers_threat = true
	hard_timeout = 0.0
	ends_on_condition = true


func start() -> void:
	gun = AiAim.new(hash(String(character.name)) + 7 if character != null else 7)
	in_cover = false
	_peeking = false
	_calm = 0.0
	spot = choose_spot()
	if spot != null:
		spot.taken_by = character
		go(spot.global_position, Speed.RUN)


func update(delta: float) -> Status:
	if spot == null:
		reason = Reason.NO_PATH
		return Status.FAILED
	var threat := subject()
	var belief := belief_of(threat)
	if belief != null and belief.believed:
		last_known = belief.last_position
		_calm = 0.0
	else:
		_calm += delta
		if _calm >= hold_seconds:
			_leave()
			return Status.SUCCEEDED
	if not in_cover:
		look_toward(last_known)
		match walk_state():
			Walk.ARRIVED:
				in_cover = true
				_phase = 0.0
			Walk.FAILED:
				if flat_distance(spot.global_position) > 1.5:
					_leave()
					reason = Reason.NO_PATH
					return Status.FAILED
				in_cover = true
		return Status.RUNNING
	return _fight(delta, belief)


func resume() -> Resume:
	if spot != null and not in_cover:
		go(spot.global_position, Speed.RUN)
	gun.reset()
	return Resume.RESUME


func cancel() -> void:
	super()
	_leave()


func detail() -> String:
	if spot == null:
		return ""
	if not in_cover:
		return "to " + String(spot.name)
	return "peek" if _peeking else "hide"


## The best free cover spot within `search_radius`: walking cost, a spot facing the threat
## preferred, the one chosen before keeping `commitment`; null when none.
func choose_spot() -> AiMarker:
	var at := (character as Node3D).global_position
	var map := (character as Node3D).get_world_3d().navigation_map
	var threat_at := last_known
	var belief := belief_of(subject())
	if belief != null:
		threat_at = belief.last_position
	elif goal != Vector3.ZERO:
		threat_at = goal
	var ids: Array = []
	var scores := PackedFloat32Array()
	var candidates: Array[AiMarker] = []
	for marker in AiMarker.of_kind(AiMarker.Kind.COVER):
		if not marker.is_free_for(character):
			continue
		if marker.global_position.distance_to(at) > search_radius:
			continue
		var cost := AiChoice.walk_cost(map, at, marker.global_position, body().budget)
		if cost == INF:
			continue
		var faces := 1.0 if marker.covers_from(threat_at) else 0.0
		ids.append(marker.get_instance_id())
		scores.append(faces - cost / search_radius)
		candidates.append(marker)
	var kept: Variant = spot.get_instance_id() if spot != null and is_instance_valid(spot) else null
	var index := AiChoice.best(ids, scores, kept, commitment)
	return candidates[index] if index >= 0 else null


func _fight(delta: float, belief: AiBelief) -> Status:
	_phase += delta
	controller.walk_direction = Vector3.ZERO
	if not _peeking and _phase >= hide_seconds and peek and not plays_safe():
		_peeking = true
		peeks += 1
		_phase = 0.0
	elif _peeking and _phase >= peek_seconds:
		_peeking = false
		_phase = 0.0
	var peek_now := _peeking and peek and not plays_safe()
	controller.crouch = not peek_now
	if not peek_now:
		controller.aim = false
		controller.fire = false
		look_toward(last_known)
		gun.reset()
		return Status.RUNNING
	var shot := gun.step(self, belief, delta, 6.0, 8.0, 1.0)
	if shot == AiAim.Shot.UNSEEN:
		look_toward(last_known)
	elif shot == AiAim.Shot.DRY:
		_leave()
		reason = Reason.NO_AMMO
		return Status.FAILED
	return Status.RUNNING


func _leave() -> void:
	if spot != null and is_instance_valid(spot) and spot.taken_by == character:
		spot.taken_by = null
	if controller != null:
		controller.crouch = false
