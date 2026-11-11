# `Vaultable`, `VaultProbe` and `VaultPlan` of `gds_game` on their own: a floor, boxes of several
# heights and depths built in code, a capsule body, and the probe asked what it would do. A game's
# suites drive a real character over its own obstacles (3D Third Person's
# `test_character_vault.gd`).
extends GdUnitTestSuite

const RADIUS := 0.34
const HEIGHT := 1.8

var _world: Node3D
var _body: CharacterBody3D
var _settings: VaultSettings


func before_test() -> void:
	_settings = VaultSettings.new()
	_world = auto_free(Node3D.new())
	add_child(_world)
	_block(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0), false)
	_body = CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	shape.shape = capsule
	shape.position.y = HEIGHT / 2.0
	_body.add_child(shape)
	_world.add_child(_body)
	await get_tree().physics_frame
	await get_tree().physics_frame


# A box `size` at `centre` (a StaticBody3D); with `vaultable`, a `Vaultable` child.
func _block(centre: Vector3, size: Vector3, vaultable := true) -> StaticBody3D:
	var block := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	block.add_child(shape)
	block.position = centre
	if vaultable:
		block.add_child(Vaultable.new())
	_world.add_child(block)
	return block


# A wall `height` high and `depth` deep, its near face 0.6 m ahead of the body (along -Z).
func _obstacle(height: float, depth: float, vaultable := true) -> StaticBody3D:
	var near := 0.6 + RADIUS
	return _block(
		Vector3(0.0, height / 2.0, -(near + depth / 2.0)), Vector3(3.0, height, depth), vaultable
	)


func _measure(direction := Vector3.FORWARD, speed := 4.0) -> VaultPlan:
	await get_tree().physics_frame
	return VaultProbe.measure(_body, Vector3.ZERO, direction, RADIUS, HEIGHT, speed, _settings)


func test_a_low_thin_wall_is_vaulted_at_its_measured_height_and_depth() -> void:
	for height: float in [0.5, 0.8, 1.0, 1.2]:
		var wall := _obstacle(height, 0.4)
		var plan := await _measure()
		assert_int(plan.kind).override_failure_message("%.1f m" % height).is_equal(
			VaultPlan.Kind.VAULT
		)
		assert_float(plan.height).is_equal_approx(height, 0.01)
		assert_float(plan.depth).is_equal_approx(0.4, 0.02)
		assert_object(plan.collider).is_same(wall)
		# The high clip from its height up (a measured 1.0 m reads a hair under or over it, by engine).
		assert_bool(plan.high).is_equal(plan.height >= _settings.high_vault_above)
		# Lands on the floor beyond the far face, clear of it by the body's radius and the margin.
		var land := plan.end_point()
		assert_float(land.y).is_equal_approx(0.0, 0.01)
		assert_float(-land.z).is_greater(0.6 + RADIUS + 0.4 + RADIUS)
		wall.free()


func test_the_path_passes_over_the_top_and_meets_the_contact_times() -> void:
	_obstacle(1.0, 0.4)
	var plan := await _measure()
	var over := plan.position_at(_settings.plant_at)
	assert_float(over.y).is_equal_approx(1.0 + _settings.foot_clearance, 0.01)
	var past := plan.position_at(_settings.clear_at)
	assert_float(past.y).is_equal_approx(1.0 + _settings.foot_clearance, 0.01)
	assert_vector(plan.position_at(0.0)).is_equal(Vector3.ZERO)
	assert_vector(plan.position_at(1.0)).is_equal(plan.end_point())
	# Every point of the way, the feet are above the top while over the obstacle.
	for step in 101:
		var at := plan.position_at(step / 100.0)
		if -at.z > 0.6 + RADIUS - RADIUS and -at.z < 0.6 + RADIUS + 0.4 + RADIUS:
			assert_float(at.y).override_failure_message("share %d" % step).is_greater(0.99)


func test_one_clip_time_for_many_heights_and_the_time_follows_the_speed() -> void:
	_obstacle(0.6, 0.3)
	var slow := await _measure(Vector3.FORWARD, 0.0)
	var fast := await _measure(Vector3.FORWARD, 9.0)
	assert_float(slow.duration).is_greater(fast.duration)
	assert_float(fast.duration).is_greater_equal(_settings.min_vault_time)
	assert_float(slow.duration).is_less_equal(_settings.max_vault_time)


func test_an_object_without_the_component_is_never_crossed() -> void:
	_obstacle(0.8, 0.4, false)
	var plan := await _measure()
	assert_int(plan.kind).is_equal(VaultPlan.Kind.NONE)
	assert_str(plan.refusal).is_equal(VaultPlan.NOT_VAULTABLE)


func test_too_low_is_left_to_the_step_and_the_jump() -> void:
	_obstacle(0.3, 0.4)
	var plan := await _measure()
	assert_str(plan.refusal).is_equal(VaultPlan.TOO_LOW)


func test_a_deep_obstacle_is_mantled_and_the_body_stands_on_top() -> void:
	_obstacle(1.0, 2.0)
	var plan := await _measure()
	assert_int(plan.kind).is_equal(VaultPlan.Kind.MANTLE)
	assert_float(plan.depth).is_equal(INF)
	var stand := plan.end_point()
	assert_float(stand.y).is_equal_approx(1.0, 0.01)
	assert_float(-stand.z).is_greater(0.6 + RADIUS + RADIUS)


func test_a_high_wall_is_mantled_and_one_too_high_is_refused() -> void:
	var wall := _obstacle(1.7, 0.4)
	var plan := await _measure()
	assert_int(plan.kind).is_equal(VaultPlan.Kind.MANTLE)
	assert_bool(plan.high).is_true()
	wall.free()
	_obstacle(2.6, 0.4)
	plan = await _measure()
	assert_int(plan.kind).is_equal(VaultPlan.Kind.NONE)
	assert_str(plan.refusal).is_equal(VaultPlan.TOO_HIGH)


func test_no_landing_room_mantles_and_with_no_mantle_is_refused() -> void:
	var wall := _obstacle(0.9, 0.4)
	# A tall block right behind the far face: no room to land.
	_block(Vector3(0.0, 1.5, -(0.6 + RADIUS + 0.4 + 0.3)), Vector3(3.0, 3.0, 0.2), false)
	var plan := await _measure()
	assert_int(plan.kind).is_equal(VaultPlan.Kind.MANTLE)
	(wall.get_child(1) as Vaultable).allow_mantle = false
	plan = await _measure()
	assert_int(plan.kind).is_equal(VaultPlan.Kind.NONE)
	assert_str(plan.refusal).is_equal(VaultPlan.NO_LANDING)


func test_a_drop_deeper_than_max_drop_is_no_landing() -> void:
	# A parapet at the edge of a pit: the floor ends at the wall's far face.
	for child in _world.get_children():
		if child is StaticBody3D:
			child.free()
	_block(Vector3(0.0, -0.5, 5.0), Vector3(40.0, 1.0, 11.0), false)
	var wall := _obstacle(0.9, 0.4)
	(wall.get_child(1) as Vaultable).allow_mantle = false
	var plan := await _measure()
	assert_str(plan.refusal).is_equal(VaultPlan.NO_LANDING)


func test_a_low_ceiling_over_the_path_is_no_room() -> void:
	var wall := _obstacle(0.9, 0.4)
	(wall.get_child(1) as Vaultable).allow_mantle = false
	_block(Vector3(0.0, 2.3, -1.2), Vector3(3.0, 0.2, 2.0), false)
	var plan := await _measure()
	assert_str(plan.refusal).is_equal(VaultPlan.NO_ROOM)


func test_an_oblique_approach_and_a_face_not_allowed_are_refused() -> void:
	var wall := _obstacle(0.8, 0.4)
	var plan := await _measure(Vector3(-1.0, 0.0, -1.0).normalized())
	assert_str(plan.refusal).is_equal(VaultPlan.TOO_OBLIQUE)
	var straight := await _measure(Vector3(-0.3, 0.0, -1.0).normalized())
	assert_int(straight.kind).is_equal(VaultPlan.Kind.VAULT)
	# The crossing goes square across the face, whatever the approach within the limit.
	assert_vector(straight.forward).is_equal_approx(Vector3.FORWARD, Vector3.ONE * 0.01)
	(wall.get_child(1) as Vaultable).faces = Vaultable.Face.NEGATIVE_Z
	plan = await _measure()
	assert_str(plan.refusal).is_equal(VaultPlan.FACE_NOT_ALLOWED)
	(wall.get_child(1) as Vaultable).faces = Vaultable.Face.POSITIVE_Z
	plan = await _measure()
	assert_int(plan.kind).is_equal(VaultPlan.Kind.VAULT)


func test_the_permissions_and_overrides_of_the_component() -> void:
	var wall := _obstacle(0.8, 0.4)
	var marker := wall.get_child(1) as Vaultable
	marker.allow_vault = false
	var plan := await _measure()
	assert_int(plan.kind).is_equal(VaultPlan.Kind.MANTLE)
	marker.allow_vault = true
	marker.height_override = 1.25
	plan = await _measure()
	assert_float(plan.height).is_equal_approx(1.25, 0.001)
	assert_bool(plan.high).is_true()
	marker.height_override = 0.0
	marker.depth_override = 1.5
	plan = await _measure()
	assert_int(plan.kind).is_equal(VaultPlan.Kind.MANTLE)


func test_nothing_ahead_or_too_far() -> void:
	var plan := await _measure()
	assert_str(plan.refusal).is_equal(VaultPlan.NOTHING_AHEAD)
	_block(Vector3(0.0, 0.4, -3.0), Vector3(3.0, 0.8, 0.4))
	plan = await _measure()
	assert_str(plan.refusal).is_equal(VaultPlan.NOTHING_AHEAD)


func test_the_component_is_found_on_the_body_beside_it_or_by_a_property() -> void:
	var holder := Node3D.new()
	var body := StaticBody3D.new()
	holder.add_child(body)
	var marker := Vaultable.new()
	holder.add_child(marker)
	_world.add_child(holder)
	assert_object(Vaultable.find(body)).is_same(marker)
	var lone: StaticBody3D = auto_free(StaticBody3D.new())
	assert_object(Vaultable.find(lone)).is_null()
	assert_object(Vaultable.find(null)).is_null()


func test_a_slow_entry_below_min_vault_speed_mantles() -> void:
	_settings.min_vault_speed = 2.0
	_obstacle(0.8, 0.4)
	var plan := await _measure(Vector3.FORWARD, 0.5)
	assert_int(plan.kind).is_equal(VaultPlan.Kind.MANTLE)
	plan = await _measure(Vector3.FORWARD, 3.0)
	assert_int(plan.kind).is_equal(VaultPlan.Kind.VAULT)


func test_a_plan_survives_its_plain_values() -> void:
	_obstacle(0.9, 0.4)
	var plan := await _measure()
	var copy := VaultPlan.new().from_array(plan.to_array())
	for step in 11:
		assert_vector(copy.position_at(step / 10.0)).is_equal(plan.position_at(step / 10.0))
	assert_float(copy.duration).is_equal(plan.duration)


func test_every_export_of_the_component_and_the_settings_has_its_default_pinned() -> void:
	var marker: Vaultable = auto_free(Vaultable.new())
	var marker_pins := {
		&"allow_vault": true,
		&"allow_mantle": true,
		&"faces": Vaultable.ALL_FACES,
		&"height_override": 0.0,
		&"depth_override": 0.0,
		&"vault_clip": &"",
		&"mantle_clip": &"",
	}
	assert_array(ExportPins.differences(marker, marker_pins)).is_empty()
	assert_array(ExportPins.wrong_values(marker, marker_pins)).is_empty()
	var settings_pins := {
		&"trigger": VaultSettings.Trigger.PRESS_JUMP,
		&"auto_min_speed": 5.5,
		&"min_vault_speed": 0.0,
		&"cooldown": 0.25,
		&"detect_distance": 0.7,
		&"detect_ahead_time": 0.15,
		&"max_approach_angle": 35.0,
		&"top_probe_radius": 0.08,
		&"max_top_slope": 30.0,
		&"min_vault_height": 0.45,
		&"max_vault_height": 1.3,
		&"high_vault_above": 1.0,
		&"max_vault_depth": 0.9,
		&"foot_clearance": 0.12,
		&"landing_margin": 0.3,
		&"max_drop": 1.2,
		&"crossing_speed": 4.0,
		&"min_vault_time": 0.45,
		&"max_vault_time": 0.9,
		&"exit_speed_share": 0.85,
		&"plant_at": 0.3,
		&"clear_at": 0.7,
		&"min_mantle_height": 0.45,
		&"max_mantle_height": 2.0,
		&"high_mantle_above": 1.25,
		&"mantle_base_time": 0.45,
		&"mantle_time_per_metre": 0.5,
		&"mantle_top_at": 0.7,
		&"mantle_inset": 0.1,
		&"drop_aim": true,
	}
	assert_array(ExportPins.differences(_settings, settings_pins)).is_empty()
	assert_array(ExportPins.wrong_values(_settings, settings_pins)).is_empty()


func test_a_component_with_nothing_allowed_warns() -> void:
	var marker: Vaultable = auto_free(Vaultable.new())
	marker.allow_vault = false
	marker.allow_mantle = false
	marker.faces = 0
	assert_int(marker._get_configuration_warnings().size()).is_equal(2)
