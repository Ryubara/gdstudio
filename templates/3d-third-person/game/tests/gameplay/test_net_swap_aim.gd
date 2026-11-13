# The online client keeps the aim through a shoulder swap too: the camera is the client's own
# (cosmetic, never sent), and the shot its `PlayerInput` sends is the ray under its crosshair, so
# a shot fired mid-swap leaves the server's body toward the point the player held under the
# crosshair before the swap. A client and the game server run in one process (`OnlineRig`), the
# client with the real `PlayerInput` in place of the scripted controller, driven by the pad.
extends GdUnitTestSuite

## How far (degrees) the server's shot may point off the kept point (the swap's own tolerance
## plus the command's quantized angles and origin).
const TOLERANCE := 0.3

var _rig: OnlineRig


func before_test() -> void:
	InputSim.release_all()
	_rig = auto_free(OnlineRig.new())
	add_child(_rig)
	assert_bool(_rig.start()).is_true()


func after_test() -> void:
	InputSim.release_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# The pistol's shot is still sounding on both sides: a playing voice leaks at exit.
	AudioDrain.stop_all(_rig)


func test_a_shot_fired_mid_swap_leaves_the_server_body_toward_the_kept_point() -> void:
	var client := await _rig.join("Ada")
	assert_object(client).is_not_null()
	var arena := _rig.views[0].get_child(0)
	var camera_rig: PlayerCamera = arena.get_node("PlayerRig/PlayerCamera")
	var body := client.player
	# The human's input in place of the scripted one.
	var input := PlayerInput.new()
	input.player = body
	body.add_child(input)
	body.controller = input
	input.camera_rig = camera_rig
	await _rig.wait(30)
	# A board 6 m out along the view, in the client's world, on the Characters layer: a swap keeps
	# the point only on a character (`keep_aim_layers`), and a flat board makes the angle exact.
	var camera := camera_rig.camera
	var ahead := -camera.global_basis.z
	ahead.y = 0.0
	var board := StaticBody3D.new()
	board.collision_layer = PhysicsLayers.CHARACTERS
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 8.0, 0.3)
	shape.shape = box
	board.add_child(shape)
	arena.add_child(board)
	board.global_position = body.global_position + ahead.normalized() * 6.0 + Vector3.UP * 1.5
	board.look_at(body.global_position + Vector3.UP * 1.5)
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await _rig.wait(60)
	var centre := camera.get_viewport().get_visible_rect().size / 2.0
	var point := body.weapon.aim_point(
		camera.project_ray_origin(centre), camera.project_ray_normal(centre)
	)
	assert_float(point.distance_to(board.global_position)).is_less(4.0)
	# The server's body fires along the ray of the command it was sent.
	var server_body := _rig.server_body(client)
	var rays: Array[PackedVector3Array] = []
	server_body.weapon.fired.connect(
		func(_shot: Projectile) -> void: rays.append(server_body.aim_ray())
	)
	var mid_swap: Array[bool] = []
	body.weapon.fired.connect(
		func(_shot: Projectile) -> void: mid_swap.append(camera_rig.aim_anchored())
	)
	camera_rig.swap_shoulder()
	await _rig.wait(3)
	InputSim.pad_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await _rig.until(func() -> bool: return not rays.is_empty(), 60)
	assert_array(mid_swap).is_equal([true])
	assert_bool(rays.is_empty()).is_false()
	var ray := rays[0]
	var off := rad_to_deg(ray[1].angle_to(point - ray[0]))
	prints("net swap aim: the server's shot is %.3f degrees off the kept point" % off)
	assert_float(off).is_less(TOLERANCE)
