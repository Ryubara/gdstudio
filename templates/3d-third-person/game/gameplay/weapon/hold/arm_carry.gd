class_name ArmCarry
extends Resource
## How a weapon carried in one hand rides the stride (gdstudio #1577): the numbers of
## `ArmCarrySteady`, the modifier that keeps the carrying arm on one readable carry while the
## locomotion clips, the transition clips and the gait blend swing it. Each arm bone follows its
## clip's own average (`follow_half_life`) and takes only `stride_share` of the clip's swing about
## that average, softly held under `limit`; the other arm keeps more of its swing. Tuned live in
## the inspector (the template's `pistol_arm_carry.tres`); cosmetic, never sent.

## Seconds in which the carry's place halves its way toward the clip's: it follows a gait's own
## carry (a walk's hanging arm, a jog's bent one) and lets a stride's swing, a turn's flail or the
## gait blend's dip pass by.
@export_range(0.05, 2.0, 0.01, "suffix:s") var follow_half_life := 0.3
## Seconds in which the swing drawn halves its way toward the share of the clip's it keeps: a
## swing that turns about in a tick or two (the gait blend's dip on a turn, a cut clip) is drawn
## over a few, while a stride's swing keeps its timing within a few hundredths of a second.
@export_range(0.0, 0.5, 0.005, "suffix:s") var swing_half_life := 0.06
## The share of the clip's swing about the carry the carrying arm keeps (1: the clip's own arm).
@export_range(0.0, 1.0, 0.01) var stride_share := 0.35
## The most the carrying arm's bones swing off the carry, in degrees, eased (`tanh`) toward it.
@export_range(1.0, 180.0, 1.0, "suffix:deg") var limit := 30.0
## The same for the other arm, which swings freer.
@export_range(0.0, 1.0, 0.01) var free_share := 0.7
@export_range(1.0, 180.0, 1.0, "suffix:deg") var free_limit := 50.0
## The carrying arm's bones and the other arm's, from the shoulder down (the hand keeps the grip).
@export var carry_bones: Array[StringName] = [&"clavicle_r", &"upperarm_r", &"lowerarm_r"]
@export var free_bones: Array[StringName] = [&"clavicle_l", &"upperarm_l", &"lowerarm_l"]
