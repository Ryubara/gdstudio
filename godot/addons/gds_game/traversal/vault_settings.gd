@tool
class_name VaultSettings
extends Resource
## Every number of vaulting and mantling, in one resource: what starts it, how far ahead and how
## square-on an obstacle is looked for, which heights and depths are vaulted or mantled, how much
## room the landing needs and how long each takes. A character holds one (3D Third Person's
## `vault_settings.tres`); a copy of the file gives another feel. A number is read where it is
## used, so a change in the inspector works while the game runs.
##
## The defaults and where they come from are in the kit's
## `docs/engines/godot/third-person/traversal.md`.

## What starts a vault or a mantle.
enum Trigger {
	## Pressing jump near an obstacle that may be crossed (the jump becomes the vault).
	PRESS_JUMP,
	## Sprinting into it, with no button.
	AUTO_ON_SPRINT,
	## Either.
	BOTH,
}

@export_group("Trigger")
## What starts a vault or a mantle. Jump works on every device (key, pad button, the touch Jump
## button) with no new action; the automatic one needs the sprint held.
@export var trigger := Trigger.PRESS_JUMP
## With the automatic trigger, the least ground speed that starts it: about a sprint, so a walk
## along a low wall never climbs it.
@export_range(0.0, 15.0, 0.05, "suffix:m/s") var auto_min_speed := 5.5
## The least ground speed a vault needs; slower, the obstacle is mantled instead (when it may be).
## 0 lets a standing character vault.
@export_range(0.0, 15.0, 0.05, "suffix:m/s") var min_vault_speed := 0.0
## Seconds after a vault or a mantle before the next may start.
@export_range(0.0, 2.0, 0.01, "suffix:s") var cooldown := 0.25

@export_group("Detection")
## How far past the front of the body an obstacle is looked for.
@export_range(0.1, 3.0, 0.01, "suffix:m") var detect_distance := 0.7
## On top of `detect_distance`, how far the body goes in this many seconds at its speed: a press a
## moment early at a run still finds the obstacle (and a jump is not made instead).
@export_range(0.0, 1.0, 0.01, "suffix:s") var detect_ahead_time := 0.15
## The widest angle between where the character goes and straight at the obstacle's face; more
## oblique, nothing happens (the crossing always goes square across the face).
@export_range(0.0, 89.0, 0.5, "suffix:deg") var max_approach_angle := 35.0
## The radius of the sphere cast down onto the obstacle's top (a rail thinner than this is still
## found; larger rounds off a lip).
@export_range(0.02, 0.5, 0.01, "suffix:m") var top_probe_radius := 0.08
## The steepest top that still counts as a top to plant a hand or stand on.
@export_range(0.0, 80.0, 1.0, "suffix:deg") var max_top_slope := 30.0

@export_group("Vault")
## The lowest obstacle that is vaulted; lower ones are stepped or jumped. Keep it above the
## character's step height.
@export_range(0.0, 2.0, 0.01, "suffix:m") var min_vault_height := 0.45
## The highest obstacle that is vaulted; higher ones are mantled.
@export_range(0.0, 3.0, 0.01, "suffix:m") var max_vault_height := 1.3
## From this height up the high vault clip plays (two hands) instead of the low one.
@export_range(0.0, 3.0, 0.01, "suffix:m") var high_vault_above := 1.0
## The thickest obstacle that is vaulted over; a deeper one is mantled onto.
@export_range(0.05, 3.0, 0.01, "suffix:m") var max_vault_depth := 0.9
## How far above the obstacle's top the feet pass while crossing.
@export_range(0.0, 1.0, 0.01, "suffix:m") var foot_clearance := 0.12
## How far past the far face (beyond the body's radius) the feet land.
@export_range(0.0, 2.0, 0.01, "suffix:m") var landing_margin := 0.3
## How far below the floor the character stands on the landing may be; a deeper drop (a cliff
## behind a parapet) is not vaulted.
@export_range(0.0, 5.0, 0.05, "suffix:m") var max_drop := 1.2
## The least speed the crossing goes at, however slowly it started; faster entries keep their
## speed (the clip plays faster to match).
@export_range(0.5, 15.0, 0.05, "suffix:m/s") var crossing_speed := 4.0
## The shortest a vault may take, however fast; the clip is never sped up past this.
@export_range(0.1, 2.0, 0.01, "suffix:s") var min_vault_time := 0.45
## The longest a vault may take, however long the crossing.
@export_range(0.1, 3.0, 0.01, "suffix:s") var max_vault_time := 0.9
## The share of the crossing speed kept on landing (1 runs on at that speed).
@export_range(0.0, 1.0, 0.01) var exit_speed_share := 0.85
## When the hand plants on the top, as a share of the vault's time: the clip's own contact time
## over its length (the body is over the near edge then).
@export_range(0.05, 0.9, 0.01) var plant_at := 0.3
## When the feet are past the far edge, as a share of the vault's time.
@export_range(0.1, 0.95, 0.01) var clear_at := 0.7

@export_group("Mantle")
## The lowest obstacle that is mantled onto.
@export_range(0.0, 2.0, 0.01, "suffix:m") var min_mantle_height := 0.45
## The highest obstacle that is mantled onto (about the standing reach with a small jump).
@export_range(0.0, 3.5, 0.01, "suffix:m") var max_mantle_height := 2.0
## From this height up the high mantle clip plays.
@export_range(0.0, 3.5, 0.01, "suffix:m") var high_mantle_above := 1.25
## Seconds a mantle takes onto an obstacle of no height; each metre adds `mantle_time_per_metre`.
@export_range(0.1, 3.0, 0.01, "suffix:s") var mantle_base_time := 0.45
## Seconds each metre of height adds to a mantle.
@export_range(0.0, 3.0, 0.01, "suffix:s/m") var mantle_time_per_metre := 0.5
## When the feet reach the top's height, as a share of the mantle's time; after it the body
## moves onto the top.
@export_range(0.1, 0.95, 0.01) var mantle_top_at := 0.7
## How far onto the top (beyond the body's radius) the feet end.
@export_range(0.0, 1.0, 0.01, "suffix:m") var mantle_inset := 0.1

@export_group("Body")
## On: aiming and firing stop for the whole vault or mantle (both hands are busy).
@export var drop_aim := true


## How far ahead of the body's front an obstacle is looked for at `speed` m/s.
func detect_reach(speed: float) -> float:
	return detect_distance + maxf(speed, 0.0) * detect_ahead_time


## How long a vault takes over a crossing of `distance` metres (flat) entered at `speed` m/s.
func vault_time(distance: float, speed: float) -> float:
	var pace := maxf(speed, crossing_speed)
	return clampf(distance / pace, min_vault_time, max_vault_time)


## How long a mantle onto an obstacle `height` metres high takes.
func mantle_time(height: float) -> float:
	return mantle_base_time + mantle_time_per_metre * maxf(height, 0.0)
