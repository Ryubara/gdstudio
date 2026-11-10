class_name NetLink
extends RefCounted
## One end of a connection that carries packets (`PackedByteArray`s) in order, whatever carries
## them: a WebSocket to a game server (`WebSocketLink`), an in-process pair (`LoopbackLink`), or
## either of those behind a bad network (`LinkConditioner`). A link never reads the bytes it
## carries: what a packet means is the packets' business (`gameplay/net/`'s codecs), not the
## transport's.
##
## Call `poll` once per physics tick (`_physics_process`), never from `_process`: the tick then has
## the same rate on every machine and in a headless server, and arrivals round to the tick on every
## platform alike. `packet_received` fires from inside `poll`, in the order the packets were sent.
##
## A WebSocket is TCP: nothing is lost or reordered, so a bad network shows as a stall followed by a
## burst, never as a missing packet. Design what rides on it for stalls (multiplayer.md).

## A packet arrived (fired from `poll`).
signal packet_received(data: PackedByteArray)
## The link became open: packets sent from now on go out (fired from `poll`).
signal connected
## The link is finished (fired from `poll`, once, after the last packet that arrived before the
## close). `left_on_purpose()` then says whether the other end said goodbye.
signal closed

## The close code of a clean goodbye, and of a page being closed (RFC 6455).
const CLOSE_NORMAL := 1000
const CLOSE_GOING_AWAY := 1001
## The close code when no close frame came (the network went).
const CLOSE_NONE := -1

## Bytes and packets this end has sent and received, for the numbers a run prints.
var bytes_in := 0
var bytes_out := 0
var packets_in := 0
var packets_out := 0


## Puts one packet on the link; false when it was not taken (the link is not open, or its buffer is
## full). A packet sent before `connected` is not taken.
func send(_data: PackedByteArray) -> bool:
	return false


## Once per physics tick: moves what is due in each direction and fires the signals.
func poll() -> void:
	pass


func is_open() -> bool:
	return false


## Ends the link with a clean goodbye (close code 1000). `closed` follows from `poll`.
func close() -> void:
	pass


## The close code the link ended with (`CLOSE_NONE` while open, or when the network went without a
## close frame).
func close_code() -> int:
	return CLOSE_NONE


## Whether the other end (or this one) said goodbye on purpose: a clean close (1000) or a page going
## away (1001), against a network that went (no close frame, or any other code).
func left_on_purpose() -> bool:
	return NetLink.is_goodbye(close_code())


## Whether `code` is a goodbye on purpose (1000 or 1001).
static func is_goodbye(code: int) -> bool:
	return code == CLOSE_NORMAL or code == CLOSE_GOING_AWAY
