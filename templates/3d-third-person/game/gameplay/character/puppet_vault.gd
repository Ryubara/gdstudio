class_name PuppetVault
extends RefCounted
## The vault and the mantle of a body drawn from the network (another player's puppet, an AI
## replica), worked out on this screen. A puppet never steps, so its `CharacterVault` never plans
## and its clip never started: the state came over the wire, the plan did not. When the state a
## puppet is drawn in turns to `VAULT` or `MANTLE`, the same `VaultProbe` the stepping body ran is
## run here, from where the puppet was drawn the frame before set down on the floor (where the
## stepping body stood when it planned, to within a tick of its run), along the heading the server
## sent (the stepping body turns square to the face as it starts) and at the speed it was drawn
## moving before. The plan goes into the puppet's `vault_motion` and its `started` is said, so
## `CharacterAnimation` plays the clip and holds the model as it does on the stepping body. The
## plan's time runs on with the frames drawn, and the crossing ends when the drawn state leaves it.
##
## Nothing is sent: the plan is the map's and the body's own (the template's networking rule,
## `net-world.md#network-ready-component`, item 6). A probe that finds no crossing of the kind the
## server said (the map differs here, something stands in the way on this screen) plays no clip:
## the puppet shows the capsule's path in its gait, as before.

## The meta a puppet keeps its `PuppetVault` under.
const META := &"puppet_vault"
## Metres below the point drawn the frame before the turn a floor is looked for: that frame is
## drawn between the last snapshot on the ground and the first one of the crossing, already a
## little way up the path (0.22 m on the course's 0.9 m wall at a run).
const FLOOR_REACH := 0.5

## Probes run for this puppet, and how many found a crossing of the server's kind (a test or a
## debug overlay reads them).
var probes := 0
var found := 0

var _crossing := false
var _seen := false
var _last_point := Vector3.ZERO
var _last_speed := 0.0
var _speed_before := 0.0


## The `PuppetVault` of `puppet` (made the first time).
static func of(puppet: Character) -> PuppetVault:
	if puppet.has_meta(META):
		return puppet.get_meta(META) as PuppetVault
	var made := PuppetVault.new()
	puppet.set_meta(META, made)
	return made


## Follows `puppet`'s drawn state for a frame of `delta` seconds, after its place, heading,
## velocity and `state` for the frame are set. `mask` is what the probe meets (the map's layers:
## a puppet itself may meet nothing).
static func follow(puppet: Character, delta: float, mask: int) -> void:
	of(puppet)._follow(puppet, delta, mask)


## True while the state a puppet is drawn in is a crossing.
static func is_crossing(state: int) -> bool:
	return state == Character.State.VAULT or state == Character.State.MANTLE


func _follow(puppet: Character, delta: float, mask: int) -> void:
	var motion := puppet.vault_motion
	var crossing := is_crossing(puppet.state)
	if not crossing:
		if _crossing or motion.plan.is_valid():
			motion.cancel()
		_crossing = false
		_seen = true
		_last_point = puppet.global_position
		_speed_before = _last_speed
		_last_speed = Vector2(puppet.velocity.x, puppet.velocity.z).length()
		return
	if _crossing:
		if motion.is_active():
			motion.elapsed = minf(motion.elapsed + delta, motion.plan.duration)
		return
	_crossing = true
	_start(puppet, delta, mask)


# The drawn state just turned to a crossing: plan it as the stepping body did and say it began.
func _start(puppet: Character, delta: float, mask: int) -> void:
	var settings := puppet.vault_settings
	if settings == null or puppet.tuning == null:
		return
	probes += 1
	var heading := Vector3.BACK.rotated(Vector3.UP, puppet.facing)
	var speed := maxf(_speed_before, _last_speed)
	var feet := _on_floor(puppet, _last_point, mask) if _seen else puppet.global_position
	var plan := _probe(puppet, feet, heading, speed, mask)
	var wanted := (
		VaultPlan.Kind.VAULT if puppet.state == Character.State.VAULT else VaultPlan.Kind.MANTLE
	)
	if plan.kind != wanted and _seen:
		# From the place it was drawn at now, a tick or two into the crossing.
		plan = _probe(puppet, puppet.global_position, heading, speed, mask)
	if plan.kind != wanted:
		return
	found += 1
	var motion := puppet.vault_motion
	motion.plan = plan
	# The frame before the turn is where the plan starts: this frame is one frame in.
	motion.elapsed = minf(delta if _seen else 0.0, plan.duration)
	motion.started.emit(plan)


func _probe(
	puppet: Character, feet: Vector3, heading: Vector3, speed: float, mask: int
) -> VaultPlan:
	var kept := puppet.collision_mask
	puppet.collision_mask = mask
	var tuning := puppet.tuning
	var plan := VaultProbe.measure(
		puppet, feet, heading, tuning.radius, tuning.height, speed, puppet.vault_settings
	)
	puppet.collision_mask = kept
	return plan


# `point` set down on the floor under it (the crossing starts from the ground), or `point` when no
# floor is within `FLOOR_REACH`.
func _on_floor(puppet: Character, point: Vector3, mask: int) -> Vector3:
	var space := puppet.get_world_3d().direct_space_state
	var from := point + Vector3.UP * 0.05
	var query := PhysicsRayQueryParameters3D.create(from, point + Vector3.DOWN * FLOOR_REACH, mask)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return point
	return Vector3(point.x, (hit["position"] as Vector3).y, point.z)
