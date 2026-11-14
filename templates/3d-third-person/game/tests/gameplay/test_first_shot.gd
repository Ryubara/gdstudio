# A first shot from rest lands on the crosshair's point (gdstudio #1411): the player's own rig (the
# shoulder camera, the real crosshair ray) and each of the template's guns, fired by the mouse at a
# wall 5 to 60 m ahead, aimed (the aim held first) and from the hip (one click with the arm down,
# which raises the arm and fires once it is up, gdstudio #1352). Spread and recoil grow only over
# shots fired in a row: the rifle's spread turned every shot, the first one too, up to 1.2 degrees
# off the crosshair (63 cm at 30 m).
extends GdUnitTestSuite

## Built high above the sample map, so nothing else is in the way.
const SPOT := Vector3(0.0, 100.0, 0.0)
const STEP := 1.0 / 60.0
const RANGES: Array[float] = [5.0, 15.0, 30.0, 60.0]
const GUNS: Array[String] = [
	"res://gameplay/weapon/pistol.tres", "res://gameplay/weapon/rifle.tres"
]
## The most a first shot may land off the crosshair's point, seen from the camera (degrees).
const TOLERANCE := 0.02
## Frames between two first shots: past every gun's spread recovery, the kick died away and the
## arm down again.
const REST_FRAMES := 90

var _scene: Node
var _rig: PlayerCamera
var _player: Player
var _camera: Camera3D
var _wall: StaticBody3D


func before_test() -> void:
	InputSim.release_all()
	_scene = scene_runner("res://main.tscn").scene()
	_rig = _scene.get_node("PlayerRig/PlayerCamera")
	_player = _scene.get_node("PlayerRig/Player")
	_camera = _scene.get_node("PlayerRig/Camera")
	await InputSim.ticks(get_tree(), 8)
	_block(SPOT + Vector3(0.0, -0.5, 0.0), Vector3(200.0, 1.0, 200.0))
	_player.teleport(SPOT, 0.0)
	_rig.yaw = 0.0
	_rig.pitch = 0.0
	await InputSim.ticks(get_tree(), 30)
	_rig.set_process(false)


func after_test() -> void:
	InputSim.release_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioDrain.stop_all(_scene)


func _block(centre: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = centre
	_scene.add_child(body)
	return body


# One frame of the rig and then the engine's, so the arm, the host and the `Camera3D` follow.
func _frame() -> void:
	_rig.advance(STEP)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame


func _frames(count: int) -> void:
	for _i in count:
		await _frame()


# A wall whose front face is `distance` m ahead of the player, wide and high enough for every shot.
func _wall_at(distance: float) -> float:
	if _wall != null:
		_wall.queue_free()
	_wall = _block(SPOT + Vector3(0.0, 2.0, -distance - 0.2), Vector3(40.0, 20.0, 0.4))
	return SPOT.z - distance


func _arm(path: String) -> void:
	_player.loadout.give(load(path) as WeaponDef, 30)
	await _frames(REST_FRAMES)
	assert_str(String(_player.weapon.definition.resource_path)).is_equal(path)


# Where the line from `start` along `along` crosses the wall's face (z = `face`).
func _on_face(start: Vector3, along: Vector3, face: float) -> Vector3:
	return start + along * ((face - start.z) / along.z)


# Fires one shot by a mouse click (with the aim held first when `aimed`), and returns how far it
# landed off the crosshair's point, in degrees from the camera: the crosshair as it was when the
# button went down, and as it was on the tick the shot left.
func _first_shot(face: float, aimed: bool) -> Vector2:
	if aimed:
		InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
		await _frames(40)
	var centre := _camera.get_viewport().get_visible_rect().size / 2.0
	var pressed_at := _camera.project_ray_origin(centre)
	var pressed_point := _on_face(pressed_at, _camera.project_ray_normal(centre), face)
	var shots: Array[PackedVector3Array] = []
	var weapon := _player.weapon
	var on_fired := func(_shot: Projectile) -> void:
		var ray := _player.aim_ray()
		shots.append(PackedVector3Array([ray[0], ray[1], weapon.last_origin, weapon.last_heading]))
	weapon.fired.connect(on_fired)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await _frame()
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
	for _i in 40:
		if not shots.is_empty():
			break
		await _frame()
	weapon.fired.disconnect(on_fired)
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, false)
	await _frames(REST_FRAMES)
	if shots.size() != 1:
		return Vector2(INF, INF)
	var shot := shots[0]
	var hit := _on_face(shot[2], shot[3], face)
	var crosshair := _on_face(shot[0], shot[1], face)
	return Vector2(
		rad_to_deg((pressed_point - pressed_at).angle_to(hit - pressed_at)),
		rad_to_deg((crosshair - shot[0]).angle_to(hit - shot[0]))
	)


func _every_first_shot(aimed: bool) -> void:
	var misses: Array[String] = []
	for path in GUNS:
		await _arm(path)
		for distance in RANGES:
			var face := _wall_at(distance)
			await _frames(2)
			var off := await _first_shot(face, aimed)
			if off.x > TOLERANCE or off.y > TOLERANCE:
				misses.append(
					(
						"%s at %.0f m: %.3f deg off the crosshair at the press, %.3f at the shot"
						% [path.get_file(), distance, off.x, off.y]
					)
				)
	assert_array(misses).override_failure_message("\n".join(misses)).is_empty()


func test_an_aimed_first_shot_lands_on_the_crosshair_at_every_range() -> void:
	await _every_first_shot(true)


func test_a_first_shot_from_the_hip_lands_on_the_crosshair_at_every_range() -> void:
	await _every_first_shot(false)
