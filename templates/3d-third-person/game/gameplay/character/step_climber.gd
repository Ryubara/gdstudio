class_name StepClimber
extends RefCounted
## Lifts a character body over a low edge in its way (a stair, a kerb) so it walks up instead of
## stopping against it. A capsule's rounded foot climbs only a few centimetres on its own.
##
## The test is made with the body's own shape before it moves: is something in the way, is there
## room above it, is the way clear at step height, and is there floor you can stand on just past
## it.

## How much farther than the step's height the probe looks down for the top of the step.
const PROBE_MARGIN := 0.02
## A rise smaller than this is not a step.
const MIN_RISE := 0.01

# What the first test hit, made once and filled again on every call (a body walking on open ground
# runs that test every tick and it finds nothing; making the object was a fifth of the climb's
# cost). Null until the first climb (no initialiser: `static-variables.md#the-rule`).
static var _wall: KinematicCollision3D


## Returns how far the body was lifted (0 when nothing was in the way or the edge was too high).
## `motion` is where the body is about to go this tick, flat (y = 0). The top of the step is
## looked for `reach` ahead of the body at least: more than the body's radius, or the probe
## lands on the step's rounded edge and sees a slope.
static func climb(
	body: CharacterBody3D, motion: Vector3, step_height: float, max_slope: float, reach: float
) -> float:
	if motion.length_squared() < 0.000001 or step_height <= 0.0:
		return 0.0
	var from := body.global_transform
	if _wall == null:
		_wall = KinematicCollision3D.new()
	var wall := _wall
	if not body.test_move(from, motion, wall):
		return 0.0
	# Floor in the way is the floor snap's job, not a step.
	if wall.get_normal().angle_to(Vector3.UP) < deg_to_rad(max_slope):
		return 0.0
	var lift := Vector3.UP * step_height
	if body.test_move(from, lift):
		return 0.0
	var raised := from.translated(lift)
	var ahead := motion.normalized() * maxf(motion.length(), reach)
	if body.test_move(raised, ahead):
		return 0.0
	var top := KinematicCollision3D.new()
	var over := raised.translated(ahead)
	var probe := Vector3.DOWN * (step_height + PROBE_MARGIN)
	if not body.test_move(over, probe, top):
		return 0.0
	if top.get_normal().angle_to(Vector3.UP) > deg_to_rad(max_slope):
		return 0.0
	var rise := step_height - absf(top.get_travel().y)
	if rise < MIN_RISE:
		return 0.0
	body.global_position.y += rise
	return rise
