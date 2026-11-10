# How the ragdoll moves in the real physics world: it falls and comes to rest, a run's momentum
# carries into it, its knees and elbows stay inside their limits, and deaths in every pose never
# throw a bone. Dying, getting up and the key are in test_ragdoll.gd.
extends GdUnitTestSuite

## A joint's limit is a soft stop against a load: an arm pinned under the body's weight rests up
## to about 17 degrees past its limit (seen on both elbows, run after run). Degrees.
const LIMIT_SLACK := 25.0

var _arena: PlayArena
var _player: Player
var _ragdoll: PlayerRagdoll


func before_test() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3(0.0, 0.0, 0.0))
	_player.tuning = (load("res://gameplay/player/player_tuning.tres") as PlayerTuning).duplicate()
	_ragdoll = _player.ragdoll_body
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()


func _ticks(count: int) -> void:
	await InputSim.ticks(get_tree(), count)


func test_the_ragdoll_falls_and_comes_to_rest_on_the_floor() -> void:
	var start := _ragdoll.hips()
	_player.die()
	await _ticks(240)
	var hips := _ragdoll.hips()
	assert_float(start.y).is_greater(0.8)
	assert_float(hips.y).is_between(0.05, 0.35)
	var pelvis := _ragdoll.body(&"pelvis")
	assert_float(pelvis.linear_velocity.length()).is_less(0.2)
	# Every bone is above the floor (the floor's top is at y = 0).
	for bone in [&"Head", &"hand_l", &"hand_r", &"foot_l", &"foot_r"]:
		assert_float(_ragdoll.body(bone).global_position.y).is_greater(-0.02)


func test_a_run_carries_its_momentum_into_the_ragdoll() -> void:
	InputSim.key(KEY_W, true)
	await _ticks(45)
	var speed := _player.ground_speed()
	var heading := Vector3(_player.velocity.x, 0.0, _player.velocity.z).normalized()
	var start := _ragdoll.hips()
	_player.die()
	await _ticks(90)
	var slid := _ragdoll.hips() - start
	slid.y = 0.0
	assert_float(speed).is_greater(3.5)
	assert_float(slid.length()).is_greater(1.0)
	assert_float(slid.normalized().dot(heading)).is_greater(0.8)


func test_without_carry_the_body_drops_on_the_spot() -> void:
	_ragdoll.carry_velocity = 0.0
	InputSim.key(KEY_W, true)
	await _ticks(45)
	var start := _ragdoll.hips()
	_player.die()
	await _ticks(90)
	var slid := _ragdoll.hips() - start
	slid.y = 0.0
	assert_float(slid.length()).is_less(0.6)


func test_knees_and_elbows_stay_in_their_limits_and_never_bend_backward() -> void:
	# The pistol used to hold both arms out whatever the clip, so a death on the run started with
	# the arms in one pose. Off aim the arms now swing with the jog, and the left elbow of a
	# jogging death leaves its limits (an unarmed character did the same before): the ragdoll's
	# limits are #872's, so this test keeps the old carry until they are reworked there.
	(_player.get_node("Animation") as PlayerAnimation).carry = PlayerAnimation.Carry.HELD_POSE
	InputSim.key(KEY_W, true)
	await _ticks(30)
	_player.die()
	for _step in 8:
		await _ticks(30)
		for entry: Dictionary in PlayerRagdoll.BODIES:
			if entry.joint != &"bend":
				continue
			var angles := _bend_angles(entry)
			var limits := Vector3(
				(entry.bend.y - entry.bend.x) / 2.0,
				(entry.twist.y - entry.twist.x) / 2.0,
				(entry.side_swing.y - entry.side_swing.x) / 2.0
			)
			for axis in 3:
				(
					assert_float(absf(angles[axis]))
					. override_failure_message(
						(
							"%s axis %d at %.1f, limit %.1f"
							% [entry.bone, axis, angles[axis], limits[axis]]
						)
					)
					. is_less(limits[axis] + LIMIT_SLACK)
				)
			# From the middle of its bend, a knee or an elbow never goes past straight.
			assert_float(angles.x + (entry.bend.x + entry.bend.y) / 2.0).is_greater(
				entry.bend.x - 8.0
			)


# Thirty deaths in every pose the player can be in (standing, running, sprinting, crouching,
# aiming), at random moments of the animation, half on each mannequin: no bone ever flies off. A
# joint that starts outside its limits can throw the whole body (the tool in tools/ragdoll
# measures the limits so none does), and the animation tree's clock is real time, so one death
# proves little. It runs on the physics clock (about 50 s): the bodies are the engine's own, so
# nothing here can be stepped by hand.
func test_deaths_in_every_pose_never_throw_a_bone() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 846
	var poses: Array[Dictionary] = [
		{keys = [], aim = false},
		{keys = [KEY_W], aim = false},
		{keys = [KEY_W, KEY_SHIFT], aim = false},
		{keys = [KEY_C], aim = false},
		{keys = [KEY_C, KEY_A], aim = false},
		{keys = [KEY_W], aim = true},
		{keys = [], aim = true},
	]
	var fastest := 0.0
	var worst := ""
	for death in 30:
		if death == 15:
			await _swap_to_male()
		var pose := poses[death % poses.size()]
		for key: Key in pose.keys:
			InputSim.key(key, true)
		if pose.aim:
			InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
		await _ticks(random.randi_range(5, 60))
		_player.die()
		for _tick in 60:
			await _ticks(1)
			for entry: Dictionary in PlayerRagdoll.BODIES:
				var speed := _ragdoll.body(entry.bone).linear_velocity.length()
				if speed > fastest:
					fastest = speed
					worst = "death %d (%s) bone %s" % [death, pose.keys, entry.bone]
		InputSim.release_all()
		# Back to the middle of the floor: a run would else carry the next death off its edge.
		_player.teleport(Vector3.ZERO)
		await _ticks(6)
	(
		assert_float(fastest)
		. override_failure_message("a bone flew at %.1f m/s in %s" % [fastest, worst])
		. is_less(12.0)
	)


func _swap_to_male() -> void:
	var slot := _player.model
	var old := slot.rig()
	slot.remove_child(old)
	old.free()
	var male := (
		(load("res://assets/characters/mannequin/mannequin_male.glb") as PackedScene).instantiate()
	)
	slot.add_child(male)
	await _ticks(3)


# A knee's or an elbow's angles about its bend, roll and side axes, in degrees, from the middle of
# its ranges, as its joint reads them (`PlayerRagdoll.swing_twist` in the joint's frame).
func _bend_angles(entry: Dictionary) -> Vector3:
	var skeleton := _player.model.skeleton()
	var parent: StringName = _ragdoll._parent_body(skeleton, entry.bone)
	var rest := _ragdoll.rest_body(parent).basis.inverse() * _ragdoll.rest_body(entry.bone).basis
	var now := _ragdoll.body(parent).global_basis.inverse() * _ragdoll.body(entry.bone).global_basis
	var centre: Basis = _ragdoll._centre(entry)
	var frame: Basis = _ragdoll._joint_frame(entry)
	return PlayerRagdoll.swing_twist(
		frame.inverse() * centre.inverse() * rest.inverse() * now * frame
	)
