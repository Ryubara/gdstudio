class_name AiTierRates
extends Resource
## How often a client hears of each AI character, by how far it is from that client's body: near
## ones every TICK, farther ones a few times a second, far ones once a second, and none past the
## interest radius (`AiSnapshot.encode` reads it for each client). The server's `ai_rates`
## (`net_server.tscn`); `ai_tier_rates.tres` holds the template's numbers.

## The send tiers, nearest first; `OUT` is past the interest radius (not sent).
enum Tier { FULL, REDUCED, DORMANT, OUT }

@export_group("Distances")
## Metres from a client's body within which a character is sent at `full_hz`.
@export_range(0.0, 500.0, 0.5, "suffix:m") var full_radius := 20.0
## Metres within which it is sent at `reduced_hz` (past `full_radius`).
@export_range(0.0, 500.0, 0.5, "suffix:m") var reduced_radius := 40.0
## Metres within which it is sent at all, at `dormant_hz` past `reduced_radius`: the interest
## radius. A character farther away is taken out of that client's view.
@export_range(0.0, 1000.0, 0.5, "suffix:m") var interest_radius := 80.0

@export_group("Rates")
## Sends a second of a near character (at most the TICK rate, 30).
@export_range(0.5, 30.0, 0.5, "suffix:Hz") var full_hz := 30.0
## Sends a second of a character past `full_radius`.
@export_range(0.5, 30.0, 0.5, "suffix:Hz") var reduced_hz := 7.5
## Sends a second of a character past `reduced_radius`.
@export_range(0.1, 30.0, 0.1, "suffix:Hz") var dormant_hz := 1.0
## Seconds between two full snapshots to a client, which mend anything a lost delta left wrong;
## 0 sends a full one only to a client that joins or whose TICK the socket refused.
@export_range(0.0, 120.0, 0.5, "suffix:s") var keyframe_seconds := 10.0


## The tier of a character `distance` metres from a client's body.
func tier_for(distance: float) -> Tier:
	if distance <= full_radius:
		return Tier.FULL
	if distance <= reduced_radius:
		return Tier.REDUCED
	if distance <= interest_radius:
		return Tier.DORMANT
	return Tier.OUT


## Server ticks between two sends of a character at `tier` (at least one; `OUT` is never sent).
func interval_ticks(tier: Tier) -> int:
	var hz := full_hz
	match tier:
		Tier.REDUCED:
			hz = reduced_hz
		Tier.DORMANT:
			hz = dormant_hz
	return maxi(roundi(NetLimits.TICK_RATE / maxf(hz, 0.01)), 1)


## Server ticks between two keyframes (0 for none).
func keyframe_ticks() -> int:
	return roundi(keyframe_seconds * NetLimits.TICK_RATE)
