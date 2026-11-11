@tool
class_name AiUseObject
extends AiStockTask
## Walks up to its subject (a door, a switch: an `Interactable`, or a node holding one) and uses
## it with the use button, as a player does: the body's own `Interactor` finds the thing in front.
## It succeeds when the body says it used something (`Character.interacted`), and fails `NO_PATH`
## when there is nothing to use or no way there, or `BLOCKED` after `tries` presses in vain.

## How far inside the body's `interact_reach` it presses from, with `reach` 0.
const REACH_MARGIN := 0.2

## How near the thing's reach point it walks before it presses; 0 takes the body's own
## `interact_reach` less `REACH_MARGIN` (a door's panel stops the body short of its middle).
@export_range(0.0, 3.0, 0.05, "suffix:m") var reach := 0.0
## Seconds after a press before it presses again.
@export_range(0.05, 5.0, 0.05, "suffix:s") var press_gap := 0.5
## Presses before it gives up.
@export_range(1, 10) var tries := 3

## Presses made, and whether the body used something.
var presses := 0
var used := false

var _usable: Interactable = null
var _pressed_at := -INF
var _walking := false


func _init() -> void:
	id = &"use"
	layer = Layer.ORDER
	channels = Channel.MOVE | Channel.ACTION
	# An order a script gives: authority 0 would be refused by any character that obeys little.
	authority = AUTHORITY_SCRIPT


func start() -> void:
	presses = 0
	used = false
	_pressed_at = -INF
	_usable = _find()
	var at := body()
	if at != null and not at.interacted.is_connected(_on_interacted):
		at.interacted.connect(_on_interacted)
	_walking = _usable != null and go(_usable.reach_point(), Speed.WALK)


func update(_delta: float) -> Status:
	controller.interact = false
	if used:
		_let_go()
		return Status.SUCCEEDED
	if _usable == null:
		reason = Reason.NO_PATH
		return _give_up()
	var point := _usable.reach_point()
	last_known = point
	var away := flat_distance(point)
	if away > _reach():
		_approach(point, away)
		return Status.RUNNING
	controller.walk_direction = Vector3.ZERO
	if elapsed - _pressed_at < press_gap:
		return Status.RUNNING
	if presses >= tries:
		reason = Reason.BLOCKED
		return _give_up()
	controller.interact = true
	presses += 1
	_pressed_at = elapsed
	return Status.RUNNING


# The navigator takes it most of the way; the last steps go straight at the thing, so the body
# faces it when it presses.
func _approach(point: Vector3, away: float) -> void:
	if _walking and walk_state() == Walk.GOING and away > _reach() * 2.0:
		return
	stop_walk()
	_walking = false
	var toward := point - (character as Node3D).global_position
	toward.y = 0.0
	controller.walk_direction = toward.normalized()
	controller.walk_strength = speed_share(Speed.WALK)


func cancel() -> void:
	super()
	_let_go()


func has_end_condition() -> bool:
	return true


func _reach() -> float:
	if reach > 0.0:
		return reach
	var at := body()
	return at.tuning.interact_reach - REACH_MARGIN if at != null else 1.0


func _find() -> Interactable:
	var thing := subject()
	if thing == null:
		return null
	if thing is Interactable:
		return thing as Interactable
	for child in thing.find_children("*", "Interactable", true, false):
		return child as Interactable
	return null


func _give_up() -> Status:
	_let_go()
	return Status.FAILED


func _let_go() -> void:
	var at := body()
	if at != null and at.interacted.is_connected(_on_interacted):
		at.interacted.disconnect(_on_interacted)


func _on_interacted(_what: Node3D) -> void:
	used = true
