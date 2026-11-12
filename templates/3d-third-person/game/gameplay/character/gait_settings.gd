class_name GaitSettings
extends Resource
## How `CharacterAnimation` fits the gaits to the body's real motion (gdstudio #1158): the speed
## matching, the transitions, the momentum blend and the lean, each its own choice here with its
## numbers. The template's characters share `gait_settings.tres`. All of it is cosmetic: it is
## worked out on each machine from the body's own motion and never sent.

@export_group("Speed matching")
## Plays each gait at the ground speed over the speed its clip covers (`GaitClips`, scaled by the
## body's leg length), with the ground blend space's points at the clips' speeds, so a planted
## foot keeps its place on the floor at any speed. Off: the points sit at the tuning's speeds and
## each clip plays at its own pace (the template before gdstudio #1158).
@export var speed_match := true:
	set(value):
		speed_match = value
		emit_changed()
## The slowest and fastest a gait is played against its own pace, so a speed far outside the
## clips' (a slide's tail, a tuning set to 12 m/s) never shows it crawling or blurred.
@export var pace_range := Vector2(0.4, 2.0)
## How far a gait is slowed (x) and sped up (y) on its own before the next one blends in: between
## two gaits the slower plays alone up to its speed times y, the faster from its speed times x,
## and only the speeds between are a blend. A blend of two clips holds a foot less well than one
## clip at another pace (the walk and the jog half and half let a planted foot slide 10 mm, either
## alone at 1.3 times its pace under 1 mm), so the blends are kept short.
@export var stretch := Vector2(0.8, 1.3)
## The slowest pace the first gait plays at on its own; below it the gait fades into the idle.
@export_range(0.1, 1.0, 0.01) var slowest_pace := 0.5

@export_group("Transitions")
## Plays a start, a stop, a reversal, a pivot or a turn on the spot when the controller does one
## and the clip for it is in the libraries (`GaitTransitionSet`); with no clip, or off, the body
## states blend as they always did.
@export var transitions := true
## The clips for each transition, by gait and planting foot.
@export var transition_clips: GaitTransitionSet
## Degrees between where the body moves and where it is asked to: from this a moving body plays a
## pivot, and from `reversal_angle` a reversal.
@export_range(10.0, 180.0, 1.0, "suffix:deg") var pivot_angle := 45.0
@export_range(90.0, 180.0, 1.0, "suffix:deg") var reversal_angle := 135.0
## Degrees a standing body's facing must be asked to turn before it plays a turn on the spot.
@export_range(10.0, 180.0, 1.0, "suffix:deg") var turn_angle := 50.0
## Below this ground speed the body is standing for the transitions (m/s).
@export_range(0.0, 2.0, 0.01, "suffix:m/s") var standing_speed := 0.3

@export_group("Momentum blend")
## Starts each body state from the pose and the motion the last one left and lets the difference
## die away (`MomentumBlend`, a `SkeletonModifier3D`), in place of the state machine's cross-fade.
## Off: the states cross-fade over `CharacterAnimation.blend_time`.
@export var momentum_blend := true:
	set(value):
		momentum_blend = value
		emit_changed()
## Seconds in which the difference halves: about a fifth of the cross-fade it replaces dies in
## each half-life, so 0.05 has it gone (under a degree) by 0.25 s.
@export_range(0.01, 0.5, 0.005, "suffix:s") var momentum_half_life := 0.05
## The fastest a bone's motion is carried into the new state, in degrees a second: a pose that
## jumped (a teleport, a model swap) is not flung on.
@export_range(0.0, 3600.0, 10.0, "suffix:deg/s") var momentum_speed_limit := 720.0

@export_group("Lean")
## Leans the body into its acceleration and its turns, from the lean poses (`lean_clips`) added
## over the locomotion. Built only when every lean clip is in the libraries: off until then.
@export var lean := true
## The four lean poses, by the way the body leans: `left`, `right`, `forward`, `back`.
@export var lean_clips: Dictionary[StringName, StringName] = {
	&"left": &"gds/Lean_Left",
	&"right": &"gds/Lean_Right",
	&"forward": &"gds/Lean_Fwd",
	&"back": &"gds/Lean_Back",
}
## The acceleration (along the body, and across it in a turn) that leans the body fully into a
## pose, in m/s².
@export_range(1.0, 80.0, 0.5, "suffix:m/s²") var lean_full_at := 20.0
## Seconds the lean takes to follow the body (a lag that keeps a jolt of the controller off it).
@export_range(0.0, 1.0, 0.01, "suffix:s") var lean_time := 0.12
