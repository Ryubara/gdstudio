# The rest of the aim layer and the weapon hold (gdstudio #1478): while nothing is aimed, reloaded,
# racked or used, `AimLayer.refresh()` writes nothing and `WeaponHold.refresh()` places only the
# grip and the slide (`HoldRest`), because every other modifier of theirs stays off. These hold
# that the shortcut changes nothing drawn: two players side by side are stepped through the same
# commands (a walk, aiming in and out with a shot, an empty reload and its rack, a hand let go for
# an action, the fists aimed crouched), one of them with the shortcuts off, and every bone is the
# same in every drawn frame, read inside the skeleton's update; and that the shortcut is taken.
extends GdUnitTestSuite

const TUNING := preload("res://gameplay/player/player_tuning.tres")
## How far apart two drawn bones may be: a place (m) and a turn (radians). Two bodies side by side
## differ by single precision alone (`test_helper_tracks.gd` reads the same).
const PLACE := 1e-5
const TURN := 1e-5
## The script, in ticks: aim from `AIM_IN` to `AIM_OUT` (a shot at `SHOT`), an empty reload at
## `RELOAD` (its rack follows), the left hand let go at `FREE`, the fists from `FISTS`, aimed
## crouched from `FISTS_AIM_IN` to `FISTS_AIM_OUT`, and the end at `TICKS`.
const AIM_IN := 30
const SHOT := 70
const AIM_OUT := 90
const RELOAD := 120
const FREE := 300
const FISTS := 340
const FISTS_AIM_IN := 360
const FISTS_AIM_OUT := 400
const TICKS := 440
## How long the left hand is let go for, in seconds.
const FREE_SECONDS := 0.5

var _arena: PlayArena


func before_test() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)


func after_test() -> void:
	AudioDrain.stop_all(_arena)


func _player(spot: Vector3) -> Player:
	var body := _arena.add_player(spot)
	body.tuning = (TUNING as CharacterTuning).duplicate()
	CommandDriver.take(body)
	return body


static func _layer(body: Node) -> AimLayer:
	return body.find_children("*", "AimLayer", true, false)[0] as AimLayer


static func _skeleton(body: Node) -> Skeleton3D:
	return body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D


# The command of tick `tick`: a walk that turns, with the aim, the shot, the reload, the switch to
# the fists and the crouch on their ticks.
static func _command(tick: int) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.move = Vector2(0.0, 1.0) if tick < FISTS_AIM_OUT else Vector2.ZERO
	command.walk = tick >= AIM_IN
	command.yaw = 0.02 * tick
	command.pitch = 0.2 * sin(tick * 0.05)
	command.aim = (
		(tick >= AIM_IN and tick < AIM_OUT) or (tick >= FISTS_AIM_IN and tick < FISTS_AIM_OUT)
	)
	command.fire = tick == SHOT
	command.fire_pressed = tick == SHOT
	command.reload_pressed = tick == RELOAD
	command.unarmed_pressed = tick == FISTS
	command.crouch = tick >= FISTS_AIM_IN
	return command


# The turn between two bones (radians), read through atan2 (`test_helper_tracks.gd`).
static func _turn(a: Basis, b: Basis) -> float:
	var d := a.get_rotation_quaternion().inverse() * b.get_rotation_quaternion()
	return 2.0 * atan2(Vector3(d.x, d.y, d.z).length(), absf(d.w))


func test_the_rest_draws_the_same_pose() -> void:
	var resting := _player(Vector3(-3.0, 0.0, 0.0))
	var full := _player(Vector3(3.0, 0.0, 0.0))
	_layer(full).full_refresh = true
	(full.get_node("WeaponHold") as WeaponHold).rest.off = true
	var bodies: Array[Player] = [resting, full]
	var drawn: Array[Array] = [[], []]
	for index in bodies.size():
		var skeleton := _skeleton(bodies[index])
		var into: Array = drawn[index]
		skeleton.skeleton_updated.connect(
			func() -> void:
				var frame: Array[Transform3D] = []
				for bone in skeleton.get_bone_count():
					frame.append(skeleton.get_bone_global_pose(bone))
				into.append(frame)
		)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hold := resting.get_node("WeaponHold") as WeaponHold
	var layer := _layer(resting)
	var step := CommandDriver.tick_seconds()
	var seen := {"aimed": 0, "reloaded": 0, "racked": 0, "freed": 0, "fists": 0, "layer_rest": 0}
	for tick in TICKS:
		await get_tree().physics_frame
		if tick == RELOAD:
			for body in bodies:
				body.weapon.set_ammo(0, 24)
		if tick == FREE:
			for body in bodies:
				(body.get_node("WeaponHold") as WeaponHold).free_hand(FREE_SECONDS)
		var command := _command(tick)
		for body in bodies:
			body.step(command.clone(), step)
		var animation := resting.get_node("Animation") as CharacterAnimation
		seen.aimed += int(hold.aim_weight > 0.0)
		seen.reloaded += int(hold.reload_weight > 0.0)
		seen.racked += int(animation.rack.progress().x > 0.0)
		seen.freed += int(hold.free_weight > 0.0)
		seen.fists += int(layer.upright_modifier().active)
		seen.layer_rest += int(layer.is_at_rest())
	print("seen %s, the hold rested %d times" % [seen, hold.rest.rested])
	# Every part of the script played, and both shortcuts were taken.
	for key: String in seen:
		assert_int(seen[key]).override_failure_message("%s: %d" % [key, seen[key]]).is_greater(3)
	assert_int(hold.rest.rested).is_greater(TICKS / 4)
	assert_int((full.get_node("WeaponHold") as WeaponHold).rest.rested).is_equal(0)
	assert_bool(_layer(full).is_at_rest()).is_false()
	var frames: int = drawn[0].size()
	assert_int(drawn[1].size()).is_equal(frames)
	assert_int(frames).is_greater(TICKS / 2)
	var rig := _skeleton(resting)
	var place := 0.0
	var turn := 0.0
	var worst := ""
	for frame in frames:
		for bone in rig.get_bone_count():
			var a: Transform3D = drawn[0][frame][bone]
			var b: Transform3D = drawn[1][frame][bone]
			var moved := a.origin.distance_to(b.origin)
			var turned := _turn(a.basis, b.basis)
			if moved > place or turned > turn:
				worst = "%s in frame %d" % [rig.get_bone_name(bone), frame]
			place = maxf(place, moved)
			turn = maxf(turn, turned)
	var message := (
		"%d frames, %.6f mm, %.6f degrees apart (%s)"
		% [frames, place * 1000.0, rad_to_deg(turn), worst]
	)
	print(message)
	assert_float(place).override_failure_message(message).is_less(PLACE)
	assert_float(turn).override_failure_message(message).is_less(TURN)
