class_name CharacterProne
extends RefCounted
## The prone stance of a `Character`, kept apart from the body's other moves: whether it lies
## down, how far down it is, and what lying changes (the crawl's speed, acceleration and turn,
## the capsule, the aim). The body asks it once a step from the command's `prone` bit
## (`step()`), so it is deterministic from the command and the state, and a server, a bot or a
## test lies a body down by sending that bit. Its numbers are a `ProneTuning`.
##
## Getting up goes through crouch: lying ends at the crouch height, and only when a crouched
## capsule fits above the body; under a gap only a lying body fits, it stays down. The body
## stays crouched while it lies, so letting go of prone stands up over the crouch time when
## there is room, or stays crouched under a low ceiling.

## Lying down or going down (true), or up or getting up (false).
var down := false
## How far down the body is: 0 standing (or crouched), 1 lying.
var amount := 0.0

# Seconds the body has been off the ground.
var _air := 0.0
var _probe := CapsuleShape3D.new()


## Moves the stance one tick: down while `wants` and on the ground (a body already down stays
## down `air_time` off a ledge), and up when it is let go of and a crouched capsule fits
## above. True when `down` changed.
func step(body: Character, wants: bool, grounded: bool, delta: float) -> bool:
	var tuning := body.prone_tuning
	_air = 0.0 if grounded else _air + delta
	var should := wants and (grounded or (down and _air < tuning.air_time))
	# Under a gap only a lying body fits, it stays down.
	if down and not should and not has_room(body, CharacterCapsule.crouch_height(body)):
		should = true
	var changed := should != down
	down = should
	var time := tuning.enter_time if down else tuning.exit_time
	amount = move_toward(amount, 1.0 if down else 0.0, delta / maxf(time, 0.001))
	return changed


## Lying, going down or getting up: the body is not standing or crouched yet.
func is_prone() -> bool:
	return down or amount > 0.0


## Going down or getting up (not all the way either way).
func is_changing() -> bool:
	return amount > 0.0 and amount < 1.0


## How far down the body is, eased (0 up, 1 lying): what the capsule and the camera follow.
func share() -> float:
	return smoothstep(0.0, 1.0, amount)


## Lets go at once: up, nothing left of the stance (death, a teleport).
func reset() -> void:
	down = false
	amount = 0.0
	_air = 0.0


## The crawl's speed for a push of `strength` (0 to 1, already raised to the least share of a
## light push) along `wish`, for a body facing `facing` (radians, 0 faces +Z): full ahead,
## `sideways_share` to the side, `backward_share` behind, `aim_move_share` of it while aiming,
## and nothing while changing stance unless `move_while_changing`.
func crawl_speed(
	tuning: ProneTuning, strength: float, wish: Vector3, facing: float, aiming: bool
) -> float:
	if is_changing() and not tuning.move_while_changing:
		return 0.0
	var along := 1.0
	if wish.length_squared() > 0.000001:
		along = wish.normalized().dot(Vector3(sin(facing), 0.0, cos(facing)))
	var share_of_speed := (
		lerpf(tuning.sideways_share, 1.0, along)
		if along >= 0.0
		else lerpf(tuning.sideways_share, tuning.backward_share, -along)
	)
	var speed := tuning.crawl_speed * strength * share_of_speed
	if aiming:
		speed *= tuning.aim_move_share
	return speed


## The view's pitch held to the prone look limits, by how far down the body is.
func held_pitch(tuning: ProneTuning, pitch: float) -> float:
	var t := share()
	if t <= 0.0:
		return pitch
	var lowest := lerpf(-PI / 2.0, -deg_to_rad(tuning.look_down_limit), t)
	var highest := lerpf(PI / 2.0, deg_to_rad(tuning.look_up_limit), t)
	return clampf(pitch, lowest, highest)


## True when a capsule `height` tall (the crouched one) fits above `body`: geometry, a probe a
## little thinner and shorter than that capsule, lifted off the floor, as the stand check does.
func has_room(body: Character, height: float) -> bool:
	_probe.radius = maxf(body.tuning.radius - 0.02, 0.05)
	_probe.height = maxf(height - 0.12, _probe.radius * 2.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _probe
	var middle := body.global_position + Vector3.UP * (height / 2.0 + 0.06)
	query.transform = Transform3D(Basis.IDENTITY, middle)
	query.collision_mask = body.collision_mask
	query.exclude = [body.get_rid()]
	return body.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## The stance in `kept` (`CharacterState.prone`).
func save_step_state(kept: Array) -> void:
	kept.resize(3)
	kept[0] = down
	kept[1] = amount
	kept[2] = _air


## Puts back what `save_step_state` wrote; an empty array is a body that is up.
func load_step_state(kept: Array) -> void:
	if kept.size() < 3:
		reset()
		return
	down = kept[0]
	amount = kept[1]
	_air = kept[2]
