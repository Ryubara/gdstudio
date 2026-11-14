# A shoulder swap keeps the aim point only when the crosshair is on a character
# (`PlayerCamera.keep_aim_layers`: Characters and Ragdoll): aimed at a wall, the floor or the sky,
# the view moves to the other shoulder without turning; aimed at a character, the view turns so
# the point stays under the crosshair. Every test is driven as a player drives it: the aim
# trigger held on the pad and the swap button (the middle mouse button) pressed, the rig running
# its own frames.
extends GdUnitTestSuite

## Built high above the sample map, so nothing else is in the way.
const SPOT := Vector3(0.0, 100.0, 0.0)
## How far (degrees) the kept point may sit off the crosshair during an aimed swap.
const TOLERANCE := 0.25
## How far (degrees) the view may turn on a swap that keeps nothing.
const STILL := 0.001

var _scene: Node
var _rig: PlayerCamera
var _player: Player
var _camera: Camera3D


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


func after_test() -> void:
	InputSim.release_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioDrain.stop_all(_scene)


func _block(centre: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = centre
	_scene.add_child(body)


func _crosshair() -> Array[Vector3]:
	var centre := _camera.get_viewport().get_visible_rect().size / 2.0
	return [_camera.project_ray_origin(centre), _camera.project_ray_normal(centre)]


func _off_crosshair(point: Vector3) -> float:
	var ray := _crosshair()
	return rad_to_deg(ray[1].angle_to(point - ray[0]))


# Holds the aim trigger until the player aims and the view has settled.
func _aim() -> void:
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await InputSim.ticks(get_tree(), 40)
	assert_bool(_player.aiming).is_true()


# Presses and lets go of the swap button, then runs `frames` frames; the largest turn of the view
# (degrees, yaw or pitch) and the largest angle `point` sat off the crosshair at any physics tick.
func _press_swap(point: Vector3, frames := 30) -> Dictionary:
	var yaw := _rig.yaw
	var pitch := _rig.pitch
	var worst := {"turn": 0.0, "off": 0.0}
	# The crosshair is read at each physics tick, where the player's input reads it for a shot.
	var at_tick := func() -> void: worst["off"] = maxf(worst["off"], _off_crosshair(point))
	get_tree().physics_frame.connect(at_tick)
	# The middle mouse button swaps since Q leans (gdstudio #1400).
	InputSim.mouse_button(MOUSE_BUTTON_MIDDLE, true)
	InputSim.mouse_button(MOUSE_BUTTON_MIDDLE, false)
	for _i in frames:
		await get_tree().process_frame
		var turn := rad_to_deg(absf(angle_difference(deg_to_rad(yaw), deg_to_rad(_rig.yaw))))
		turn = maxf(turn, absf(_rig.pitch - pitch))
		worst["turn"] = maxf(worst["turn"], turn)
	get_tree().physics_frame.disconnect(at_tick)
	# The swap did happen: the view is on the left shoulder.
	assert_int(_rig.shoulder).is_equal(PlayerCamera.Shoulder.LEFT)
	assert_float(_camera.h_offset).is_equal_approx(-_rig.shoulder_offset, 0.001)
	return worst


func _assert_still(worst: Dictionary, label: String) -> void:
	(
		assert_float(worst["turn"])
		. override_failure_message("%s: the view turned %.3f degrees" % [label, worst["turn"]])
		. is_less(STILL)
	)
	assert_bool(_rig.aim_anchored()).is_false()


func test_by_default_only_characters_and_limp_bodies_keep_the_aim() -> void:
	var fresh := PlayerCamera.new()
	assert_int(fresh.keep_aim_layers).is_equal(PhysicsLayers.CHARACTERS | PhysicsLayers.RAGDOLL)
	fresh.free()
	var wall := StaticBody3D.new()
	assert_bool(ShoulderSwapAim.keeps(wall, _rig.keep_aim_layers)).is_false()
	wall.collision_layer = PhysicsLayers.RAGDOLL
	assert_bool(ShoulderSwapAim.keeps(wall, _rig.keep_aim_layers)).is_true()
	assert_bool(ShoulderSwapAim.keeps(null, _rig.keep_aim_layers)).is_false()
	wall.free()


func test_an_aimed_swap_at_a_wall_does_not_turn_the_view() -> void:
	_block(SPOT + Vector3(0.0, 1.5, -4.0), Vector3(40.0, 30.0, 0.5))
	await _aim()
	var point := _rig.crosshair_point()
	assert_float(point.z).is_equal_approx(SPOT.z - 3.75, 0.05)
	_assert_still(await _press_swap(point), "wall")


func test_an_aimed_swap_at_the_floor_does_not_turn_the_view() -> void:
	_rig.pitch = 40.0
	await _aim()
	var point := _rig.crosshair_point()
	assert_float(point.y).is_equal_approx(SPOT.y, 0.05)
	_assert_still(await _press_swap(point), "floor")


func test_an_aimed_swap_at_the_sky_does_not_turn_the_view() -> void:
	_rig.pitch = -20.0
	await _aim()
	var point := _rig.crosshair_point()
	_assert_still(await _press_swap(point), "sky")


func test_an_aimed_swap_at_a_character_keeps_the_point() -> void:
	await _aim()
	# A character standing where the crosshair's ray is 7 m out, its chest on the crosshair.
	var ray := _crosshair()
	var ahead: Vector3 = ray[0] + ray[1] * 7.0
	var body := HitRange.target(_scene, Vector3(ahead.x, SPOT.y, ahead.z))
	HitRange.freeze(body)
	await InputSim.ticks(get_tree(), 10)
	var point := _rig.crosshair_point()
	var across := (
		Vector2(point.x, point.z) - Vector2(body.global_position.x, body.global_position.z)
	)
	assert_float(across.length()).is_less(0.6)
	var worst := await _press_swap(point)
	(
		assert_float(worst["off"])
		. override_failure_message("character: the point came %.3f degrees off" % worst["off"])
		. is_less(TOLERANCE)
	)
	# The view turned inward to keep it (a 1 m shift at about 8 m is about 7 degrees).
	assert_float(worst["turn"]).is_greater(3.0)


func test_an_aimed_swap_at_a_wall_turns_with_every_layer_counted() -> void:
	# The setting is what decides: counting the World layer keeps the point on a wall again.
	_rig.keep_aim_layers = PhysicsLayers.SHOT_MASK
	_block(SPOT + Vector3(0.0, 1.5, -4.0), Vector3(40.0, 30.0, 0.5))
	await _aim()
	var point := _rig.crosshair_point()
	var worst := await _press_swap(point)
	assert_float(worst["off"]).is_less(TOLERANCE)
	assert_float(worst["turn"]).is_greater(3.0)
