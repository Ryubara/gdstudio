@tool
class_name AimLimits
extends Resource
## How far the aim layer may turn a character's upper body in one move (standing, crouched,
## sliding, lying), so its weapon points at the aim: the `AimLayer` swings the spine left, right,
## up and down off the move's own pose by at most these angles. Each move's tuning holds one
## (`CharacterTuning.aim_limits` and `crouch_aim_limits`, `SlideTuning.aim_limits`,
## `ProneTuning.aim_limits`); `Character.aim_limits` is the one of the move it is in now.
##
## The body reads `yaw_left` and `yaw_right` too: a slide keeps the body along the slide while the
## aim stays within them, and past them the body turns or the shot is refused, as the held
## weapon's `WeaponDef.past_aim_limit` says. The angles are the aim's, off the way the body faces:
## left and right as the character sees them.

## How far past a limit a shot is still allowed, radians: the body's facing eases toward the way it
## should face, so an aim at the very edge is not refused on one tick and allowed on the next.
const REACH_MARGIN := 0.035

## On: the aim layer points the weapon at the aim in this move. Off: the move's own pose holds
## the weapon (the aim clips alone).
@export var enabled := true:
	set(value):
		enabled = value
		emit_changed()
## The most the upper body turns to the character's left of the way the body faces.
@export_range(0.0, 120.0, 0.5, "suffix:deg") var yaw_left := 70.0:
	set(value):
		yaw_left = value
		emit_changed()
## The most the upper body turns to the character's right of the way the body faces.
@export_range(0.0, 120.0, 0.5, "suffix:deg") var yaw_right := 70.0:
	set(value):
		yaw_right = value
		emit_changed()
## The most the upper body bends up off the move's pose to raise the weapon.
@export_range(0.0, 90.0, 0.5, "suffix:deg") var pitch_up := 45.0:
	set(value):
		pitch_up = value
		emit_changed()
## The most the upper body bends down off the move's pose to lower the weapon.
@export_range(0.0, 90.0, 0.5, "suffix:deg") var pitch_down := 45.0:
	set(value):
		pitch_down = value
		emit_changed()


## `yaw` (radians, positive to the character's left) held within `yaw_left` and `yaw_right`.
func clamp_yaw(yaw: float) -> float:
	return clampf(yaw, -deg_to_rad(yaw_right), deg_to_rad(yaw_left))


## `pitch` (radians, positive up) held within `pitch_up` and `pitch_down`.
func clamp_pitch(pitch: float) -> float:
	return clampf(pitch, -deg_to_rad(pitch_down), deg_to_rad(pitch_up))


## True when an aim `yaw` radians off the body's facing (positive to its left) is within reach,
## with `margin` radians to spare on either side.
func reaches_yaw(yaw: float, margin: float = 0.0) -> bool:
	return yaw <= deg_to_rad(yaw_left) + margin and yaw >= -deg_to_rad(yaw_right) - margin
