# A shot at a character a few metres away lands where the crosshair is (gdstudio #1251): the
# player's own rig (the shoulder camera, the real crosshair ray), its pistol fired by the fire
# button, and a dressed character 2 to 4 m ahead, standing and crouched, with a wall behind it.
# The crosshair is put on the head (its middle or near its edge) or just beside it. The muzzle
# sits low and to the left of the camera's line, so the weapon must aim at the part the
# crosshair is on: aimed at the capsule's surface, in front of the part, the shot crossed the
# crosshair's line there and went on up and to the right, past the edge of the head to the wall.
extends GdUnitTestSuite

## Built high above the sample map, so nothing else is in the way.
const SPOT := Vector3(0.0, 100.0, 0.0)
const STEP := 1.0 / 60.0

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
	_rig.set_process(false)


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


# One frame of the rig and then the engine's, so the arm, the host and the `Camera3D` follow.
func _frame() -> void:
	_rig.advance(STEP)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame


func _crosshair() -> Array[Vector3]:
	var centre := _camera.get_viewport().get_visible_rect().size / 2.0
	return [_camera.project_ray_origin(centre), _camera.project_ray_normal(centre)]


# A dressed character `distance` m straight ahead, facing the player, crouched or standing,
# and a wall 3 m behind it.
func _target(distance: float, crouched: bool) -> Character:
	_block(SPOT + Vector3(0.0, 2.0, -distance - 3.0), Vector3(20.0, 6.0, 0.4))
	var body := HitRange.target(_scene, SPOT + Vector3(0.0, 0.0, -distance))
	var scripted := ScriptedController.new()
	body.add_child(scripted)
	body.controller = scripted
	scripted.next.crouch = crouched
	# Lives through every shot, so each one meets a living, flinching body.
	var health := body.get_node("Health")
	health.max_value = 100000.0
	health.reset()
	return body


# Turns the rig until the crosshair's ray passes through `point` (a few rounds: the shoulder
# offset moves the ray's start as the view turns).
func _aim_at(point: Vector3) -> void:
	for _round in 8:
		var ray := _crosshair()
		var want := (point - ray[0]).normalized()
		var have := ray[1]
		_rig.yaw += rad_to_deg(atan2(-want.x, -want.z) - atan2(-have.x, -have.z))
		_rig.pitch -= rad_to_deg(asin(want.y) - asin(have.y))
		for _i in 6:
			await _frame()


# Holds aim with the crosshair on `point` (a function of the target's posed zones, read each
# round) and fires once: what the projectile met first and the zone of the hit, if any.
func _shoot_at(body: Character, point: Callable) -> Dictionary:
	InputSim.pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	for _i in 40:
		await _frame()
	var zones := HitRange.zones_of(body)
	for _round in 3:
		zones.follow_bones()
		await _aim_at(point.call(zones))
	var met := {}
	var records: Array[HitRecord] = []
	body.hit_received.connect(func(record: HitRecord) -> void: records.append(record))
	var rays: Array[PackedVector3Array] = []
	_player.weapon.fired.connect(
		func(shot: Projectile) -> void:
			rays.append(_player.aim_ray())
			shot.impacted.connect(
				func(collider: Node, at: Vector3, _normal: Vector3) -> void:
					if met.is_empty():
						met["collider"] = collider
						met["point"] = at
			)
	)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	for _i in 30:
		await _frame()
		if not met.is_empty():
			break
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
	return {
		"met": met,
		"zone": records[0].zone if not records.is_empty() else &"",
		"ray": rays[0] if not rays.is_empty() else PackedVector3Array(),
	}


# The head's middle moved `right` and `up` metres across the view.
func _on_head(right: float, up := 0.0) -> Callable:
	return func(zones: HitZones) -> Vector3:
		var basis := _camera.global_basis
		return zones.zone(&"head").global_position + basis.x * right + basis.y * up


func _assert_head(result: Dictionary, body: Character, label: String) -> void:
	var met: Dictionary = result["met"]
	var where := "%s: met %s, zone %s" % [label, met, result["zone"]]
	assert_bool(met.is_empty()).override_failure_message(where + " (nothing)").is_false()
	if met.is_empty():
		return
	assert_object(met["collider"]).override_failure_message(where).is_same(body)
	assert_str(String(result["zone"])).override_failure_message(where).is_equal("head")


func test_a_standing_character_2_m_away_is_hit_in_the_head_under_the_crosshair() -> void:
	var body := _target(2.0, false)
	_assert_head(await _shoot_at(body, _on_head(0.0)), body, "standing 2 m")


func test_a_standing_character_4_m_away_is_hit_in_the_head_under_the_crosshair() -> void:
	var body := _target(4.0, false)
	_assert_head(await _shoot_at(body, _on_head(0.0)), body, "standing 4 m")


func test_the_right_edge_of_the_head_2_m_away_is_hit() -> void:
	var body := _target(2.0, false)
	_assert_head(await _shoot_at(body, _on_head(0.08)), body, "standing 2 m, right edge")


func test_the_top_right_of_the_head_3_m_away_is_hit() -> void:
	var body := _target(3.0, false)
	_assert_head(await _shoot_at(body, _on_head(0.06, 0.06)), body, "standing 3 m, top right")


func test_a_crouched_characters_head_3_m_away_is_hit_at_its_right_edge() -> void:
	var body := _target(3.0, true)
	_assert_head(await _shoot_at(body, _on_head(0.08)), body, "crouched 3 m, right edge")


func test_a_crouched_characters_head_2_m_away_is_hit() -> void:
	var body := _target(2.0, true)
	_assert_head(await _shoot_at(body, _on_head(0.0)), body, "crouched 2 m")


func test_a_shot_just_beside_the_head_lands_on_the_wall_under_the_crosshair() -> void:
	var body := _target(3.0, false)
	var result := await _shoot_at(body, _on_head(-0.2))
	var met: Dictionary = result["met"]
	assert_bool(met.is_empty()).override_failure_message("nothing met").is_false()
	if met.is_empty():
		return
	assert_object(met["collider"]).override_failure_message("met %s" % [met]).is_not_same(body)
	# Where the crosshair's ray (the one the body fired along) meets the wall.
	var ray: PackedVector3Array = result["ray"]
	var wall_z := SPOT.z - 3.0 - 3.0 + 0.2
	var along := (wall_z - ray[0].z) / ray[1].z
	var under_crosshair := ray[0] + ray[1] * along
	(
		assert_float((met["point"] as Vector3).distance_to(under_crosshair))
		. override_failure_message("met %s, the crosshair is on %s" % [met, under_crosshair])
		. is_less(0.03)
	)
