# The shot hull (gdstudio #1431): a shot meets a character first at a capsule a little wider and
# taller than the one it moves with, so a part the pose holds outside the moving capsule is hit: a
# crouched body's hips seen from the side, the head and chest while the body stands up. Movement
# never meets it, a dead body's hull is off, and a shot that passes between the parts flies on.
extends GdUnitTestSuite

## The thinnest round a weapon can fire (`WeaponDef.projectile_size`), metres.
const THIN_ROUND := 0.02

var _arena: PlayArena
var _player: Player
var _animation: CharacterAnimation
var _zones: HitZones
var _records: Array[HitRecord] = []


func before_test() -> void:
	_arena = auto_free(ImpactShots.world(self))
	_player = _arena.add_player(Vector3(0.0, 0.0, -4.0))
	_animation = _player.get_node("Animation")
	_zones = HitRange.zones_of(_player)
	_records.clear()
	_player.hit_received.connect(func(record: HitRecord) -> void: _records.append(record))
	CommandDriver.take(_player)
	_animation.set_throttled(true)
	await get_tree().physics_frame
	await get_tree().physics_frame


func after_test() -> void:
	AudioDrain.stop_all(_arena)


# Steps the body `count` ticks with `command`, the tree moved on with it (nothing else moves it).
func _steps(command: PlayerCommand, count: int, each := Callable()) -> void:
	var step := CommandDriver.tick_seconds()
	for tick in count:
		await get_tree().physics_frame
		_player.step(command, step)
		_animation.advance(step)
		if each.is_valid() and each.call(tick):
			return


func _crouch() -> PlayerCommand:
	var command := PlayerCommand.new()
	command.crouch = true
	return command


# Where `zone_name`'s part is drawn now.
func _part(zone_name: StringName) -> Vector3:
	_zones.follow_bones()
	return _zones.zone(zone_name).global_position


func _capsule() -> CapsuleShape3D:
	return (_player.get_node("%Body") as CollisionShape3D).shape as CapsuleShape3D


# A start 3 m out, level, from which a line to `centre` meets `zone_name` first and passes the
# moving capsule by (its closest point to the axis is outside the radius): empty when none does.
func _side_line(zone_name: StringName, centre: Vector3) -> Array[Vector3]:
	var off := centre - _player.global_position
	off.y = 0.0
	var across := off.normalized().cross(Vector3.UP)
	for side: Vector3 in [across, -across]:
		var from := centre + side * 3.0
		var found := _zones.find(from, centre)
		if not found.is_empty() and found.zone.zone == zone_name:
			return [from, (centre - from).normalized()]
	return []


func test_a_crouched_body_is_hit_at_its_hips_from_the_side() -> void:
	await _steps(_crouch(), 40)
	assert_int(_player.state).is_equal(Character.State.CROUCH)
	assert_str(String(_animation.body_state())).is_equal("crouch")
	var hips := _part(&"pelvis")
	var off := Vector2(hips.x - _player.global_position.x, hips.z - _player.global_position.z)
	# The case: the drawn hips are out past the moving capsule's surface.
	assert_float(off.length()).is_greater(_capsule().radius + THIN_ROUND / 2.0)
	var line := _side_line(&"pelvis", hips)
	assert_array(line).override_failure_message("no side sees the hips first").is_not_empty()
	if line.is_empty():
		return
	# A thin round, as a hitscan ray or the aim ray is: the template's 14 cm round reaches 7 cm past
	# the capsule by its own width and met these hips before.
	var shot := ImpactShots.fire(_arena, line[0], hips + line[1] * 0.5)
	shot.size = THIN_ROUND
	await ImpactShots.land(get_tree(), shot)
	assert_int(_records.size()).override_failure_message("the shot flew past the hips").is_equal(1)
	if not _records.is_empty():
		assert_str(String(_records[0].zone)).is_equal("pelvis")


func test_a_body_standing_up_is_hit_at_its_drawn_head() -> void:
	await _steps(_crouch(), 40)
	# Let go: the pose is upright long before the capsule has grown to the standing height.
	var head_over := [0.0]
	var over := func(_tick: int) -> bool:
		_zones.follow_bones()
		var head := _zones.zone(&"head").global_position.y - _player.global_position.y
		head_over[0] = head - _capsule().height
		return head_over[0] > 0.05
	await _steps(PlayerCommand.new(), 12, over)
	(
		assert_float(head_over[0])
		. override_failure_message("the head never rose over the capsule")
		. is_greater(0.05)
	)
	if head_over[0] <= 0.05:
		return
	assert_float(_player._crouch_amount).is_greater(0.0)
	var head := _part(&"head")
	var from := head + Vector3(0.0, 0.0, 3.0)
	await ImpactShots.shoot(get_tree(), _arena, from, head - Vector3(0.0, 0.0, 0.5))
	assert_int(_records.size()).override_failure_message("the shot flew over the capsule").is_equal(
		1
	)
	if not _records.is_empty():
		assert_str(String(_records[0].zone)).is_equal("head")


func test_a_shot_between_the_parts_still_flies_on_past_the_hull() -> void:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 3.0, 0.4)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0.0, 1.5, -7.0)
	_arena.add_child(wall)
	await get_tree().physics_frame
	# Inside the hull's width and beside the moving capsule: the hull is met, no part is.
	var hull := ShotHull.of(_player)
	var at := _player.global_position + Vector3(_capsule().radius + hull.margin * 0.5, 1.0, 0.0)
	assert_bool(_zones.find(at + Vector3.BACK * 3.0, at + Vector3.FORWARD).is_empty()).is_true()
	var met: Array[Node] = []
	var shot := ImpactShots.fire(_arena, at + Vector3(0.0, 0.0, 3.0), at)
	shot.impacted.connect(func(c: Node, _p: Vector3, _n: Vector3) -> void: met.append(c))
	await ImpactShots.land(get_tree(), shot)
	assert_array(_records).is_empty()
	assert_array(met).is_equal([wall])


func test_the_hull_follows_the_stance_and_movement_never_meets_it() -> void:
	var hull := ShotHull.of(_player)
	assert_object(hull).is_not_null()
	assert_object(_zones.hull).is_same(hull)
	assert_object(HitZones.of(hull)).is_same(_zones)
	assert_int(hull.collision_layer).is_equal(PhysicsLayers.SHOT_HULLS)
	assert_int(hull.collision_mask).is_equal(0)
	var masks := {
		"a character's capsule": PhysicsLayers.CHARACTER_MASK,
		"a prop": PhysicsLayers.PROP_MASK,
		"a ragdoll bone": PhysicsLayers.RAGDOLL_MASK,
		"the camera's arm": PhysicsLayers.CAMERA_MASK,
		"a pickup or a door's sensor": PhysicsLayers.CHARACTER_SENSOR_MASK,
		"a trigger zone": PhysicsLayers.TRIGGER_MASK,
		"a shot's mark": PhysicsLayers.SURFACE_MASK,
	}
	for what: String in masks:
		assert_int(masks[what] & PhysicsLayers.SHOT_HULLS).override_failure_message(what).is_equal(
			0
		)
	assert_int(PhysicsLayers.SHOT_MASK & PhysicsLayers.SHOT_HULLS).is_not_equal(0)
	var shape := hull.capsule()
	assert_float(shape.radius).is_equal_approx(_capsule().radius + hull.margin, 0.001)
	assert_float(shape.height).is_equal_approx(_player.tuning.height + hull.head_room, 0.001)
	await _steps(_crouch(), 40)
	assert_float(shape.height).is_equal_approx(_capsule().height + hull.head_room, 0.001)
	# Standing up, the hull is standing height at once, while the capsule grows.
	await _steps(PlayerCommand.new(), 2)
	assert_float(_capsule().height).is_less(_player.tuning.height - 0.05)
	assert_float(shape.height).is_equal_approx(_player.tuning.height + hull.head_room, 0.001)


func test_a_dead_body_has_its_hull_off_and_getting_up_puts_it_back() -> void:
	var hull := ShotHull.of(_player)
	_player.die()
	assert_int(hull.collision_layer).is_equal(0)
	_player.revive()
	assert_int(hull.collision_layer).is_equal(PhysicsLayers.SHOT_HULLS)


func test_the_shooter_never_meets_its_own_hull() -> void:
	# The weapon's aim ray from inside the hull goes on to what is ahead.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 3.0, 0.4)
	shape.shape = box
	wall.add_child(shape)
	wall.position = _player.global_position + Vector3(0.0, 1.5, -5.0)
	_arena.add_child(wall)
	await get_tree().physics_frame
	var origin := _player.global_position + Vector3(0.4, 1.4, 0.0)
	var point := _player.weapon.aim_point(origin, Vector3.FORWARD)
	assert_float(point.z).is_equal_approx(wall.position.z + 0.2, 0.01)


func test_the_shot_hull_pins_its_exports() -> void:
	var pins := {&"margin": 0.12, &"head_room": 0.25}
	var hull := auto_free(ShotHull.new()) as ShotHull
	assert_array(ExportPins.differences(hull, pins)).is_empty()
	assert_array(ExportPins.wrong_values(hull, pins)).is_empty()
