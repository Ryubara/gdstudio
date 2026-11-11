class_name AiBudget
extends RefCounted
## The costly work every AI character of one `AiDirector` shares in a physics tick: sight rays,
## path queries and thinks. A part asks before it spends (`take_ray()`, `take_path()`); a refusal
## means "not this tick", and the part tries again on its next think. The director resets the
## counts at the start of every tick, so 200 characters cast no more rays a tick than 50.
##
## Counts, not time: they do not move with the machine, so a test holds them exactly
## (`docs/engines/godot/performance-budgets.md#budgets-counts-tight-time-loose`).

## Sight rays all characters together may cast in one physics tick.
var rays_per_tick := 8
## Path queries all characters together may make in one physics tick.
var paths_per_tick := 4
## Thinks the director runs in one physics tick; a think over it waits for the next tick.
var thinks_per_tick := 12

## Rays taken this tick.
var rays := 0
## Path queries taken this tick.
var paths := 0
## Thinks run this tick.
var thinks := 0
## Requests refused this tick (rays, paths and thinks together), for the debug overlay and tests.
var refused := 0


## A new tick: every count back to 0.
func reset() -> void:
	rays = 0
	paths = 0
	thinks = 0
	refused = 0


## True, and counted, when a sight ray may be cast this tick.
func take_ray() -> bool:
	if rays >= rays_per_tick:
		refused += 1
		return false
	rays += 1
	return true


## True, and counted, when a path query may be made this tick.
func take_path() -> bool:
	if paths >= paths_per_tick:
		refused += 1
		return false
	paths += 1
	return true


## True, and counted, when one more think may run this tick.
func take_think() -> bool:
	if thinks >= thinks_per_tick:
		refused += 1
		return false
	thinks += 1
	return true
