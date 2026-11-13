class_name ShoulderSwapAim
extends RefCounted
## The geometry and the choice behind `PlayerCamera`'s aim-point keeping on a shoulder swap:
## which point under the crosshair is worth keeping (`keeps()`) and the view that puts a point on
## the crosshair (`view_through()`). Static and pure, so tests read them without a scene.


## A swap keeps the point under the crosshair only when the crosshair's ray stopped on a body on
## one of `layers` (`PlayerCamera.keep_aim_layers`: by default a character's capsule or a limp
## body's bones). A wall, the floor, a prop or the empty sky (`collider` null) keep nothing: the
## view slides to the other shoulder without turning.
static func keeps(collider: Object, layers: int) -> bool:
	var body := collider as CollisionObject3D
	return body != null and (body.collision_layer & layers) != 0


## The yaw and pitch (radians, the rig's senses: pitch positive looks down) that put `point` on
## the crosshair of a camera turning about `pivot` with the view shifted `side` to the right and
## `height` up (the Camera node's H and V Offset): the crosshair's ray is the view's axis moved by
## the offsets, so `point` must sit `side` to the right of the axis and `height` above it.
static func view_through(point: Vector3, pivot: Vector3, side: float, height: float) -> Vector2:
	var to := point - pivot
	var flat := Vector2(to.x, to.z).length()
	var across := asin(clampf(side / maxf(flat, 0.001), -0.95, 0.95))
	var ahead := flat * cos(across)
	var reach := Vector2(ahead, to.y).length()
	var lift := asin(clampf(height / maxf(reach, 0.001), -0.95, 0.95))
	return Vector2(atan2(-to.x, -to.z) + across, lift - atan2(to.y, ahead))
