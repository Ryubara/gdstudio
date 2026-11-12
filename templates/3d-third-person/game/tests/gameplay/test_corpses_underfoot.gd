# The player among the dead (kit #1339): the capsule walks, sprints and slides through a pile of
# ragdolls with its speed, stance and view untouched (it never meets a bone), the legs push the
# dead's limbs out of them (`CorpseNudge`) without throwing them, and a weapon hold made on a body
# already limp leaves the weapon in the dead hand. Driven by the keys a player presses.
extends GdUnitTestSuite

## Where the dead lie: a row along -Z, the way the player runs.
const DEAD: Array[Vector3] = [
	Vector3(0.0, 0.0, -3.0),
	Vector3(0.15, 0.0, -3.8),
	Vector3(0.0, 0.0, -4.6),
	Vector3(0.15, 0.0, -5.4),
]

var _arena: AiArena
var _player: Player
var _dead: Array[AiCharacter] = []


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(AiArena.new())
	add_child(_arena)
	_arena.add_director()
	_dead.clear()
	for spot in DEAD:
		_dead.append(_arena.add_character(spot))
	_player = _arena.add_player(Vector3(0.0, 0.0, 4.0))
	await InputSim.ticks(get_tree(), 10)
	for body in _dead:
		body.die()
	# Long enough for every body to lie still on the floor.
	await InputSim.ticks(get_tree(), 240)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


# The dead's bone centres inside the player's capsule now.
func _inside() -> int:
	var capsule := (_player.get_node(^"%Body") as CollisionShape3D).shape as CapsuleShape3D
	var low := _player.global_position + Vector3.UP * capsule.radius
	var high := _player.global_position + Vector3.UP * (capsule.height - capsule.radius)
	var count := 0
	for body in _dead:
		for entry: Dictionary in CharacterRagdoll.BODIES:
			var at := body.ragdoll_body.body(entry.bone).global_position
			var axis := Geometry3D.get_closest_point_to_segment(at, low, high)
			if at.distance_to(axis) < capsule.radius:
				count += 1
	return count


func _fastest_bone() -> float:
	var fastest := 0.0
	for body in _dead:
		for entry: Dictionary in CharacterRagdoll.BODIES:
			fastest = maxf(fastest, body.ragdoll_body.body(entry.bone).linear_velocity.length())
	return fastest


func test_the_dead_lie_limp_on_the_way() -> void:
	for body in _dead:
		assert_bool(body.ragdoll_body.is_limp()).is_true()
		assert_float(body.ragdoll_body.hips().y).is_less(0.3)


func test_a_sprint_through_the_dead_keeps_the_bodys_speed_stance_and_view() -> void:
	var eye := _player.get_node(^"%CameraTarget") as Node3D
	var eye_height := eye.global_position.y
	InputSim.key(KEY_W, true)
	InputSim.key(KEY_SHIFT, true)
	await InputSim.ticks(get_tree(), 30)
	var speed := _player.velocity.length()
	assert_float(speed).is_equal_approx(_player.tuning.sprint_speed, 0.05)
	var crossed := 0
	for tick in 120:
		await get_tree().physics_frame
		if _inside() > 0:
			crossed += 1
		var why := "tick %d" % tick
		assert_float(_player.velocity.length()).override_failure_message(why).is_equal_approx(
			speed, 0.05
		)
		assert_float(_player.global_position.y).override_failure_message(why).is_equal_approx(
			0.0, 0.01
		)
		assert_float(_player.global_position.x).override_failure_message(why).is_equal_approx(
			0.0, 0.01
		)
		assert_float(_player.facing).override_failure_message(why).is_equal_approx(PI, 0.001)
		assert_float(eye.global_position.y).override_failure_message(why).is_equal_approx(
			eye_height, 0.01
		)
		assert_bool(_player.vault_motion.is_active()).override_failure_message(why).is_false()
		assert_int(_player.state).override_failure_message(why).is_equal(Player.State.RUN)
	# It went through the pile, not round it.
	assert_int(crossed).is_greater(0)
	assert_float(_player.global_position.z).is_less(DEAD.back().z - 1.0)


func test_a_slide_into_the_dead_stays_on_the_floor_and_goes_through() -> void:
	InputSim.key(KEY_W, true)
	InputSim.key(KEY_SHIFT, true)
	await InputSim.ticks(get_tree(), 45)
	InputSim.key(KEY_C, true)
	for tick in 60:
		await get_tree().physics_frame
		var why := "tick %d" % tick
		assert_float(_player.global_position.y).override_failure_message(why).is_equal_approx(
			0.0, 0.01
		)
		assert_float(absf(_player.global_position.x)).override_failure_message(why).is_less(0.01)
		assert_bool(_player.vault_motion.is_active()).override_failure_message(why).is_false()
	assert_float(_player.global_position.z).is_less(DEAD[1].z)


func test_the_legs_push_the_dead_out_of_them() -> void:
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 60)
	InputSim.release_all()
	# Stopped among the dead, then a moment to stand there.
	_player.global_position = Vector3(_dead[1].ragdoll_body.hips().x, 0.0, DEAD[1].z)
	await InputSim.ticks(get_tree(), 4)
	assert_int(_inside()).override_failure_message("nothing in the legs to push").is_greater(0)
	await InputSim.ticks(get_tree(), 90)
	assert_int(_inside()).is_equal(0)


func test_with_the_nudge_off_the_dead_stay_in_the_legs() -> void:
	(_player.get_node(^"CorpseNudge") as CorpseNudge).enabled = false
	_player.global_position = Vector3(_dead[1].ragdoll_body.hips().x, 0.0, DEAD[1].z)
	await InputSim.ticks(get_tree(), 94)
	assert_int(_inside()).is_greater(0)


func test_a_sprint_through_the_dead_never_throws_a_body() -> void:
	InputSim.key(KEY_W, true)
	InputSim.key(KEY_SHIFT, true)
	var fastest := 0.0
	var pushed := 0.0
	for tick in 150:
		await get_tree().physics_frame
		fastest = maxf(fastest, _fastest_bone())
	for index in _dead.size():
		var moved := _dead[index].ragdoll_body.hips() - DEAD[index]
		pushed = maxf(pushed, Vector2(moved.x, moved.z).length())
	# Moved aside (a limb faster than a walk, the hips less than a body's length), never thrown.
	assert_float(fastest).is_less(4.0)
	assert_float(pushed).is_less(1.0)
	assert_float(_player.global_position.z).is_less(DEAD.back().z - 1.0)


func test_a_weapon_hold_made_on_a_dead_body_leaves_the_weapon_in_the_dead_hand() -> void:
	var dead := _dead[0]
	var hold := dead.find_children("*", "WeaponHold", true, false)[0] as WeaponHold
	var gun := dead.find_children("*", "BoneAttachment3D", true, false)[0] as Node3D
	var at_first := gun.global_position
	# A stance change after the death makes the hold's modifiers again (a weapon switch does too).
	hold.one_handed = not hold.one_handed
	await InputSim.ticks(get_tree(), 4)
	var simulator := dead.ragdoll_body.simulator()
	for modifier in hold.modifiers():
		(
			assert_int(modifier.get_index())
			. override_failure_message("%s after the ragdoll" % modifier.name)
			. is_less(simulator.get_index())
		)
	assert_float(gun.global_position.distance_to(at_first)).is_less(0.01)
