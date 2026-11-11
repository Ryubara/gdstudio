# How the ragdoll moves in the real physics world: it falls and comes to rest, a run's momentum
# carries into it, its knees and elbows stay in range, and deaths in every pose never throw a
# bone. Dying, getting up and the key are in test_ragdoll.gd, what makes it look like a body in
# test_ragdoll_natural.gd.
extends GdUnitTestSuite

## The fastest a bone may move after a death, in m/s. Each bone leaves with the speed the animation
## gave it (a foot of a sprinting body is at 12 to 16), a body the engine throws is at 230 to 500.
const MOST_SPEED := 20.0
## A joint's limit is a soft stop against a load (`ragdoll.md#limits`). Degrees.
const LIMIT_SLACK := 25.0

var _arena: PlayArena
var _player: Player
var _ragdoll: CharacterRagdoll


func before_test() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3(0.0, 0.0, 0.0))
	_player.tuning = (
		(load("res://gameplay/player/player_tuning.tres") as CharacterTuning).duplicate()
	)
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
	# Not carried, the body falls where it stood (a run's carried slide is over 1 m): it topples a
	# little, the run's lean and the limbs' spin included.
	assert_float(slid.length()).is_less(0.9)


func test_knees_and_elbows_stay_in_their_limits_and_never_bend_backward() -> void:
	# Off aim the arms swing with the jog (#877), so a jogging death starts with the elbows in the
	# clip's pose; the hinges hold them in range (#872).
	InputSim.key(KEY_W, true)
	await _ticks(30)
	_player.die()
	for _step in 8:
		await _ticks(30)
		for entry: Dictionary in CharacterRagdoll.BODIES:
			if entry.joint != &"hinge":
				continue
			var angles := _hinge_angles(entry)
			var bend_range: Vector2 = entry.range
			(
				assert_float(angles.x)
				. override_failure_message(
					"%s bent %.1f, range %s" % [entry.bone, angles.x, bend_range]
				)
				. is_between(bend_range.x - LIMIT_SLACK, bend_range.y + LIMIT_SLACK)
			)
			# A knee or an elbow never goes past straight.
			assert_float(angles.x).is_greater(bend_range.x - 8.0)


# The angles of a hinge joint from the straight limb, in degrees: x the bend (about the hinge),
# y the sideways lean and z the roll about the bone.
func _hinge_angles(entry: Dictionary) -> Vector3:
	var skeleton := _player.model.skeleton()
	var parent: StringName = _ragdoll._parent_body(skeleton, entry.bone)
	var rest := _ragdoll.rest_body(parent).basis.inverse() * _ragdoll.rest_body(entry.bone).basis
	var now := _ragdoll.body(parent).global_basis.inverse() * _ragdoll.body(entry.bone).global_basis
	var frame := CharacterRagdoll.hinge_frame(entry.axis)
	var q := Quaternion(frame.inverse() * rest.inverse() * now * frame).normalized()
	if q.w < 0.0:
		q = -q
	return Vector3(
		rad_to_deg(2.0 * atan2(q.z, q.w)),
		rad_to_deg(2.0 * asin(clampf(q.y, -1.0, 1.0))),
		rad_to_deg(2.0 * asin(clampf(q.x, -1.0, 1.0)))
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
			for entry: Dictionary in CharacterRagdoll.BODIES:
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
		. is_less(MOST_SPEED)
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
