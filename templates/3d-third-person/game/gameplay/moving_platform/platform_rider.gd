class_name PlatformRider
extends RefCounted
## Carries a character that stands on a `MovingPlatform` an online world drives. Offline the
## platform is a kinematic body and the engine gives its riders its velocity; online it is a static
## body put at each command's tick (`NetWorld.place`), which gives a rider nothing, so the rider is
## moved by what the platform moved between the tick of its last step and the tick of this one,
## from the platform's own function (`MovingPlatform.position_at`). The server's body and the
## predicting client's body step the same commands at the same ticks, so both are carried alike.
##
## `Character` calls `carry` before its move and `land` after it.

## The platform under the body after its last step, or null.
var platform: MovingPlatform
## The tick that platform was at then.
var tick := 0

var _hit := KinematicCollision3D.new()


## Moves `body` by what its platform moved since the last step.
func carry(body: CharacterBody3D) -> void:
	if platform == null:
		return
	if not is_instance_valid(platform) or not platform.is_online():
		platform = null
		return
	var moved := platform.position_at(platform.placed_tick) - platform.position_at(tick)
	tick = platform.placed_tick
	body.global_position += moved


## Notes the online platform `body` stands on after its move (none: not carried next step).
func land(body: CharacterBody3D) -> void:
	platform = null
	if MovingPlatform.online_count == 0 or not body.is_on_floor():
		return
	var found := _floor_platform(body)
	if found != null and found.is_online():
		platform = found
		tick = found.placed_tick


# The platform among the move's contacts, or under the body's feet (a body that stands still on
# the floor touches it by the snap only, which records no contact).
func _floor_platform(body: CharacterBody3D) -> MovingPlatform:
	for index in body.get_slide_collision_count():
		var contact := body.get_slide_collision(index)
		var below := contact.get_normal().dot(body.up_direction) > 0.5
		if below and contact.get_collider() is MovingPlatform:
			return contact.get_collider() as MovingPlatform
	if body.test_move(body.global_transform, -body.up_direction * 0.1, _hit):
		return _hit.get_collider() as MovingPlatform
	return null
