class_name NetEvent
extends RefCounted
## Something that happened once, carried inside a TICK so its order against the snapshot is exact
## (a WebSocket is ordered). Each kind uses some of the fields; the layout after the kind byte:
##
## JOINED    u8 slot, u8 name length, the name (UTF-8, <= NAME_BYTES)          3 + name bytes
## LEFT      u8 slot                                                            2
## SHOT      u8 slot, u16 seq (its low 16 bits), u8 weapon (the loadout slot
##           + 1, 0 the empty hands), s16 origin x/y/z (cm), u16 yaw, s16 pitch  15
## HIT       s16 point x/y/z (cm), u16 normal yaw, s16 normal pitch, u8 code
##           (what was hit, `NetHits.Kind`), u16 id (the target, `NO_ID` for
##           none), u8 health left (`NO_HEALTH` for a thing with none)          15
## DIED      u8 slot, s16 velocity x/y/z (cm/s), u8 code (the cause)            9
## REVIVED   u8 slot, s16 position x/y/z (cm)                                   8
## ENTITY    u16 id, u32 tick (when the new state starts), u8 state length,
##           the state (<= MAX_ENTITY_STATE)                                    8 + state bytes
## PICKUP    u16 id, u8 slot                                                    4
## REJECTED  u32 seq (the client's command), u8 code (why)                      6
## AI        u16 id (the AI character's), u8 code (`AiCode`), s16 point x/y/z
##           (cm: where a shot left; cm/s: a death's velocity), u16 yaw, s16
##           pitch (a shot's way)                                               14
##
## Cosmetics (a ragdoll, an impact, a sound) are never events of their own: each peer makes them
## from these.

enum Kind {
	JOINED = 1,
	LEFT = 2,
	SHOT = 3,
	HIT = 4,
	DIED = 5,
	REVIVED = 6,
	ENTITY = 7,
	PICKUP = 8,
	REJECTED = 9,
	AI = 10,
}

## What happened to an AI character (an AI event's code): each client plays its own cosmetics
## from it (a bark, a ragdoll, a muzzle flash), and the rows carry the state.
enum AiCode {
	ALERTED = 1,  ## Its situation rose to Alert or Engaged.
	DIED = 2,  ## It died; the point is its velocity.
	FIRED = 3,  ## Its weapon fired; the point is where the shot left, the direction its way.
	REVIVED = 4,  ## It got up where its row says.
}

## The id of a hit that struck no networked part.
const NO_ID := 0xFFFF
## The health byte of a hit on something that has no `Health`.
const NO_HEALTH := 0xFF

var kind := Kind.LEFT
## The player it is about.
var slot := 0
## A command's number (REJECTED; a SHOT carries its low 16 bits).
var seq := 0
## Metres: the shot's origin, the hit's point, the revived body's place; metres a second: the
## dead body's velocity.
var point := Vector3.ZERO
## A unit direction: the shot's aim, the hit's surface normal.
var direction := Vector3.FORWARD
## A small number whose meaning is the kind's: what was hit, the cause of death, why a command
## was refused.
var code := 0
## A networked part's id (HIT, ENTITY, PICKUP).
var id := 0
## The weapon a SHOT left (the loadout slot + 1, 0 the empty hands); the health a HIT left
## (`Health.wire_value()`, `NO_HEALTH` for none).
var amount := 0
## The server tick an entity's new state starts at.
var tick := 0
var player_name := ""
## An entity's new state.
var state := PackedByteArray()


static func joined(player_slot: int, joined_name: String) -> NetEvent:
	var event := _of(Kind.JOINED, player_slot)
	event.player_name = joined_name
	return event


static func left(player_slot: int) -> NetEvent:
	return _of(Kind.LEFT, player_slot)


static func shot(
	player_slot: int, command_seq: int, origin: Vector3, aim: Vector3, weapon := 1
) -> NetEvent:
	var event := _of(Kind.SHOT, player_slot)
	event.seq = command_seq
	event.amount = weapon
	event.point = origin
	event.direction = aim
	return event


static func hit(
	at: Vector3, normal: Vector3, surface: int, target_id := NO_ID, health_left := NO_HEALTH
) -> NetEvent:
	var event := _of(Kind.HIT, 0)
	event.point = at
	event.direction = normal
	event.code = surface
	event.id = target_id
	event.amount = health_left
	return event


static func died(player_slot: int, velocity: Vector3, cause: int) -> NetEvent:
	var event := _of(Kind.DIED, player_slot)
	event.point = velocity
	event.code = cause
	return event


static func revived(player_slot: int, at: Vector3) -> NetEvent:
	var event := _of(Kind.REVIVED, player_slot)
	event.point = at
	return event


static func entity(entity_id: int, start_tick: int, new_state: PackedByteArray) -> NetEvent:
	var event := _of(Kind.ENTITY, 0)
	event.id = entity_id
	event.tick = start_tick
	event.state = new_state
	return event


static func pickup(entity_id: int, player_slot: int) -> NetEvent:
	var event := _of(Kind.PICKUP, player_slot)
	event.id = entity_id
	return event


## Something that happened to AI character `ai_id` (`AiCode`).
static func ai(ai_id: int, what: AiCode, at := Vector3.ZERO, way := Vector3.FORWARD) -> NetEvent:
	var event := _of(Kind.AI, 0)
	event.id = ai_id
	event.code = what
	event.point = at
	event.direction = way
	return event


static func rejected(command_seq: int, reason: int) -> NetEvent:
	var event := _of(Kind.REJECTED, 0)
	event.seq = command_seq
	event.code = reason
	return event


func all_finite() -> bool:
	return point.is_finite() and direction.is_finite()


static func _of(event_kind: Kind, player_slot: int) -> NetEvent:
	var event := NetEvent.new()
	event.kind = event_kind
	event.slot = player_slot
	return event
