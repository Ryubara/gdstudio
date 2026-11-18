class_name GaitSettings
extends Resource
## How `CharacterAnimation` fits the gaits to the body's real motion (gdstudio #1158): the speed
## matching, the transitions, the momentum blend, the lean and the jump's clips (gdstudio #1371),
## each its own choice here with its numbers. The template's characters share
## `gait_settings.tres`. All of it is cosmetic: it is worked out on each machine from the body's
## own motion and never sent.

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
## The least time the drawn blend takes to cross a seam: two gaits whose stretched ranges meet with
## no speeds between to blend them (the jog alone to 5.2 m/s, the sprint alone from 5.2). The
## body's 28 m/s² crossed it in one tick and the pose went from the jog's to the sprint's at once,
## a foot 0.28 m in a tick (gdstudio #1578). A blend with speeds of its own (the walk and the jog)
## follows the speed as before. 0: a seam is crossed at once.
@export_range(0.0, 0.5, 0.01, "suffix:s") var gait_change_time := 0.1

@export_group("Transitions")
## Plays a start, a stop, a reversal, a pivot or a turn on the spot when the controller does one
## and the clip for it is in the libraries (`GaitTransitionSet`); with no clip, or off, the body
## states blend as they always did.
@export var transitions := true
## The clips for each transition, by gait and planting foot.
@export var transition_clips: GaitTransitionSet
## Degrees a standing body's facing must be asked to turn before it plays a turn on the spot.
@export_range(10.0, 180.0, 1.0, "suffix:deg") var turn_angle := 50.0
## Below this ground speed the body is standing for the transitions (m/s).
@export_range(0.0, 2.0, 0.01, "suffix:m/s") var standing_speed := 0.3
## The fastest a turn on the spot's clip runs to catch up with the body, against its own pace
## (2 before gdstudio #1565: a half turn took 0.9 s after a body that turned in 0.15 s).
@export_range(1.0, 8.0, 0.1) var transition_pace := 4.0
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

@export_group("Jump")
## Picks the jump's clips by the body's own numbers (`JumpAnimation`, gdstudio #1371): the
## take-off by speed and the run's foot, the air by vertical speed, the landing by fall speed and
## the run asked for. Off: `CharacterAnimation`'s `jump_clip`, `air_clip` and `land_clip` alone.
@export var jump_choices := true
## The take-offs from a run, from its left and its right foot strike: the one whose first frame
## is nearest the gait's phase plays. Empty or missing: the standing take-off.
@export var run_takeoff_left: StringName = CharacterClips.JUMP_START_RUN_L
@export var run_takeoff_right: StringName = CharacterClips.JUMP_START_RUN_R
## The ground speed from which a jump takes off running (between the walk and the jog).
@export_range(0.0, 12.0, 0.05, "suffix:m/s") var run_takeoff_speed := 2.5
## The rise and the top of the jump, blended with the fall (`CharacterAnimation.air_clip`) by the
## body's vertical speed. Either missing: the fall alone.
@export var rise_clip: StringName = CharacterClips.JUMP_RISE
@export var apex_clip: StringName = CharacterClips.JUMP_APEX
## The vertical speeds at which the rise plays alone (up) and the fall (down); the top is at 0.
@export_range(0.5, 20.0, 0.1, "suffix:m/s") var air_rise_speed := 3.0
@export_range(0.5, 20.0, 0.1, "suffix:m/s") var air_fall_speed := 4.0
## The landing from a long fall, from its record's `fall_speed.from` (`hard_land_speed` for a clip
## with no record). Missing: `CharacterAnimation.land_clip`.
@export var hard_land_clip: StringName = CharacterClips.LAND_HARD
@export_range(0.0, 40.0, 0.1, "suffix:m/s") var hard_land_speed := 9.0
## The landing into a run, played when the body lands asked to go at `run_land_speed` or more,
## inside its record's fall speeds; it hands over to the gait at the phase it ends on.
@export var run_land_clip: StringName = CharacterClips.LAND_TO_JOG
@export_range(0.0, 12.0, 0.05, "suffix:m/s") var run_land_speed := 2.5

@export_group("Stance changes")
## Draws a crouch and a stand at rest with their own clips, carried over the body (no cross-fade:
## the momentum blend takes the drawn pose in and out), and goes on from getting up (which ends
## crouched) into the stand's clip (`StanceAnimation`, gdstudio #1576). A moving body, and any move,
## jump or slide asked for during the clip, changes stance by the momentum blend alone. Off, every
## crouch and stand is the momentum blend (the template before #1576).
@export var stance_clips := true
## The clip a body at rest crouches with: from the idle's first pose to the crouch idle's.
@export var stand_to_crouch_clip: StringName = CharacterClips.STAND_TO_CROUCH
## The clip a body at rest stands up with: from the crouch idle's first pose to the idle's.
@export var crouch_to_stand_clip: StringName = CharacterClips.CROUCH_TO_STAND
## How long the crouch's clip is drawn (its own pace: 0.67 s, its drop at 0.54 of gravity; at
## 0.5 s it drops at 0.96, and shorter asks more than a fall). The capsule is down in the tuning's
## `crouch_time` (0.2 s) whatever this is: only the look takes longer.
@export_range(0.1, 2.0, 0.01, "suffix:s") var stand_to_crouch_time := 0.5
## How long the stand's clip is drawn (its own pace: 0.53 s, its rise stopping at 0.94 of gravity;
## shorter throws the body up past standing).
@export_range(0.1, 2.0, 0.01, "suffix:s") var crouch_to_stand_time := 0.53

@export_group("Helper bones")
## Blends the clips' tracks of the rig's helper bones (the `ik_` foot and hand targets), which
## nothing drawn follows. Off: they are switched off in the game (`HelperTracks`), the same pose
## for 4 to 5 fewer microseconds of the tree a character a frame; turn it on for a modifier that
## reads the targets. The clips are shared: give every character the same choice.
@export var helper_tracks := false
