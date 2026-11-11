class_name ServerCombat
extends RefCounted
## The server's half of shots, hits and deaths (gdstudio #906): the server is the one owner of
## every hit and every health. It judges each command's shot before the body steps it, turns
## what the bodies' real weapons did into small events and gets the dead up again. `NetServer`
## owns one and hands it each body (`watch`), each command (`judge`) and each step (`step`).
##
## - A shot block is refused (a REJECTED event to its sender, the shot and the fire presses taken
##   off the command, nothing fired) when its numbers are not finite, its origin is farther than
##   `origin_slack` from the body's eye, or it presses fire while the weapon still cools down.
## - A shot that leaves is a SHOT event (slot, seq, weapon, where it left and the way it went) to
##   every other player; what it meets is a HIT (point, normal, kind, id, the health it left) to
##   everyone. The bodies' weapons are the real ones (`Weapon.authoritative`) with no flash, sound
##   or mark (`Weapon.effects` off): a server draws nothing.
## - A body whose health reaches zero is a DIED event (slot, the velocity of its last step, the
##   cause) to everyone; each peer starts its own ragdoll from it, and no bone is ever sent. After
##   `revive_seconds` the server gets it up where it died (or at its spawn point,
##   `revive_at_spawn`) and says where in a REVIVED event.
##
## The server checks a shot against the world as it is now: no rewind to what the shooter saw.
## A projectile flies for many ticks, so a rewind would not match what it meets; the shooter's
## own shot and every puppet's are cosmetic and decide nothing.

## Why a shot was refused (the REJECTED event's code).
enum Reason {
	NOT_FINITE = 1,  ## A number in the shot block is not finite.
	ORIGIN = 2,  ## The shot starts too far from the shooter's eye.
	COOLDOWN = 3,  ## Fire pressed with a shot block while the weapon cools down.
}

## What killed (the DIED event's code).
enum Cause {
	DAMAGE = 1,  ## A hit took the health to zero.
	OTHER = 2,  ## Anything else (a game's `die()`).
}

## Metres a shot's origin may be from the body's eye (the camera of a third-person view is behind
## the shoulder: 1.7 m out, more while sprinting).
var origin_slack := 4.0
## Seconds a dead body lies before the server gets it up.
var revive_seconds := 3.0
## On: a body gets up at its spawn point; off: where it died.
var revive_at_spawn := false
## Shots refused, shots fired, hits sent and deaths, since the start.
var rejected := 0
var shots := 0
var hits := 0
var deaths := 0

## `func(event: NetEvent)`: to every seated player.
var tell_all := Callable()
## `func(slot: int, event: NetEvent)`: to every player but `slot`.
var tell_others := Callable()
## `func(slot: int, event: NetEvent)`: to `slot` alone.
var tell := Callable()
## `func(slot: int) -> Transform3D`: where `slot` spawns.
var spawn_of := Callable()

var _bodies: Dictionary[int, Character] = {}
var _moving: Dictionary[int, Vector3] = {}
var _dead_for: Dictionary[int, float] = {}
# The slots whose health a hit took this step (a death then is `Cause.DAMAGE`).
var _damaged: Dictionary[int, bool] = {}


## Takes `body` as `slot`'s: it is named for HITs, its weapon fires real shots with no effects,
## seeded by the slot, and what it fires, hits and how it dies become events.
func watch(slot: int, body: Character) -> void:
	_bodies[slot] = body
	_moving[slot] = Vector3.ZERO
	body.set_meta(NetHits.SLOT_META, slot)
	body.died.connect(_on_died.bind(slot))
	var health := Health.of(body)
	if health != null:
		health.damaged.connect(func(_amount: float, _hit: HitRecord) -> void: _damaged[slot] = true)
	if body.weapon != null:
		body.weapon.effects = false
		body.weapon.authoritative = true
		body.weapon.seed_base = slot
		body.weapon.fired.connect(_on_fired.bind(slot, body))
		body.weapon.hit_scanned.connect(_on_scanned)


## Forgets `slot` (its body is being freed).
func forget(slot: int) -> void:
	_bodies.erase(slot)
	_moving.erase(slot)
	_dead_for.erase(slot)
	_damaged.erase(slot)


## Judges the shot block of `command` before `slot`'s body steps it; a refused one is taken off
## the command (with its fire presses) and its sender is told. Returns the `Reason`, or 0.
func judge(slot: int, body: Character, command: PlayerCommand) -> int:
	if not command.has_shot or body.is_dead():
		return 0
	var reason := reason_for(body, command, origin_slack)
	if reason == 0:
		return 0
	rejected += 1
	command.has_shot = false
	command.fire_pressed = false
	command.fire = false
	if tell.is_valid():
		tell.call(slot, NetEvent.rejected(command.seq, reason))
	return reason


## Why `body` may not fire the shot block of `command`, or 0.
static func reason_for(body: Character, command: PlayerCommand, slack: float) -> int:
	if not command.all_finite():
		return Reason.NOT_FINITE
	var eye := body.global_position + Vector3.UP * body.tuning.camera_height
	if command.origin.distance_to(eye) > slack:
		return Reason.ORIGIN
	if command.fire_pressed and body.weapon != null and body.weapon.is_cooling_down():
		return Reason.COOLDOWN
	return 0


## After `slot`'s body stepped: its velocity is what a death would carry.
func stepped(slot: int, body: Character) -> void:
	if not body.is_dead():
		_moving[slot] = body.velocity


## One server step of `delta` seconds: the dead lie, then get up.
func step(delta: float) -> void:
	_damaged.clear()
	for slot: int in _dead_for.keys():
		var body: Character = _bodies.get(slot)
		if body == null or not is_instance_valid(body):
			_dead_for.erase(slot)
			continue
		_dead_for[slot] += delta
		if _dead_for[slot] >= revive_seconds:
			_dead_for.erase(slot)
			_revive(slot, body)


# The shot of `slot`'s body left (inside its step): a SHOT to the others, and its projectile's
# touches become HITs.
func _on_fired(projectile: Projectile, slot: int, body: Character) -> void:
	var weapon := body.weapon
	shots += 1
	var held := body.loadout.held_slot() + 1 if body.loadout != null else 1
	var event := NetEvent.shot(
		slot, body.last_command.seq, weapon.last_origin, weapon.last_heading, held
	)
	if tell_others.is_valid():
		tell_others.call(slot, event)
	if projectile != null and not projectile.impacted.is_connected(_on_impacted):
		projectile.impacted.connect(_on_impacted)


func _on_impacted(collider: Node, point: Vector3, normal: Vector3) -> void:
	_send_hit(collider, point, normal)


func _on_scanned(hit: Dictionary) -> void:
	_send_hit(hit.get("collider"), hit.get("position", Vector3.ZERO), hit.get("normal", Vector3.UP))


## A HIT for what a shot that is not a player's met (an AI's: `AiBroadcast.hit_made`).
func send_hit(collider: Object, point: Vector3, normal: Vector3) -> void:
	_send_hit(collider, point, normal)


func _send_hit(collider: Object, point: Vector3, normal: Vector3) -> void:
	hits += 1
	var event := NetEvent.hit(
		point,
		normal,
		NetHits.kind_of(collider),
		NetHits.id_of(collider),
		NetHits.health_of(collider)
	)
	if tell_all.is_valid():
		tell_all.call(event)


func _on_died(slot: int) -> void:
	deaths += 1
	_dead_for[slot] = 0.0
	var cause := Cause.DAMAGE if _damaged.get(slot, false) else Cause.OTHER
	if tell_all.is_valid():
		tell_all.call(NetEvent.died(slot, _moving.get(slot, Vector3.ZERO), cause))


func _revive(slot: int, body: Character) -> void:
	var spot := body.global_position
	if revive_at_spawn and spawn_of.is_valid():
		spot = (spawn_of.call(slot) as Transform3D).origin
	# In whole centimetres, as the event carries it: every peer stands the body at the same float.
	body.revive_at(CommandCodec.snap_point(spot))
	_moving[slot] = Vector3.ZERO
	if tell_all.is_valid():
		tell_all.call(NetEvent.revived(slot, body.global_position))
