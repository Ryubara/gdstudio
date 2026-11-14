# Hit zones (#876): a real projectile that meets a character's capsule finds the body part in its
# path, the part scales the damage, health runs out into a death, a shot between the parts flies
# on, and nothing but a shot's second test ever meets a zone.
extends GdUnitTestSuite

var _arena: PlayArena
var _target: Character
var _zones: HitZones
var _records: Array[HitRecord] = []


func before_test() -> void:
	_arena = auto_free(ImpactShots.world(self))
	_target = HitRange.target(_arena, Vector3(0.0, 0.0, -4.0))
	_zones = HitRange.zones_of(_target)
	_records.clear()
	_target.hit_received.connect(func(record: HitRecord) -> void: _records.append(record))
	await InputSim.ticks(get_tree(), 6)
	HitRange.freeze(_target)
	await InputSim.ticks(get_tree(), 2)


func after_test() -> void:
	AudioDrain.stop_all(_arena)


func test_the_dressed_character_has_eleven_zones_on_their_own_layer() -> void:
	var names: Array[StringName] = []
	for part in _zones.zones():
		names.append(part.zone)
		assert_int(_target.model.skeleton().find_bone(part.bone)).is_greater_equal(0)
	(
		assert_array(names)
		. contains_exactly_in_any_order(
			[
				&"head",
				&"chest",
				&"pelvis",
				&"arm_l",
				&"forearm_l",
				&"arm_r",
				&"forearm_r",
				&"thigh_l",
				&"shin_l",
				&"thigh_r",
				&"shin_r",
			]
		)
	)
	assert_int(_zones.collision_layer).is_equal(PhysicsLayers.HIT_ZONES)
	assert_int(_zones.collision_mask).is_equal(0)


func test_a_shot_on_each_zone_hits_that_zone_and_scales_the_damage() -> void:
	Health.of(_target).max_value = 100000.0
	Health.of(_target).value = 100000.0
	var projectile := load(ImpactShots.PROJECTILE).instantiate() as Projectile
	var damage := projectile.damage
	projectile.free()
	for part in _zones.zones():
		var line := HitRange.line_to(_target, part)
		(
			assert_array(line)
			. override_failure_message("no side sees %s first" % part.zone)
			. is_not_empty()
		)
		if line.is_empty():
			continue
		_records.clear()
		await HitRange.shoot(get_tree(), _arena, line[0], line[1])
		assert_int(_records.size()).override_failure_message("%s: no hit" % part.zone).is_equal(1)
		if _records.is_empty():
			continue
		var record := _records[0]
		assert_str(String(record.zone)).is_equal(String(part.zone))
		assert_str(String(record.bone)).is_equal(String(part.bone))
		assert_float(record.damage).is_equal_approx(damage * part.damage_multiplier, 0.001)
		assert_float(record.direction.dot(line[1])).is_greater(0.99)
	# The head counts most, a limb less than the trunk.
	assert_float(_zones.zone(&"head").damage_multiplier).is_greater(1.0)
	assert_float(_zones.zone(&"forearm_l").damage_multiplier).is_less(1.0)


func test_health_falls_by_each_hit_and_the_character_dies_at_zero() -> void:
	var line := HitRange.line_to(_target, _zones.zone(&"chest"))
	var healths: Array[float] = []
	_target.health_changed.connect(func(value: float) -> void: healths.append(value))
	var deaths := [0]
	_target.died.connect(func() -> void: deaths[0] += 1)
	for shot in 3:
		await HitRange.shoot(get_tree(), _arena, line[0], line[1])
	# 34 a chest shot: 66, 32, then dead.
	assert_array(healths).is_equal([66.0, 32.0, 0.0])
	assert_bool(_target.is_dead()).is_true()
	assert_int(deaths[0]).is_equal(1)
	assert_bool(_records[-1].killed).is_true()
	assert_bool(_records[0].killed).is_false()


func test_getting_up_gives_the_health_back() -> void:
	_target.take_hit(HitRecord.shot(250.0, &"chest", &"spine_03", Vector3.INF, Vector3.ZERO, 0.0))
	assert_bool(_target.is_dead()).is_true()
	assert_float(_target.health).is_equal(0.0)
	_target.revive()
	assert_float(_target.health).is_equal(_target.max_health)


func test_with_health_off_a_hit_takes_nothing() -> void:
	Health.of(_target).enabled = false
	_target.take_hit(HitRecord.shot(500.0, &"head", &"Head", Vector3.INF, Vector3.ZERO, 0.0))
	assert_float(_target.health).is_equal(_target.max_health)
	assert_bool(_target.is_dead()).is_false()


func test_with_zones_off_a_shot_hits_the_whole_body() -> void:
	_zones.enabled = false
	var line := HitRange.line_to(_target, _zones.zone(&"head"))
	_zones.enabled = false
	await HitRange.shoot(get_tree(), _arena, line[0], line[1])
	assert_int(_records.size()).is_equal(1)
	assert_str(String(_records[0].zone)).is_empty()
	assert_float(_records[0].damage).is_equal_approx(34.0, 0.001)


func test_a_shot_between_the_parts_flies_on_to_the_wall() -> void:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 3.0, 0.4)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0.0, 1.5, -7.0)
	_arena.add_child(wall)
	await get_tree().physics_frame
	# A line from the front through the capsule (0.34 m) that meets no part: beside the legs.
	var at := _gap()
	assert_bool(at.is_finite()).override_failure_message("no gap beside the legs").is_true()
	var met: Array[Node] = []
	var shot := ImpactShots.fire(_arena, at + Vector3(0.0, 0.0, 3.0), at)
	shot.impacted.connect(func(c: Node, _p: Vector3, _n: Vector3) -> void: met.append(c))
	await ImpactShots.land(get_tree(), shot)
	assert_array(_records).is_empty()
	assert_array(met).is_equal([wall])


# gdstudio #1412: a crouch holds the hips behind the body's middle, out past the capsule's surface;
# a shot from behind met the capsule after it had crossed them, the second test looked on from
# there and found nothing, and the shot flew on through the drawn hips. The test now starts
# `look_back` before the touch.
func test_a_part_in_front_of_the_capsule_is_hit_on_the_way_in() -> void:
	var part := _zones.zone(&"pelvis")
	var skeleton := _target.model.skeleton()
	_zones.follow_bones()
	# The pelvis moved 0.5 m toward the shooter, past the capsule's front (0.34 m).
	var wanted := _target.global_position + Vector3(0.0, 0.9, 0.5)
	var basis := skeleton.global_basis * skeleton.get_bone_global_pose(part.bone_index).basis
	part.offset += basis.inverse() * (wanted - part.global_position)
	_zones.follow_bones()
	assert_float(part.global_position.distance_to(wanted)).is_less(0.01)
	await ImpactShots.shoot(get_tree(), _arena, wanted + Vector3(0.0, 0.0, 3.0), wanted)
	assert_int(_records.size()).override_failure_message("the shot flew on").is_equal(1)
	if not _records.is_empty():
		assert_str(String(_records[0].zone)).is_equal("pelvis")


# A point inside the capsule's width, seen from the front, on no part's line.
func _gap() -> Vector3:
	for height: float in [0.3, 0.45, 0.6]:
		for step in 6:
			var side := 0.17 + step * 0.02
			var at := _target.global_position + Vector3(side, height, 0.0)
			var clear := true
			# Three lines 3 cm apart, so the shot is not at a part's very edge.
			for nudge: float in [-0.03, 0.0, 0.03]:
				var line := at + Vector3(nudge, 0.0, 0.0)
				if not _zones.find(line + Vector3.BACK * 3.0, line + Vector3.FORWARD).is_empty():
					clear = false
			if clear:
				return at
	return Vector3.INF


func test_a_character_moved_since_the_last_shot_is_found_where_it_is_now() -> void:
	# The zones are put on the bones only when a shot asks (`find`); a body that moved since must
	# be met there in the same tick, not where the last shot left its zones (gdstudio #1198).
	_zones.follow_bones()
	await InputSim.ticks(get_tree(), 2)
	_target.global_position += Vector3(1.5, 0.0, 0.0)
	var chest := _target.global_position + Vector3.UP * 1.2
	var found := _zones.find(chest + Vector3(0.0, 0.0, 2.0), chest - Vector3(0.0, 0.0, 2.0))
	assert_bool(found.is_empty()).override_failure_message("no zone met").is_false()
	if not found.is_empty():
		assert_float((found.point as Vector3).x).is_equal_approx(chest.x, 0.3)


func test_the_zones_cost_nothing_until_a_shot_reaches_the_capsule() -> void:
	# Placed once, the zones stay where they were while the character walks on: nothing moves
	# them every tick.
	_zones.follow_bones()
	var head := _zones.zone(&"head").global_position
	_target.teleport(_target.global_position + Vector3(2.0, 0.0, 0.0))
	await InputSim.ticks(get_tree(), 10)
	assert_vector(_zones.zone(&"head").global_position).is_equal_approx(head, Vector3.ONE * 0.001)
	_zones.follow_bones()
	assert_float(_zones.zone(&"head").global_position.x - head.x).is_equal_approx(2.0, 0.05)


func test_movement_the_camera_and_areas_never_meet_a_zone() -> void:
	var masks := {
		"a character's capsule": PhysicsLayers.CHARACTER_MASK,
		"a prop": PhysicsLayers.PROP_MASK,
		"a ragdoll bone": PhysicsLayers.RAGDOLL_MASK,
		"the camera's arm": PhysicsLayers.CAMERA_MASK,
		"a pickup or a door's sensor": PhysicsLayers.CHARACTER_SENSOR_MASK,
		"a trigger zone": PhysicsLayers.TRIGGER_MASK,
		"a shot's flight and the aim ray": PhysicsLayers.SHOT_MASK,
	}
	for what: String in masks:
		assert_int(masks[what] & PhysicsLayers.HIT_ZONES).override_failure_message(what).is_equal(0)
	assert_int(_target.collision_mask & PhysicsLayers.HIT_ZONES).is_equal(0)
	assert_int(_target.ragdoll_body.collision_mask & PhysicsLayers.HIT_ZONES).is_equal(0)
	# In the world: a ray of every other mask through the head finds nothing (the capsule and its
	# shot hull are excluded), a ray of the zones' own mask finds the head.
	_zones.follow_bones()
	var centre := _zones.zone(&"head").global_position
	var space := _arena.get_world_3d().direct_space_state
	var others := (
		PhysicsLayers.CHARACTER_MASK
		| PhysicsLayers.CAMERA_MASK
		| PhysicsLayers.TRIGGER_MASK
		| PhysicsLayers.SHOT_MASK
	)
	var query := PhysicsRayQueryParameters3D.create(
		centre + Vector3(0.0, 0.0, 2.0), centre, others, ShotHull.rids_of(_target)
	)
	query.collide_with_areas = true
	var met := space.intersect_ray(query)
	assert_bool(met.is_empty()).override_failure_message(str(met)).is_true()
	query.collision_mask = PhysicsLayers.HIT_ZONE_MASK
	assert_object(space.intersect_ray(query).get("collider")).is_same(_zones)
	# A character walks through the zones of another standing where it walks.
	var walker := HitRange.target(_arena, centre + Vector3(0.0, -1.6, 2.0))
	await InputSim.ticks(get_tree(), 4)
	_zones.follow_bones()
	walker.controller = null
	var through := walker.move_and_collide(Vector3(0.0, 0.0, -4.0), true)
	assert_object(through).is_null()


func test_a_record_survives_the_wire_in_a_few_bytes() -> void:
	var record := HitRecord.shot(
		102.0, &"head", &"Head", Vector3(1.5, 1.7, -4.25), Vector3(0.0, -0.1, -1.0), 40.0
	)
	var bytes := record.encode()
	assert_int(bytes.size()).is_less_equal(48)
	var back := HitRecord.decode(bytes)
	assert_float(back.damage).is_equal(102.0)
	assert_str(String(back.zone)).is_equal("head")
	assert_str(String(back.bone)).is_equal("Head")
	assert_vector(back.point).is_equal_approx(record.point, Vector3.ONE * 0.0001)
	assert_vector(back.direction).is_equal_approx(record.direction, Vector3.ONE * 0.0001)
	assert_float(back.strength).is_equal(40.0)
	assert_object(HitRecord.decode(bytes.slice(0, 20))).is_null()
	# A blow has no point, and that survives too.
	assert_bool(HitRecord.decode(HitRecord.blow(5.0).encode()).has_point()).is_false()


func test_the_hit_zones_pin_their_exports() -> void:
	var zone_pins := {
		&"zone": &"body",
		&"bone": &"",
		&"offset": Vector3.ZERO,
		&"damage_multiplier": 1.0,
		&"enabled": true,
	}
	var part := auto_free(HitZone.new()) as HitZone
	assert_array(ExportPins.differences(part, zone_pins)).is_empty()
	assert_array(ExportPins.wrong_values(part, zone_pins)).is_empty()
	var zones_pins := {
		&"receiver": null,
		&"model": null,
		&"ragdoll": null,
		&"enabled": true,
		&"ray_length": 1.2,
		&"look_back": 0.5,
		&"hull": null,
	}
	var holder := auto_free(HitZones.new()) as HitZones
	assert_array(ExportPins.differences(holder, zones_pins)).is_empty()
	assert_array(ExportPins.wrong_values(holder, zones_pins)).is_empty()
