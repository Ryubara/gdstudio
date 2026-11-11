class_name AiAnimationThrottle
extends CharacterAnimationThrottle
## Moves AI characters' animation on less often where nobody would see the difference
## (gdstudio #1046). The `AiDirector` hands it each character it manages (its
## `animation_throttle`); without one, every character animates every frame as the player does.
##
## The rules are `CharacterAnimationThrottle`'s, with the director's tier as the base period: never
## at the Dormant tier (whatever the distance), `1` at Full and `reduced_period` at Reduced, so a
## Reduced character in view past `near_distance` moves every `reduced_period` frames, and at least
## `far_period` past `far_distance`. A tier change rechecks the character at once.
##
## Cosmetic and per machine: nothing here changes what the body does or what a network sends.

@export_group("Periods")
## Frames between two advances at the Reduced tier (in view, past `near_distance`).
@export_range(1, 30) var reduced_period := 3


func _base_period(character: Character) -> int:
	var ai := character as AiCharacter
	if ai == null:
		return 1
	if ai.tier == AiDirector.Tier.DORMANT:
		return 0
	return 1 if ai.tier == AiDirector.Tier.FULL else reduced_period


func _follow(character: Character, recheck_1: Callable, on: bool) -> void:
	var ai := character as AiCharacter
	if ai == null:
		return
	if on:
		ai.tier_changed.connect(recheck_1)
	else:
		ai.tier_changed.disconnect(recheck_1)
