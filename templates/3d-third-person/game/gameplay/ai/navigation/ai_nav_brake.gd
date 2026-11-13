class_name AiNavBrake
extends RefCounted
## Where an `AiNavigator` lets go of the stick so that its body comes to rest on the goal
## (gdstudio #1415). A body on its feet slows over its stop clip (`CharacterTuning`'s stop
## decelerations: 1.96 m from a jog, 4.82 m from a sprint), so a walk that let go at
## `arrive_distance` ran on past the point by the rest of the stop. The navigator lets go once what
## is left of the path (to the goal, to the band of a follow, or to a link it waits at) is the
## ground the body's stop covers (`CharacterTuning.stop_distance`), and keeps letting go until the
## body is at rest or the goal moves on. Nothing here is sent: the server's AI decides it, and the
## body's commands carry it.

## Below this ground speed (m/s) a body let go to stop is at rest.
const DONE := 0.3
## Metres more than its stop leaves before a body let go to stop walks again.
const SLACK := 0.5
## Metres more than the stop's reach within which the navigator steers at every step.
const EVERY_STEP_MARGIN := 0.25

## True once the body was let go to stop, until it is at rest or the goal moves on: asked again
## each step, a stop that keeps pace with what is left would flicker on and off.
var latched := false


## True when `navigator`'s body at `at` is to be let go this step: its stop ends on what it walks
## to. Never on a link, nor before one it crosses at speed, crouched or in the air.
func wants(navigator: AiNavigator, at: Vector3) -> bool:
	var body := navigator.character
	var path := navigator.path
	var mode := navigator.mode
	if (
		(mode != AiNavigator.Mode.GO_TO and mode != AiNavigator.Mode.FOLLOW)
		or navigator._on_link >= 0
		or (navigator.auto_traverse_links and path.link_at(path.index) != 0)
		or body.crouching
		or not body.is_on_floor()
	):
		latched = false
		return false
	var room := path.left(at)
	if mode == AiNavigator.Mode.FOLLOW:
		room -= navigator.follow_band
	var reach := stop_distance(body)
	if not navigator.auto_traverse_links:
		room = minf(room, _room_to_link(path, at, reach + SLACK))
	if room > reach + SLACK:
		latched = false  # The goal moved on, or a link let it by.
	elif latched and body.ground_speed() < DONE and room > navigator.arrive_distance:
		latched = false  # It came to rest short: it walks the rest.
	elif room <= reach:
		latched = true
	return latched


## The path's length from `at` (`left` of it to the end) to where `navigator` steers at every
## step: within `least` of the path's end, or of a link it waits at, or as far from either as
## its body's stop reaches from `speed` (or its own speed, when faster) and a little more, so that
## the step its stop begins on is never one a steer holds over. 0 or less: it steers at every
## step now.
func room_before(
	navigator: AiNavigator, at: Vector3, left: float, speed: float, least: float
) -> float:
	var path := navigator.path
	var within := maxf(least, stop_distance(navigator.character, speed) + EVERY_STEP_MARGIN)
	var room := left
	if not navigator.auto_traverse_links:
		room = minf(room, _room_to_link(path, at, within + room))
	return room - within


## The ground `body`'s stop covers from its ground speed, or from `speed` when that is faster.
static func stop_distance(body: Character, speed := 0.0) -> float:
	if body == null or body.tuning == null:
		return 0.0
	return body.tuning.stop_distance(maxf(body.ground_speed(), speed))


# The path's length from `at` to the first link ahead; INF with none within `reach`.
static func _room_to_link(path: AiNavPath, at: Vector3, reach: float) -> float:
	if not path.has_points() or path.index >= path.points.size():
		return INF
	var room := AiNavPath.flat(path.points[path.index] - at).length()
	for index in range(path.index, path.points.size() - 1):
		if room > reach:
			break
		if path.link_at(index) != 0:
			return room
		room += AiNavPath.flat(path.points[index + 1] - path.points[index]).length()
	return INF
