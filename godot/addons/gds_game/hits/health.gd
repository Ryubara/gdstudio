@tool
class_name Health
extends Node
## How much harm something can take, as a node it carries: a character, a target, a crate. A shot
## (or a blow, a fall, a trap) gives it a `HitRecord` with `apply(hit)`; it takes the damage, says
## so through its signals and says `died` once when it reaches zero. What dying means (a ragdoll,
## a board tipping over, a crate breaking) is the carrier's: it listens to `died`.
##
## A shot finds the component with `Health.of(body)` (a child of what it hit), never by a method
## name, so a body with no `Health` takes no harm, and its carrier says so in a configuration
## warning.
##
## Networking: the value sent is one integer (`wire_value()`, set on a peer with
## `set_wire_value()`); a flinch is never sent, each peer makes it from the hit it is given.

## A hit was applied (`apply()`), whether it took anything or not: switched off, invulnerable or
## already dead. Said last, after `damaged`, `flinched` and `died`.
signal hit_taken(hit: HitRecord)
## The value went down by `amount` (more than zero) from `hit`.
signal damaged(amount: float, hit: HitRecord)
## The value or the maximum changed.
signal changed(value: float, max_value: float)
## A hit that did not kill was at least `flinch_threshold`.
signal flinched(hit: HitRecord)
## The value reached zero. Said once a life; `hit` is what killed (null for `kill()` or a value
## set to zero).
signal died(hit: HitRecord)
## `reset()` brought it back from zero.
signal revived

## On: hits take from the value. Off: a hit is still said (`hit_taken`, `flinched`) but takes
## nothing.
@export var enabled := true
## The value it starts and comes back with (`reset()`). Lowering it below the value lowers the
## value.
@export_range(1.0, 100000.0, 1.0, "or_greater") var max_value := 100.0:
	set(new_max):
		max_value = maxf(new_max, 1.0)
		if _value > max_value:
			_set_value(max_value)
		elif is_node_ready():
			changed.emit(_value, max_value)
## On: hits take nothing (a cutscene, a spawn shield); they are still said.
@export var invulnerable := false

@export_group("Regeneration")
## How much comes back each second while alive and hurt. Zero: none, and the node does no work
## each frame.
@export_range(0.0, 1000.0, 0.5, "or_greater", "suffix:/s") var regeneration_per_second := 0.0:
	set(rate):
		regeneration_per_second = maxf(rate, 0.0)
		_update_regeneration()
## Seconds after the last damage before regeneration starts. Zero: at once.
@export_range(0.0, 60.0, 0.1, "or_greater", "suffix:s") var regeneration_delay := 0.0

@export_group("Flinch")
## A hit that does not kill and is at least this much says `flinched` (an AI stops to react, a
## character plays its flinch). Zero: every hit that does not kill.
@export_range(0.0, 1000.0, 0.5, "or_greater") var flinch_threshold := 0.0

## What is left, 0 to `max_value`. Setting it says `changed`, `died` when it reaches zero and
## `revived` when it leaves zero.
var value: float:
	get:
		return _value
	set(new_value):
		_set_value(new_value)

var _value := 100.0
var _dead := false
var _since_damage := 0.0


func _ready() -> void:
	_value = max_value
	_update_regeneration()


func _physics_process(delta: float) -> void:
	_since_damage += delta
	if _since_damage < regeneration_delay:
		return
	_set_value(_value + regeneration_per_second * delta)


## The `Health` of `node`: `node` itself, or its first child that is one. Null when it has none.
static func of(node: Object) -> Health:
	if node is Health:
		return node
	var parent := node as Node
	if parent == null:
		return null
	for child in parent.get_children():
		if child is Health:
			return child
	return null


## Takes `hit`: its damage comes off the value (when on, not invulnerable and alive), and the
## signals say what happened. Returns the damage taken (0 when nothing was taken). `hit.killed`
## is set when this hit reached zero.
func apply(hit: HitRecord) -> float:
	if hit == null:
		return 0.0
	var taken := 0.0
	if not _dead:
		if enabled and not invulnerable and hit.damage > 0.0:
			taken = minf(hit.damage, _value)
			_since_damage = 0.0
			_value -= taken
			changed.emit(_value, max_value)
			damaged.emit(taken, hit)
			if _value <= 0.0:
				_value = 0.0
				hit.killed = true
				_die(hit)
			else:
				_update_regeneration()
		if not _dead and hit.damage >= flinch_threshold:
			flinched.emit(hit)
	hit_taken.emit(hit)
	return taken


## Gives back `amount` (alive only). Returns how much came back.
func heal(amount: float) -> float:
	if _dead or amount <= 0.0:
		return 0.0
	var before := _value
	_set_value(_value + amount)
	return _value - before


## Takes it to zero at once (`died` once, with `hit`).
func kill(hit: HitRecord = null) -> void:
	if _dead:
		return
	_value = 0.0
	changed.emit(_value, max_value)
	if hit != null:
		hit.killed = true
	_die(hit)


## Back to `max_value`; `revived` when it was at zero.
func reset() -> void:
	_since_damage = 0.0
	_set_value(max_value)


## True once it reached zero, until `reset()`.
func is_dead() -> bool:
	return _dead


## The share left, 0 to 1.
func fraction() -> float:
	return _value / max_value


## The value as a network sends it: one integer, rounded up, so a body alive here is alive there.
func wire_value() -> int:
	return ceili(_value)


## Takes the value a network sent (`wire_value()` on the other peer): zero says `died` with no
## hit, above zero after zero says `revived`.
func set_wire_value(sent: int) -> void:
	_set_value(float(sent))


func _set_value(new_value: float) -> void:
	var was := _value
	_value = clampf(new_value, 0.0, max_value)
	if _value != was:
		changed.emit(_value, max_value)
	if _value <= 0.0 and not _dead:
		_die(null)
		return
	if _value > 0.0 and _dead:
		_dead = false
		revived.emit()
	_update_regeneration()


func _die(hit: HitRecord) -> void:
	_dead = true
	_update_regeneration()
	died.emit(hit)


# Regeneration is the only per-frame work, and only while it can do something.
func _update_regeneration() -> void:
	if not is_inside_tree() or Engine.is_editor_hint():
		set_physics_process(false)
		return
	set_physics_process(regeneration_per_second > 0.0 and not _dead and _value < max_value)
