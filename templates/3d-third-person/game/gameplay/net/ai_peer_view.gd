class_name AiPeerView
extends RefCounted
## What one client holds of the AI characters (the server keeps one in each `PeerSlot`): the
## sequence of the last AI snapshot sent to it, each character's row as it was sent and when.
## A WebSocket is ordered and reliable, so what the server sent is what the client applied, unless
## the socket refused a TICK (`reset`: the next snapshot is full) or the client dropped one (the
## next keyframe mends it).

## The sequence of the last snapshot sent (0 to 255), -1 before the first: the next is full.
var seq := -1
## Each character the client holds: its 14 bytes as last sent, and the server tick they left.
var sent: Dictionary[int, PackedByteArray] = {}
var sent_tick: Dictionary[int, int] = {}
## The server tick of the last full snapshot.
var full_tick := 0
## Where the client's body is, metres from the section's origin.
var viewer := Vector3.ZERO
## The client cannot hold more AI characters than this (the population cap of the match).
var cap := NetLimits.MAX_AI_ROWS


## The next snapshot is full (the client joined, or a TICK did not leave).
func reset() -> void:
	seq = -1
	sent.clear()
	sent_tick.clear()


func has_baseline() -> bool:
	return seq >= 0


## Whether the client holds character `id`.
func holds(id: int) -> bool:
	return sent.has(id)
