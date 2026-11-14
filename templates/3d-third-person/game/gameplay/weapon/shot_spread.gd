class_name ShotSpread
extends RefCounted
## How far a weapon's next shot may go off the aim (gdstudio #1411). A first shot from rest goes
## where the aim is (`WeaponDef.first_shot_spread`, 0 by default); each shot fired in a row adds
## to the spread, up to `WeaponDef.spread` after `spread_build_shots`, and it falls back over
## `spread_recovery_time` on the ticks the weapon is ready and not fired. The `Weapon` owns one:
## `draw()` turns a shot, `recover()` runs on its tick. `heat` is step state (the weapon's
## `save_step_state`), so a server and a predicting client draw the same cone.

## Where the spread is between a first shot's (0) and the most (1).
var heat := 0.0


## The cone of the next shot, in degrees, for `definition` (before the character's share).
func degrees(definition: WeaponDef) -> float:
	var most := maxf(definition.spread, definition.first_shot_spread)
	return lerpf(definition.first_shot_spread, most, heat)


## Turns `heading` off by up to the cone of this shot times `share`, drawn from `rng` (a seeded
## generator: every peer draws the same), and counts the shot into the spread.
func draw(
	heading: Vector3, definition: WeaponDef, share: float, rng: RandomNumberGenerator
) -> Vector3:
	var cone := degrees(definition) * share
	heat = minf(heat + 1.0 / maxf(definition.spread_build_shots, 1.0), 1.0)
	if cone <= 0.0:
		return heading
	var angle := deg_to_rad(cone) * sqrt(rng.randf())
	var around := rng.randf() * TAU
	var side := heading.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(heading).normalized()
	return heading.rotated(side, sin(around) * angle).rotated(up, cos(around) * angle)


## Lets the spread fall by one tick of `delta` seconds (the weapon calls it on the ticks it was
## ready to fire and did not).
func recover(definition: WeaponDef, delta: float) -> void:
	if definition.spread_recovery_time <= 0.0:
		heat = 0.0
	else:
		heat = maxf(heat - delta / definition.spread_recovery_time, 0.0)


## Seconds from a shot (at the most spread) until a first shot from rest: the shot interval and the
## recovery.
static func rest_time(definition: WeaponDef) -> float:
	return definition.shot_interval() + definition.spread_recovery_time
