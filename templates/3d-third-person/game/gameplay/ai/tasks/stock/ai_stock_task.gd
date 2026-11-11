@tool
class_name AiStockTask
extends AiTask
## The base of the stock tasks (`gameplay/ai/tasks/stock/`): the helpers they share to reach the
## character's parts (its brain, navigator, beliefs and weapon) and the two flags the brain
## reads. A stock task reads beliefs, never the world: where a thing is comes from
## `belief_of(subject())`, and only the senses decide what is seen.
##
## A game's own task extends `AiTask` or this class; nothing in the brain names a stock task.
##
## Docs: the kit's `docs/engines/godot/third-person/ai-behaviour.md#stock-tasks`.

## How fast a movement task asks the navigator to go.
enum Speed { WALK, RUN, SPRINT }
## Where a walk stands (`walk_state()`).
enum Walk { GOING, ARRIVED, FAILED }

## The height above the feet of a body's chest, where an aim and a look point.
const CHEST := 1.2
## How far over the body's `walk_below_push` a walk's push goes.
const PUSH_MARGIN := 0.02

@export_group("Stock")
## It answers a threat (a fight, cover, a flight): the brain's reminder leaves it alone while a
## hostile is in view.
@export var answers_threat := false
## It roams (a patrol, a wander): it does not run while the character plays Safe.
@export var roams := false

## The last place it knew its subject at (the brain's next answer is about this place when the
## task fails).
var last_known := Vector3.ZERO
## It ended because a hostile came into view (`found_threat()`).
var found := false


## The character it runs on, as an `AiCharacter` (null in a bare test).
func body() -> AiCharacter:
	return character as AiCharacter


## The character's brain, or null.
func brain() -> AiBrain:
	return AiBrain.of(character)


## The character's navigator, or null.
func nav() -> AiNavigator:
	var at := body()
	return at.navigator as AiNavigator if at != null else null


## The character's beliefs, or null.
func beliefs() -> AiBeliefs:
	var at := body()
	var senses := at.senses as AiSenses if at != null else null
	return senses.beliefs if senses != null else null


## What it is about: its target, or (a step of a composite with none) the brain's focus.
func subject() -> Node3D:
	if is_instance_valid(target):
		return target as Node3D
	var mind := brain()
	return mind.focus if mind != null and is_instance_valid(mind.focus) else null


## The belief about `node`, or null.
func belief_of(node: Node3D) -> AiBelief:
	var known := beliefs()
	return known.of(node) if known != null and node != null else null


## The flat distance from the character to `point`.
func flat_distance(point: Vector3) -> float:
	var at := (character as Node3D).global_position
	return Vector2(point.x - at.x, point.z - at.z).length()


## The navigator's speed share for `speed` (a run is 1; over 1 sprints).
func speed_share(speed: Speed) -> float:
	var profile := run_profile()
	var at := body()
	if speed == Speed.SPRINT:
		return 1.5
	if profile == null or at == null or at.tuning == null or at.tuning.run_speed <= 0.0:
		return 1.0 if speed == Speed.RUN else 0.4
	var wanted := profile.run_speed if speed == Speed.RUN else profile.walk_speed
	# The body walks at `least_walk_share` of its walk speed for any push under `walk_below_push`
	# and runs at `run_speed` times the push above it: a walk asks for a little over that line (the
	# command packs the push into a byte, which may round it under the line).
	var tuning := at.tuning
	var least := tuning.walk_below_push + PUSH_MARGIN
	return clampf(maxf(wanted / tuning.run_speed, least), 0.05, 1.0)


## Starts a walk to `point` at `speed`; false when the navigator refused it at once.
func go(point: Vector3, speed: Speed) -> bool:
	var walker := nav()
	if walker == null:
		return false
	return walker.go_to(point, speed_share(speed))


## Where the walk the task started stands: going, arrived, or failed.
func walk_state() -> Walk:
	var walker := nav()
	if walker == null:
		return Walk.FAILED
	if walker.is_arrived():
		return Walk.ARRIVED
	return Walk.GOING if walker.is_active() else Walk.FAILED


## Stops the walk (the runner lets go of the channels, but a navigator with a goal would walk on).
func stop_walk() -> void:
	var walker := nav()
	if walker != null and walker.is_active():
		walker.stop()


## Points the look channel at `point` (the chest height of a body standing there).
func look_toward(point: Vector3) -> void:
	if controller == null:
		return
	var eye := (character as Node3D).global_position + Vector3.UP * 1.55
	var toward := point + Vector3.UP * CHEST - eye
	if toward.length_squared() > 0.0001:
		controller.look_direction = toward.normalized()


## The brain's event for a failure of this task (`AiBehaviourSet`), or empty for none. The base
## answers a dry gun; a task that loses its subject names its own.
func event_for(why: Reason) -> StringName:
	return AiBehaviourSet.NO_AMMO if why == Reason.NO_AMMO else &""


## True when a hostile is in view: the task ends and sets `found`, and the brain routes the
## noticed event when it has ended (a search or a chase ends on it; routing from inside a step
## would replace the task under the runner's feet).
func found_threat() -> bool:
	var mind := brain()
	if mind == null or mind.choose_target() == null:
		return false
	found = true
	return true


## True while the character plays Safe.
func plays_safe() -> bool:
	var mind := brain()
	return mind != null and mind.play.current == AiPlayState.State.SAFE


func can_run() -> bool:
	return not (roams and plays_safe())


func suspend() -> void:
	stop_walk()


func cancel() -> void:
	stop_walk()
