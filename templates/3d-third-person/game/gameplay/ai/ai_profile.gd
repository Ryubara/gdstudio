@tool
class_name AiProfile
extends Resource
## What kind of character an AI is: every number its senses, its decisions and its budget read,
## in one resource per kind (`profiles/grunt.tres`, `ally.tres`, `civilian.tres`). The profile is
## the only game-specific part of an AI character: a copy of a file is another kind.
##
## A number is read where it is used, at the moment it is used (the `AiDirector` reads the think
## rates and the tier ranges at every think and every tier check), so an edit in the inspector or
## the remote inspector applies while the game runs. The defaults are the research's for kit #882
## (`docs/engines/godot/crowds.md#ai-characters` has the costs): a 10 Hz think, a person's
## reaction floor of 0.2 s, two rays a think.

## The shortest reaction a profile may set: a person's floor, under which an AI reads as a cheat.
const REACTION_FLOOR := 0.2

## The name shown above the head when the debug overlay is on, and in logs.
@export var display_name := "AI"

@export_group("Movement")
## A walk, as the navigator asks for it (patrols, searching).
@export_range(0.0, 10.0, 0.05, "suffix:m/s") var walk_speed := 1.6
## A run, as the navigator asks for it (engaging, fleeing).
@export_range(0.0, 12.0, 0.05, "suffix:m/s") var run_speed := 4.5
## How fast the body turns toward where it looks, in degrees a second.
@export_range(0.0, 1440.0, 1.0, "suffix:°/s") var turn_rate := 360.0
## How fast it reaches the speed it asks for.
@export_range(0.0, 60.0, 0.1, "suffix:m/s²") var acceleration := 12.0

@export_group("Senses")
## How far it sees a thing in its view cone.
@export_range(0.0, 200.0, 0.5, "suffix:m") var sight_range := 24.0
## How far a thing it already sees stays seen: above `sight_range`, so a thing on the edge does
## not blink in and out.
@export_range(0.0, 250.0, 0.5, "suffix:m") var lose_sight_range := 32.0
## Half the view cone's width, from straight ahead.
@export_range(0.0, 180.0, 0.5, "suffix:°") var half_angle := 55.0
## Anything this near is noticed whichever way it faces (a swing within arm's reach).
@export_range(0.0, 20.0, 0.1, "suffix:m") var near_radius := 2.0
## How far a noise of loudness 1 is heard.
@export_range(0.0, 200.0, 0.5, "suffix:m") var hearing_range := 30.0
## Seconds of looking at a thing in plain view, near and ahead, before it is noticed; farther
## and to the side is slower.
@export_range(0.0, 10.0, 0.05, "suffix:s") var time_to_notice := 0.6
## Seconds from noticing a threat to acting on it; never under `REACTION_FLOOR`.
@export_range(REACTION_FLOOR, 3.0, 0.01, "suffix:s") var reaction_time := 0.35
## Seconds a thing it lost sight of is remembered (where it was last).
@export_range(0.0, 120.0, 0.5, "suffix:s") var memory_seconds := 6.0
## Awareness (0 to 1) at which it turns Suspicious and looks toward a thing; at 1 it is Alert.
@export_range(0.0, 1.0, 0.01) var suspicious_at := 0.3
## How far awareness falls under a threshold before the situation calms back down, so a value
## that wobbles on a line changes the situation once.
@export_range(0.0, 0.5, 0.01) var awareness_hysteresis := 0.1

@export_group("Combat")
## The distance from which it starts a fight with a seen enemy.
@export_range(0.0, 200.0, 0.5, "suffix:m") var engage_range := 18.0
## The distance it tries to fight from.
@export_range(0.0, 200.0, 0.5, "suffix:m") var preferred_range := 10.0
## The reach of a melee blow.
@export_range(0.0, 10.0, 0.05, "suffix:m") var attack_range := 1.6
## Seconds between shots of a burst.
@export_range(0.0, 5.0, 0.01, "suffix:s") var fire_interval := 0.4
## Shots in a burst before it lets go of the trigger.
@export_range(1, 30) var burst_size := 3
## How well it aims, 0 (sprays) to 1 (on the point it aims at once settled).
@export_range(0.0, 1.0, 0.01) var accuracy := 0.5
## How fast its aim turns onto a target, in degrees a second.
@export_range(0.0, 1440.0, 1.0, "suffix:°/s") var aim_speed := 360.0
## How much nearer than `preferred_range` an enemy may come before it backs off.
@export_range(0.0, 50.0, 0.5, "suffix:m") var retreat_margin := 3.0

@export_group("Nerve")
## 0 (a coward: flees early, holds back) to 1 (brave).
@export_range(0.0, 1.0, 0.01) var courage := 0.5
## The share of its health under which it flees, scaled down by `courage`.
@export_range(0.0, 1.0, 0.01) var flee_below_health := 0.3
## Seconds a fleeing character takes to calm down once safe.
@export_range(0.0, 60.0, 0.5, "suffix:s") var panic_recovery_seconds := 8.0
## 0 (waits to be attacked) to 1 (seeks a fight).
@export_range(0.0, 1.0, 0.01) var aggression := 0.5
## 0 (ignores a noise) to 1 (goes to look).
@export_range(0.0, 1.0, 0.01) var curiosity := 0.5
## Seconds it stays Alert after losing every threat before it turns Suspicious.
@export_range(0.0, 120.0, 0.5, "suffix:s") var alert_hold_seconds := 10.0
## The least time a situation holds before it may calm down (Engaged to Alert, Alert to
## Suspicious) or turn sideways (Engaged to Fleeing): a wobble changes it once. Rising (Unaware
## to Alert, a hit to Engaged) and dying are at once.
@export_range(0.0, 10.0, 0.05, "suffix:s") var situation_dwell := 1.0

@export_group("Social")
## The side it is on; the factions table says who is an enemy of whom.
@export var faction := &"neutral"
## How far it tells its allies what it knows.
@export_range(0.0, 100.0, 0.5, "suffix:m") var share_radius := 12.0
## Seconds between noticing a thing and telling the allies within `share_radius` about it (a
## shout takes a moment); each ally passes a told thing on at most once.
@export_range(0.0, 10.0, 0.05, "suffix:s") var share_delay := 0.5
## 0 (ignores orders) to 1 (always obeys).
@export_range(0.0, 1.0, 0.01) var obeys_orders := 0.5

@export_group("Budget")
## Thinks a second at the Full tier (near a player), each on the character's own phase.
@export_range(0.0, 60.0, 0.1, "suffix:Hz") var think_rate := 10.0
## Thinks a second at the Reduced tier.
@export_range(0.0, 60.0, 0.1, "suffix:Hz") var reduced_think_rate := 2.0
## Thinks a second at the Dormant tier; 0 never thinks there.
@export_range(0.0, 60.0, 0.05, "suffix:Hz") var dormant_think_rate := 0.5
## Nearer than this to a player's body: the Full tier.
@export_range(0.0, 500.0, 0.5, "suffix:m") var full_range := 25.0
## Nearer than this (and past `full_range`): the Reduced tier; farther: Dormant.
@export_range(0.0, 1000.0, 0.5, "suffix:m") var reduced_range := 70.0
## How far past a range a character goes before it drops a tier, so one walking along the line
## does not flip each check.
@export_range(0.0, 50.0, 0.5, "suffix:m") var tier_margin := 4.0
## The most sight rays one think may cast (the director also caps them a tick).
@export_range(0, 16) var max_rays_per_think := 2
## Seconds between path queries while it follows a moving goal.
@export_range(0.05, 10.0, 0.05, "suffix:s") var repath_seconds := 0.25


## The think rate (a second) at `tier` (`AiDirector.Tier`).
func think_rate_at(tier: int) -> float:
	match tier:
		AiDirector.Tier.FULL:
			return think_rate
		AiDirector.Tier.REDUCED:
			return reduced_think_rate
	return dormant_think_rate
