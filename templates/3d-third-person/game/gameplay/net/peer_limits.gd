class_name PeerLimits
extends RefCounted
## What one connection may send a game server, and what happens when it sends more: the exact
## size of each message, how often each may come, one HELLO, and a strike count that hangs up on a
## peer that keeps breaking them (`judge`). An honest client sends a command each tick (60 a
## second), a ping twice a second and one hello; after a stall of a few seconds every late
## command arrives together, and the burst takes that.
##
## A packet over its rate is dropped and costs a little; one the server cannot make sense of
## (empty, too long, an unknown type, the wrong size for its type, a second hello) costs more.
## Strikes wear off, so a client that bunched after a stall is forgiven, and a flood is cut off
## after a few hundred packets. Every drop is counted by reason in `drops`. Time is the caller's
## (seconds from any clock that only goes forward).

enum Verdict { ACCEPT, DROP, KICK }

## No message a client sends is longer.
const MAX_PACKET := NetWire.MAX_CLIENT_PACKET
## Strikes at which the peer is hung up on, how many wear off a second, and what each fault costs.
const KICK_AT := 100.0
const FORGIVE_PER_SECOND := 5.0
const STRIKE_RATE := 0.5
const STRIKE_BAD := 5.0

## Per message type: the messages a second it may keep up, and how many may come at once.
const RATES := {
	NetWire.Type.HELLO: Vector2(1.0, 1.0),
	NetWire.Type.COMMAND:
	Vector2(NetLimits.TICK_RATE * 1.5, NetLimits.TICK_RATE * NetLimits.STALL_SECONDS),
	NetWire.Type.PING: Vector2(NetLimits.PING_RATE * 2.0, NetLimits.PING_RATE * 3.0),
}

## Why this peer's packets were dropped.
var drops := NetDrops.new()
var strikes := 0.0
## True once a verdict was KICK; every later packet is a KICK too.
var kicked := false

var _buckets: Dictionary[int, TokenBucket] = {}
var _hello_seen := false
var _at := -1.0


func _init() -> void:
	for type: int in RATES:
		_buckets[type] = TokenBucket.new(RATES[type].x, RATES[type].y)


## Whether a client's message of this type may be this long: a HELLO is its header and a name of
## up to `NetLimits.NAME_BYTES`, a COMMAND 15 bytes or 27 with a shot block, a PING 7.
static func fits(type: int, size: int) -> bool:
	match type:
		NetWire.Type.HELLO:
			return size >= NetWire.HELLO_HEADER and size <= NetWire.MAX_HELLO
		NetWire.Type.COMMAND:
			return size == NetWire.COMMAND_SIZE or size == NetWire.COMMAND_SHOT_SIZE
		NetWire.Type.PING:
			return size == NetWire.PING_SIZE
	return false


## What to do with a packet that came at time `now`.
func judge(data: PackedByteArray, now: float) -> Verdict:
	if kicked:
		return Verdict.KICK
	_forgive(now)
	var reason := _malformed(data)
	if reason != &"":
		return _strike(STRIKE_BAD, reason)
	if not _buckets[data[0]].take(now):
		return _strike(STRIKE_RATE, NetDrops.OVER_RATE)
	if data[0] == NetWire.Type.HELLO:
		_hello_seen = true
	return Verdict.ACCEPT


## A packet that passed `judge` whose content the server then refused (a decoder said null, a
## command out of order): it costs as much as a malformed one.
func fault(now: float, reason: StringName) -> Verdict:
	_forgive(now)
	return _strike(STRIKE_BAD, reason)


## Why a packet is malformed for this peer, or `&""` when it is not.
func _malformed(data: PackedByteArray) -> StringName:
	if data.is_empty():
		return NetDrops.EMPTY
	if data.size() > MAX_PACKET:
		return NetDrops.TOO_LONG
	var type := data[0]
	if not _buckets.has(type):
		return NetDrops.UNKNOWN_TYPE
	if type == NetWire.Type.HELLO and _hello_seen:
		return NetDrops.HELLO_TWICE
	# An old client's hello passes whatever its length, so the server can answer
	# `Refusal.VERSION`.
	if not fits(type, data.size()) and not _is_old_hello(data):
		return NetDrops.WRONG_SIZE
	return &""


static func _is_old_hello(data: PackedByteArray) -> bool:
	var version := NetWire.hello_version(data)
	return version >= 0 and not NetWire.accepts(version)


func _forgive(now: float) -> void:
	if _at >= 0.0 and now > _at:
		strikes = maxf(0.0, strikes - (now - _at) * FORGIVE_PER_SECOND)
	_at = maxf(_at, now)


func _strike(cost: float, reason: StringName) -> Verdict:
	strikes += cost
	drops.count(reason)
	if strikes >= KICK_AT:
		kicked = true
	return Verdict.KICK if kicked else Verdict.DROP
