class_name HandPoseWay
extends Resource
## The poses a hand's bones pass through between two `HandPose`s, in order (kit #1036): the
## rifle's trigger finger goes round the trigger guard from along the receiver to the trigger,
## where the straight way between the two poses goes through the guard and the magazine well.
## `HandPoseModifier.second_way` takes the list. Written by `tools/hold/solve_trigger_way.gd` from
## the skinned finger against the rifle's triangles, so no number of it is typed.

## The poses, from the first to the last; each names the bones the two ends' second pose names.
@export var poses: Array[HandPose] = []
