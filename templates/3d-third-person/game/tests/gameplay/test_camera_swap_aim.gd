# A shoulder swap keeps the point under the crosshair where it is (`keep_aim_on_swap`): the view
# turns inward as it slides, so the point the weapon aims at stays on the crosshair through the
# swap, on a near board and a far one, and a shot fired mid-swap goes there. The point is kept
# only on a character (`keep_aim_layers`, the Characters and Ragdoll layers): aimed at a wall, the
# floor or the sky the view slides without turning (test_camera_swap_target.gd). The boards here
# are on the Characters layer, stand-ins for a character whose flat face makes the angle exact. The
# player's look during the swap adds to the turn (`SwapLook.ADD`) or lets the point go past an
# angle (`RELEASE`); with the anchor off the view slides and the aim drifts as before. By default
# the point is kept only on a swap made while aiming (`keep_aim_when_not_aiming` off): a swap
# while running only slides the view, so the run keeps its way. The suite turns that option on
# for the tests of the anchor's geometry, which swap standing; the tests of the default turn it
# off again. The rig's
# own `_process` is off: every frame is `advance(1/60)` and then the engine's frames, so the
# Phantom Camera and the real `Camera3D` catch up before the crosshair is read.
extends GdUnitTestSuite

## Built high above the sample map, so nothing else is in the way.
const SPOT := Vector3(0.0, 100.0, 0.0)
const STEP := 1.0 / 60.0
## How far (degrees) the kept point may sit off the crosshair during the swap.
const TOLERANCE := 0.2

var _scene: Node
var _rig: PlayerCamera
var _player: Player
var _camera: Camera3D
## The scene's own `keep_aim_when_not_aiming`, read before the suite turns it on.
var _keeps_when_not_aiming := true


func before_test() -> void:
	InputSim.release_all()
	_scene = scene_runner("res://main.tscn").scene()
	_rig = _scene.get_node("PlayerRig/PlayerCamera")
	_player = _scene.get_node("PlayerRig/Player")
	_camera = _scene.get_node("PlayerRig/Camera")
	await InputSim.ticks(get_tree(), 8)
	_block(SPOT + Vector3(0.0, -0.5, 0.0), Vector3(60.0, 1.0, 60.0))
	_player.teleport(SPOT, 0.0)
	_rig.yaw = 0.0
	_rig.pitch = 0.0
	await InputSim.ticks(get_tree(), 30)
	_rig.set_process(false)
	_keeps_when_not_aiming = _rig.keep_aim_when_not_aiming
	_rig.keep_aim_when_not_aiming = true


func after_test() -> void:
	InputSim.release_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioDrain.stop_all(_scene)


func _block(centre: Vector3, size: Vector3, layer := PhysicsLayers.WORLD) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = centre
	_scene.add_child(body)


# A board straight ahead of the spot, `distance` metres out, as tall and wide as the view, on the
# Characters layer: a swap keeps the point on it as it would on a character.
func _board(distance: float) -> void:
	_block(SPOT + Vector3(0.0, 1.5, -distance), Vector3(40.0, 30.0, 0.5), PhysicsLayers.CHARACTERS)


# One frame of the rig and then the engine's, so the arm, the host and the `Camera3D` follow.
func _frame(delta := STEP) -> void:
	_rig.advance(delta)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame


func _settle(frames := 40) -> void:
	for _i in frames:
		await _frame()


func _crosshair() -> Array[Vector3]:
	var centre := _camera.get_viewport().get_visible_rect().size / 2.0
	return [_camera.project_ray_origin(centre), _camera.project_ray_normal(centre)]


# What the weapon aims at along the crosshair's ray now (the shot's own point, not the rig's).
func _aimed_point() -> Vector3:
	var ray := _crosshair()
	return _player.weapon.aim_point(ray[0], ray[1])


# How far `point` sits off the crosshair, in degrees.
func _off_crosshair(point: Vector3) -> float:
	var ray := _crosshair()
	return rad_to_deg(ray[1].angle_to(point - ray[0]))


# Swaps and runs `frames` frames; the largest angle the point aimed at before the swap sat off
# the crosshair in any of them, and that point. `look` is called on each frame index.
func _swap_and_track(frames := 24, look := Callable()) -> Dictionary:
	await _settle()
	var point := _aimed_point()
	# Read at each physics tick too (before the bodies step), where the player's input reads
	# the camera for a shot, as well as after each frame, where it is drawn.
	var worst := [0.0]
	var at_tick := func() -> void: worst[0] = maxf(worst[0], _off_crosshair(point))
	get_tree().physics_frame.connect(at_tick)
	_rig.swap_shoulder()
	for index in frames:
		if look.is_valid():
			look.call(index)
		await _frame()
		worst[0] = maxf(worst[0], _off_crosshair(point))
	get_tree().physics_frame.disconnect(at_tick)
	return {"point": point, "worst": worst[0], "last": _off_crosshair(point)}


func _assert_kept(result: Dictionary, label: String) -> void:
	(
		assert_float(result["worst"])
		. override_failure_message(
			"%s: the aimed point came %.3f degrees off the crosshair" % [label, result["worst"]]
		)
		. is_less(TOLERANCE)
	)
	# The swap did happen: the view is on the left shoulder.
	assert_float(_camera.h_offset).is_equal_approx(-_rig.shoulder_offset, 0.001)


func test_the_anchor_is_on_by_default_and_every_choice_is_exported() -> void:
	assert_bool(_rig.keep_aim_on_swap).is_true()
	assert_bool(_keeps_when_not_aiming).is_false()
	var names: Array[String] = []
	for property in _rig.get_property_list():
		if property["usage"] & PROPERTY_USAGE_EDITOR:
			names.append(property["name"])
	for wanted in [
		"shoulder_time",
		"aim_shoulder_time",
		"keep_aim_on_swap",
		"keep_aim_when_not_aiming",
		"swap_anchor_strength",
		"swap_look",
		"swap_release_angle",
		"aim_point_range",
		"aim_point_min_distance",
		"aim_point_mask",
		"keep_aim_layers",
	]:
		assert_array(names).contains([wanted])


func test_a_far_board_stays_under_the_crosshair_through_the_swap() -> void:
	_board(30.0)
	_assert_kept(await _swap_and_track(), "far board")


func test_a_near_board_stays_under_the_crosshair_through_the_swap() -> void:
	_board(4.0)
	var result := await _swap_and_track()
	_assert_kept(result, "near board")
	assert_float((result["point"] as Vector3).z).is_equal_approx(SPOT.z - 3.75, 0.05)


func test_with_nothing_hit_the_point_is_the_ray_end_and_the_view_does_not_turn() -> void:
	# Looking up at the empty sky: the point is the ray's end, `aim_point_range` out, and it is
	# no character, so the swap only slides the view.
	_rig.pitch = -20.0
	await _settle()
	var ray := _crosshair()
	assert_float(ray[0].distance_to(_rig.crosshair_point())).is_greater(90.0)
	var yaw_before := _rig.yaw
	var result := await _swap_and_track()
	assert_bool(_rig.aim_anchored()).is_false()
	assert_float(_rig.yaw).is_equal(yaw_before)
	assert_float(result["last"]).is_greater(0.2)


func test_with_the_anchor_off_the_view_slides_and_the_aim_drifts() -> void:
	_rig.keep_aim_on_swap = false
	_board(4.0)
	var yaw_before := _rig.yaw
	var pitch_before := _rig.pitch
	var result := await _swap_and_track()
	# Today's behaviour: the view only slides, so a near point drifts by the whole shift.
	assert_float(_rig.yaw).is_equal(yaw_before)
	assert_float(_rig.pitch).is_equal(pitch_before)
	assert_float(result["last"]).is_greater(8.0)
	assert_float(_camera.h_offset).is_equal_approx(-_rig.shoulder_offset, 0.001)


func test_the_anchor_off_drifts_and_on_does_not_on_the_same_far_board() -> void:
	_board(30.0)
	_rig.keep_aim_on_swap = false
	var off := await _swap_and_track()
	_rig.keep_aim_on_swap = true
	_rig.swap_shoulder()
	await _settle()
	var on := await _swap_and_track()
	assert_float(off["last"]).is_greater(1.5)
	assert_float(on["worst"]).is_less(TOLERANCE)


func test_a_shot_fired_mid_swap_goes_to_the_crosshair_and_the_kept_point() -> void:
	_board(8.0)
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await _settle()
	var point := _aimed_point()
	_rig.swap_shoulder()
	for _i in 4:
		await _frame()
	assert_bool(_rig.aim_anchored()).is_true()
	# A real shot, fired by the body from its own command mid-swap, hits the board there.
	var hits: Array[Vector3] = []
	var on_hit := func(_collider: Node, at: Vector3, _normal: Vector3) -> void: hits.append(at)
	# The ray the body fired along: the shot block of the command its input made from the camera.
	var rays: Array[PackedVector3Array] = []
	var mid_swap: Array[bool] = []
	_player.weapon.fired.connect(
		func(shot: Projectile) -> void:
			shot.impacted.connect(on_hit)
			rays.append(_player.aim_ray())
			mid_swap.append(_rig.aim_anchored())
	)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	var fired_at := -1
	for index in 40:
		await _frame()
		if fired_at < 0 and _player.weapon.live_projectiles().size() > 0:
			fired_at = index
		if not hits.is_empty():
			break
	assert_int(fired_at).is_between(0, 10)
	assert_bool(hits.is_empty()).is_false()
	assert_float(hits[0].distance_to(point)).is_less(0.05)
	assert_array(mid_swap).is_equal([true])
	var ray := rays[0]
	assert_float(rad_to_deg(ray[1].angle_to(point - ray[0]))).is_less(TOLERANCE)


func test_look_mid_swap_adds_to_the_turn() -> void:
	_board(30.0)
	var plain := await _swap_and_track()
	var yaw_plain := _rig.yaw
	_rig.swap_shoulder()
	await _settle()
	# The same swap again, with a look of 3 degrees to the right on the sixth frame.
	await _swap_and_track(
		24,
		func(index: int) -> void:
			if index == 5:
				_rig.orbit(Vector2(3.0, 0.0))
	)
	assert_float(plain["worst"]).is_less(TOLERANCE)
	# The anchor stayed to the end: the view is the kept view turned 3 degrees right.
	var turned := rad_to_deg(angle_difference(deg_to_rad(_rig.yaw), deg_to_rad(yaw_plain)))
	assert_float(turned).is_equal_approx(3.0, 0.05)


func test_a_small_look_with_release_keeps_the_anchor_and_a_big_one_lets_go() -> void:
	_board(4.0)
	_rig.swap_look = PlayerCamera.SwapLook.RELEASE
	_rig.swap_release_angle = 4.0
	await _swap_and_track()
	var yaw_plain := _rig.yaw
	_rig.swap_shoulder()
	await _settle()
	# Below the angle the look adds: the view ends 1 degree left of the kept view.
	await _swap_and_track(
		24,
		func(index: int) -> void:
			if index == 2:
				_rig.orbit(Vector2(-1.0, 0.0))
	)
	var turned := rad_to_deg(angle_difference(deg_to_rad(yaw_plain), deg_to_rad(_rig.yaw)))
	assert_float(turned).is_equal_approx(1.0, 0.05)
	_rig.swap_shoulder()
	await _settle()
	# Past the angle the anchor lets go at once: no more turn after the look, and the point
	# drifts by the look and the rest of the slide.
	var yaw_at_release := [0.0]
	var big := await _swap_and_track(
		24,
		func(index: int) -> void:
			if index == 2:
				_rig.orbit(Vector2(-5.0, 0.0))
				yaw_at_release[0] = _rig.yaw
	)
	assert_bool(_rig.aim_anchored()).is_false()
	assert_float(_rig.yaw).is_equal_approx(yaw_at_release[0], 0.001)
	assert_float(big["last"]).is_greater(5.0)


func test_a_stick_inside_its_dead_zone_sends_no_look_and_the_aim_does_not_drift() -> void:
	_board(8.0)
	# 0.1 is inside the look actions' 0.2 dead zone: the rig's own frame orbits nothing.
	InputSim.pad_axis(JOY_AXIS_RIGHT_X, 0.1)
	await _settle()
	var point := _aimed_point()
	_rig.swap_shoulder()
	var worst := 0.0
	for _i in 24:
		_rig._process(STEP)
		await get_tree().process_frame
		await get_tree().physics_frame
		await get_tree().process_frame
		worst = maxf(worst, _off_crosshair(point))
	assert_float(worst).is_less(TOLERANCE)


func test_a_zero_swap_time_swaps_at_once_and_keeps_the_point() -> void:
	_board(6.0)
	_rig.shoulder_time = 0.0
	await _settle()
	var point := _aimed_point()
	_rig.swap_shoulder()
	await _frame()
	assert_float(_camera.h_offset).is_equal_approx(-_rig.shoulder_offset, 0.001)
	assert_float(_off_crosshair(point)).is_less(TOLERANCE)
	assert_bool(_rig.aim_anchored()).is_false()


func test_aiming_swaps_in_the_aim_swap_time() -> void:
	_board(10.0)
	_rig.shoulder_time = 1.0
	_rig.aim_shoulder_time = 0.1
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await InputSim.ticks(get_tree(), 4)
	var result := await _swap_and_track(8)
	assert_bool(_player.aiming).is_true()
	assert_float(_camera.h_offset).is_equal_approx(-_rig.shoulder_offset, 0.001)
	assert_float(result["worst"]).is_less(TOLERANCE)


func test_a_swap_back_mid_swap_keeps_the_same_point() -> void:
	_board(5.0)
	await _settle()
	var point := _aimed_point()
	_rig.swap_shoulder()
	var worst := 0.0
	for index in 30:
		if index == 7:
			_rig.swap_shoulder()
		await _frame()
		worst = maxf(worst, _off_crosshair(point))
	assert_float(worst).is_less(TOLERANCE)
	assert_float(_camera.h_offset).is_equal_approx(_rig.shoulder_offset, 0.001)


func test_half_strength_turns_half_way() -> void:
	_board(4.0)
	_rig.keep_aim_on_swap = false
	var off := await _swap_and_track()
	_rig.keep_aim_on_swap = true
	_rig.swap_anchor_strength = 0.5
	var half := await _swap_and_track()
	assert_float(half["last"]).is_between(off["last"] * 0.35, off["last"] * 0.65)


func test_crouched_the_point_is_kept_too() -> void:
	_board(6.0)
	InputSim.key(KEY_C, true)
	await InputSim.ticks(get_tree(), 40)
	assert_bool(_player.crouching).is_true()
	_assert_kept(await _swap_and_track(), "crouched")


# Holds forward and sprint until the character is at a full sprint.
func _sprint() -> void:
	InputSim.key(KEY_W, true)
	InputSim.key(KEY_SHIFT, true)
	for _i in 50:
		await _frame()
	assert_bool(_player.is_sprinting()).is_true()


func _flat(vector: Vector3) -> Vector2:
	return Vector2(vector.x, vector.z)


func test_by_default_a_sprinting_swap_turns_neither_the_view_nor_the_run() -> void:
	_rig.keep_aim_when_not_aiming = false
	_board(30.0)
	await _sprint()
	var yaw_before := _rig.yaw
	var pitch_before := _rig.pitch
	var run_before := _flat(_player.velocity)
	_rig.swap_shoulder()
	assert_bool(_rig.aim_anchored()).is_false()
	var worst_run := 0.0
	for _i in 24:
		await _frame()
		worst_run = maxf(worst_run, absf(rad_to_deg(run_before.angle_to(_flat(_player.velocity)))))
	assert_bool(_player.is_sprinting()).is_true()
	assert_float(_rig.yaw).is_equal_approx(yaw_before, 0.001)
	assert_float(_rig.pitch).is_equal_approx(pitch_before, 0.001)
	(
		assert_float(worst_run)
		. override_failure_message("the run turned %.3f degrees across the swap" % worst_run)
		. is_less(0.05)
	)
	# The swap did happen: the view is on the left shoulder.
	assert_float(_camera.h_offset).is_equal_approx(-_rig.shoulder_offset, 0.001)


func test_by_default_an_aimed_swap_keeps_the_point() -> void:
	_rig.keep_aim_when_not_aiming = false
	_board(10.0)
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await InputSim.ticks(get_tree(), 4)
	var result := await _swap_and_track()
	assert_bool(_player.aiming).is_true()
	_assert_kept(result, "aimed, default")


func test_with_keeping_when_not_aiming_on_a_sprinting_swap_keeps_the_point() -> void:
	_board(30.0)
	await _sprint()
	var point := _aimed_point()
	var yaw_before := _rig.yaw
	_rig.swap_shoulder()
	assert_bool(_rig.aim_anchored()).is_true()
	var worst := 0.0
	for _i in 24:
		await _frame()
		worst = maxf(worst, _off_crosshair(point))
	# Running, the follow damping keeps the arm a little behind the body (0.26 degrees seen).
	assert_float(worst).is_less(TOLERANCE * 2.5)
	# The view turned inward to keep it, and the run with it.
	assert_float(absf(_rig.yaw - yaw_before)).is_greater(1.0)
