# Sliding, in the real physics world: crouch pressed at a sprint drops the body into a slide that
# keeps its momentum, slows by friction and ends standing or crouched; a slope speeds it up or
# slows it down, a jump out of it keeps the speed, a low gap is slid under. Keys through the
# project's InputMap first, then commands alone (a bot, a server), then snapshots. The numbers are
# `SlideTuning` (`slide_tuning.tres`).
extends GdUnitTestSuite

const SLIDE := "res://gameplay/player/slide_tuning.tres"

var _arena: PlayArena
var _player: Player
var _tuning: CharacterTuning
var _slide: SlideTuning


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3(0.0, 0.0, 20.0))
	_player.tuning = (
		(load("res://gameplay/player/player_tuning.tres") as CharacterTuning).duplicate()
	)
	_player.slide_tuning = ((load(SLIDE) as SlideTuning).duplicate())
	_tuning = _player.tuning
	_slide = _player.slide_tuning
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


func _capsule() -> CapsuleShape3D:
	return (_player.get_node("%Body") as CollisionShape3D).shape as CapsuleShape3D


func _target() -> Node3D:
	return _player.get_node("%CameraTarget") as Node3D


# Sprints north (-Z) with the keys for `count` ticks.
func _sprint(count: int) -> void:
	InputSim.key(KEY_W, true)
	InputSim.key(KEY_SHIFT, true)
	await InputSim.ticks(get_tree(), count)


# Ticks until the slide ends (at most `limit`); returns how many.
func _ticks_until_the_slide_ends(limit: int) -> int:
	for tick in limit:
		await InputSim.ticks(get_tree(), 1)
		if not _player.sliding:
			return tick + 1
	return limit


func test_crouch_at_a_sprint_slides_low_with_a_boost() -> void:
	await _sprint(40)
	assert_float(_player.ground_speed()).is_equal_approx(_tuning.sprint_speed, 0.1)
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 1)
	assert_bool(_player.sliding).is_true()
	assert_int(_player.state).is_equal(Player.State.SLIDE)
	# The boost, less one tick of friction.
	var boosted := minf(_tuning.sprint_speed + _slide.boost, _slide.boost_cap)
	assert_float(_player.ground_speed()).is_equal_approx(boosted, 0.15)
	assert_bool(_player.crouching).is_false()
	assert_bool(_player.is_sprinting()).is_false()
	await InputSim.ticks(get_tree(), 12)
	assert_float(_capsule().height).is_equal_approx(_slide.height, 0.001)
	assert_float(_target().position.y).is_equal_approx(_slide.camera_height, 0.001)
	var body := _player.get_node("%Body") as CollisionShape3D
	assert_float(body.position.y - _capsule().height / 2.0).is_equal_approx(0.0, 0.001)


func test_a_flat_slide_slows_by_friction_and_ends_crouched_while_crouch_is_held() -> void:
	await _sprint(40)
	InputSim.key(KEY_SHIFT, false)
	var start := _player.global_position
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 1)
	var speeds: Array[float] = [_player.ground_speed()]
	var ticks := 0
	for tick in 200:
		await InputSim.ticks(get_tree(), 1)
		if not _player.sliding:
			ticks = tick + 1
			break
		speeds.append(_player.ground_speed())
	# Friction only takes speed away on the flat, every tick.
	for index in range(1, speeds.size()):
		assert_float(speeds[index]).is_less(speeds[index - 1])
	var seconds := ticks / float(Engine.physics_ticks_per_second)
	assert_float(seconds).is_between(0.7, _slide.max_time)
	var travelled := Vector2(
		_player.global_position.x - start.x, _player.global_position.z - start.z
	)
	assert_float(travelled.length()).is_between(3.5, 7.0)
	await InputSim.ticks(get_tree(), 2)
	assert_bool(_player.crouching).is_true()
	assert_int(_player.state).is_equal(Player.State.CROUCH)


func test_letting_go_of_crouch_ends_the_slide_and_stands() -> void:
	await _sprint(40)
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 15)
	assert_bool(_player.sliding).is_true()
	InputSim.key(KEY_C, false)
	await InputSim.ticks(get_tree(), 1)
	assert_bool(_player.sliding).is_false()
	await InputSim.ticks(get_tree(), 20)
	assert_bool(_player.crouching).is_false()
	assert_float(_capsule().height).is_equal_approx(_tuning.height, 0.001)
	assert_int(_player.state).is_equal(Player.State.RUN)


func test_off_hold_a_tap_slides_to_the_end() -> void:
	_slide.hold_to_continue = false
	await _sprint(40)
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_C, false)
	InputSim.key(KEY_W, false)
	InputSim.key(KEY_SHIFT, false)
	await InputSim.ticks(get_tree(), 20)
	assert_bool(_player.sliding).is_true()
	var ticks := await _ticks_until_the_slide_ends(200)
	assert_int(ticks).is_less(200)
	await InputSim.ticks(get_tree(), 20)
	assert_bool(_player.crouching).is_false()


func test_a_jog_crouches_and_does_not_slide() -> void:
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 40)
	assert_float(_player.ground_speed()).is_less(_slide.min_speed)
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 2)
	assert_bool(_player.sliding).is_false()
	assert_bool(_player.crouching).is_true()


func test_a_second_slide_soon_after_gets_no_boost() -> void:
	await _sprint(40)
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 10)
	InputSim.key(KEY_C, false)
	await InputSim.ticks(get_tree(), 30)
	assert_float(_player.ground_speed()).is_equal_approx(_tuning.sprint_speed, 0.1)
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 1)
	assert_bool(_player.sliding).is_true()
	assert_float(_player.ground_speed()).is_less(_tuning.sprint_speed)


func test_slide_off_turns_crouch_back_into_a_crouch() -> void:
	_slide.enabled = false
	await _sprint(40)
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 2)
	assert_bool(_player.sliding).is_false()
	assert_bool(_player.crouching).is_true()


func test_a_slide_goes_under_a_gap_too_low_to_crouch_in_and_stands_past_it() -> void:
	# A slab whose underside is 1.0 m up (under the crouch's 1.1 m, over the slide's 0.9 m), from
	# z = 13 to z = 9, so the slide ends under it.
	_arena.add_block(Vector2(0.0, 11.0), Vector3(4.0, 0.4, 4.0), 1.4)
	await _sprint(30)
	InputSim.key(KEY_W, false)
	InputSim.key(KEY_SHIFT, false)
	# Crouch held through it: the slide does not end under the slab, though it slows to its exit
	# speed there, and ends crouched past it.
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 200)
	# Out from under the edge (z = 9) by about the capsule's radius.
	assert_float(_player.global_position.z).is_less(9.0 - _tuning.radius + 0.05)
	assert_bool(_player.crouching).is_true()
	InputSim.key(KEY_C, false)
	await InputSim.ticks(get_tree(), 30)
	assert_bool(_player.sliding).is_false()
	assert_bool(_player.crouching).is_false()
	assert_float(_capsule().height).is_equal_approx(_tuning.height, 0.001)


func test_a_slide_that_ends_under_a_low_ceiling_stays_crouched() -> void:
	# A ceiling 1.25 m up (room to crouch, not to stand) over the whole end of the slide.
	_arena.add_block(Vector2(0.0, 9.0), Vector3(4.0, 0.4, 10.0), 1.65)
	await _sprint(30)
	InputSim.key(KEY_W, false)
	InputSim.key(KEY_SHIFT, false)
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 120)
	assert_bool(_player.sliding).is_false()
	InputSim.key(KEY_C, false)
	await InputSim.ticks(get_tree(), 20)
	assert_bool(_player.has_room_to_stand()).is_false()
	assert_bool(_player.crouching).is_true()
	assert_float(_capsule().height).is_less(_tuning.crouch_height + 0.001)


func test_a_standing_sprint_is_stopped_by_the_low_gap() -> void:
	_arena.add_block(Vector2(0.0, 11.0), Vector3(4.0, 0.4, 4.0), 1.4)
	await _sprint(90)
	assert_float(_player.global_position.z).is_greater(13.0)


func test_downhill_speeds_the_slide_up_and_uphill_ends_it_sooner() -> void:
	var down := await _slide_on_a_ramp(-20.0)
	var flat := await _slide_on_a_ramp(0.0)
	var up := await _slide_on_a_ramp(20.0)
	assert_float(down["peak"]).is_greater(flat["peak"] + 0.5)
	assert_float(down["seconds"]).is_greater(_slide.max_time)
	assert_float(up["seconds"]).is_less(flat["seconds"])


# Slides on a ramp tilted `degrees` (positive rises to the north) from the sprint; returns the
# peak speed and how long the slide lasted.
func _slide_on_a_ramp(degrees: float) -> Dictionary:
	InputSim.release_all()
	var ramp := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 1.0, 60.0)
	shape.shape = box
	ramp.add_child(shape)
	# Off the arena's floor (it ends at x = 30) and high above it.
	ramp.position = Vector3(40.0, 10.0, 0.0)
	ramp.rotation.x = deg_to_rad(degrees)
	_arena.add_child(ramp)
	# On the top surface 20 m south of the ramp's middle: cos(a) y + sin(a) z = 0.5 there.
	var angle := deg_to_rad(degrees)
	var south := 20.0
	var top := Vector3(40.0, 10.0 + (0.5 - sin(angle) * south) / cos(angle), south)
	_player.teleport(top + Vector3(0.0, 0.05, 0.0), PI)
	CommandDriver.take(_player)
	var run := CommandDriver.walking(Vector3.FORWARD)
	run.sprint = true
	await CommandDriver.run(get_tree(), [_player], run, 40)
	run.crouch = true
	var peak := 0.0
	var ticks := 0
	for tick in 600:
		await CommandDriver.run(get_tree(), [_player], run, 1)
		peak = maxf(peak, _player.velocity.length())
		ticks = tick + 1
		if not _player.sliding:
			break
	ramp.queue_free()
	_player.teleport(Vector3(0.0, 0.0, 20.0), PI)
	return {"peak": peak, "seconds": ticks / float(Engine.physics_ticks_per_second)}


func test_a_jump_out_of_the_slide_keeps_its_speed_in_the_air() -> void:
	await _sprint(40)
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 6)
	var speed := _player.ground_speed()
	InputSim.key(KEY_SPACE, true)
	await InputSim.ticks(get_tree(), 2)
	assert_bool(_player.sliding).is_false()
	assert_bool(_player.is_on_floor()).is_false()
	var top := 0.0
	for tick in 60:
		await InputSim.ticks(get_tree(), 1)
		top = maxf(top, _player.global_position.y)
		if tick == 20:
			# Faster than a sprint after a third of a second in the air.
			assert_float(_player.ground_speed()).is_greater(_tuning.sprint_speed + 0.3)
			assert_float(_player.ground_speed()).is_less(speed + 0.01)
	var height := _tuning.jump_height * _slide.jump_height_scale
	assert_float(top).is_equal_approx(height, 0.12)


func test_slide_jump_off_keeps_the_body_on_the_ground() -> void:
	_slide.jump = false
	await _sprint(40)
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 6)
	InputSim.key(KEY_SPACE, true)
	await InputSim.ticks(get_tree(), 10)
	assert_float(_player.global_position.y).is_less(0.05)


func test_a_bot_slides_by_command_alone() -> void:
	CommandDriver.take(_player)
	var run := CommandDriver.walking(Vector3.FORWARD)
	run.sprint = true
	await CommandDriver.run(get_tree(), [_player], run, 40)
	run.crouch = true
	await CommandDriver.run(get_tree(), [_player], run, 3)
	assert_bool(_player.sliding).is_true()
	assert_int(_player.state).is_equal(Player.State.SLIDE)


func test_the_stick_steers_a_slide_only_a_little() -> void:
	CommandDriver.take(_player)
	var run := CommandDriver.walking(Vector3.FORWARD)
	run.sprint = true
	await CommandDriver.run(get_tree(), [_player], run, 40)
	var turn := CommandDriver.walking(Vector3.RIGHT)
	turn.crouch = true
	await CommandDriver.run(get_tree(), [_player], turn, 30)
	assert_bool(_player.sliding).is_true()
	var heading := Vector3(_player.velocity.x, 0.0, _player.velocity.z).normalized()
	var turned := rad_to_deg(Vector3.FORWARD.angle_to(heading))
	var most := rad_to_deg(_slide.turn_rate) * 30.0 / Engine.physics_ticks_per_second
	assert_float(turned).is_between(most * 0.8, most + 1.0)


func test_a_restore_mid_slide_goes_the_same_way_again() -> void:
	CommandDriver.take(_player)
	var run := CommandDriver.walking(Vector3(0.3, 0.0, -1.0))
	run.sprint = true
	await CommandDriver.run(get_tree(), [_player], run, 40)
	run.crouch = true
	await CommandDriver.run(get_tree(), [_player], run, 10)
	assert_bool(_player.sliding).is_true()
	var kept := _player.state_snapshot()
	var first: Array[Vector3] = []
	await CommandDriver.run(
		get_tree(), [_player], run, 60, func(_t: int) -> void: first.append(_player.velocity)
	)
	_player.restore(kept)
	var second: Array[Vector3] = []
	await CommandDriver.run(
		get_tree(), [_player], run, 60, func(_t: int) -> void: second.append(_player.velocity)
	)
	for index in first.size():
		assert_vector(second[index]).is_equal_approx(first[index], Vector3.ONE * 0.001)


func test_two_bodies_slide_alike_from_one_command_stream() -> void:
	var other := _arena.add_player(Vector3(6.0, 0.0, 20.0))
	await InputSim.ticks(get_tree(), 4)
	other.tuning = _tuning
	CommandDriver.take(_player)
	CommandDriver.take(other)
	var run := CommandDriver.walking(Vector3.FORWARD)
	run.sprint = true
	await CommandDriver.run(get_tree(), [_player, other], run, 40)
	run.crouch = true
	await CommandDriver.run(get_tree(), [_player, other], run, 30)
	assert_bool(other.sliding).is_equal(_player.sliding)
	assert_vector(other.velocity).is_equal_approx(_player.velocity, Vector3.ONE * 0.001)
	var gap := other.global_position - _player.global_position
	assert_vector(gap).is_equal_approx(Vector3(6.0, 0.0, 0.0), Vector3.ONE * 0.001)


# Every slide setting is pinned, with the default the research picked (the kit's character
# page gives the sources), on a fresh resource and in the player's file.
func test_every_slide_setting_is_pinned() -> void:
	var pins := {
		&"enabled": true,
		&"min_speed": 5.0,
		&"needs_sprint": false,
		&"while_aiming": false,
		&"on_landing": true,
		&"boost": 1.5,
		&"boost_cap": 8.5,
		&"boost_cooldown": 2.0,
		&"friction": 3.5,
		&"drag": 0.3,
		&"max_speed": 11.0,
		&"exit_speed": 3.0,
		&"max_time": 1.5,
		&"downhill_unlimited": true,
		&"gravity": 9.8,
		&"downhill_friction": 0.2,
		&"flat_angle": 4.0,
		&"turn_rate": 1.2,
		&"cooldown": 0.3,
		&"hold_to_continue": true,
		&"height": 0.9,
		&"drop_time": 0.12,
		&"camera_height": 0.75,
		&"can_shoot": true,
		&"jump": true,
		&"jump_height_scale": 0.85,
		&"jump_boost": 0.0,
		&"jump_max_speed": 9.0,
		&"jump_air_drag": 1.0,
	}
	for tuning: SlideTuning in [SlideTuning.new(), load(SLIDE)]:
		assert_array(ExportPins.differences(tuning, pins)).is_empty()
		assert_array(ExportPins.wrong_values(tuning, pins)).is_empty()
