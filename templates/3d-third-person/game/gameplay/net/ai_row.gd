class_name AiRow
extends RefCounted
## One AI character as a snapshot carries it (`AiSnapshot`, 14 bytes on the wire): what a client
## needs to draw and animate it and nothing it could work out itself. Positions are metres from the
## section's origin (`AiReplica.section_origin`, the server's `ai_section_origin`).

## The wire id (`NetHits.AI_BASE + id` in a HIT), 0 to `NetLimits.MAX_AI_ID`.
var id := 0
var position := Vector3.ZERO
## The heading the body faces (`Character.facing`), radians.
var yaw := 0.0
## The flat speed, metres a second (0.05 steps, at most 12.75).
var speed := 0.0
## `AiSituation.Situation`.
var situation := 0
## `Character.State`.
var state := 0
var aiming := false
## What it is after, as a HIT names it (`NetHits.id_of`), `AiSnapshot.NO_TARGET` for nothing.
var target := AiSnapshot.NO_TARGET
## The look it is drawn in: the index of its profile in the server's `ai_variants` (the client's
## `AiReplica.variant_scenes` at the same index).
var variant := 0


## Dead by its situation or its body's state.
func is_dead() -> bool:
	return situation == AiSituation.Situation.DEAD or state == Character.State.DEAD


func all_finite() -> bool:
	return position.is_finite() and is_finite(yaw) and is_finite(speed)


func copy() -> AiRow:
	var out := AiRow.new()
	out.id = id
	out.position = position
	out.yaw = yaw
	out.speed = speed
	out.situation = situation
	out.state = state
	out.aiming = aiming
	out.target = target
	out.variant = variant
	return out
