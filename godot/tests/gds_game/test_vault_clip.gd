# `VaultClip` of `gds_game` on its own, and a vault that `VaultProbe` times by one: the frame a
# vault starts at for a distance, where the model's root is through the clip's contacts, the
# landing drawn in when there is no room, and the capsule's path still over the top. The probe's
# measuring is `test_vault_probe_alone.gd`; a game's suite measures the hands of its own clips
# (3D Third Person's `test_vault_contacts.gd`).
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


# A clip keyed like 3D Third Person's low vault: over a 0.8 m box 0.4 m deep at 4 m/s, the root
# 1.3 m before the face at its start.
func _low_clip() -> VaultClip:
	var clip := VaultClip.new()
	clip.planted_hands = {&"hand_l": Vector3(0.27, 0.036, 0.12)}
	clip.hand_release = {&"hand_l": 0.375}
	return clip


func test_a_vault_clip_starts_at_the_frame_that_fits_the_distance() -> void:
	var clip := _low_clip()
	# 1.3 m away is the clip's own start; nearer starts later; never later than the lead allows.
	assert_float(clip.start_time(1.3)).is_equal_approx(0.0, 0.0001)
	assert_float(clip.start_time(2.0)).is_equal(0.0)
	assert_float(clip.start_time(0.9)).is_equal_approx(0.1, 0.0001)
	assert_float(clip.start_time(0.34)).is_equal_approx(clip.hand_plant - clip.lead, 0.0001)
	assert_float(clip.keyed_landing()).is_equal_approx(1.4668, 0.001)


func test_a_vault_clips_root_is_where_the_clip_had_it_while_a_hand_is_planted() -> void:
	var clip := _low_clip()
	for near: float in [0.4, 0.9, 1.3, 1.9]:
		var start := clip.start_time(near)
		var label := "from %.1f m" % near
		(
			assert_float(clip.forward_at(start, start, near, 2.0))
			. override_failure_message(label)
			. is_equal_approx(-near, 0.0001)
		)
		# From the plant to the push the root is the clip's own, so the hand does not slide.
		for step in 11:
			var time := lerpf(clip.hand_plant, clip.push_off, step / 10.0)
			(
				assert_float(clip.forward_at(time, start, near, 2.0))
				. override_failure_message(label)
				. is_equal_approx(clip.keyed_forward(time), 0.0001)
			)
			assert_float(clip.raised(time, start)).override_failure_message(label).is_equal(1.0)
		assert_float(clip.forward_at(clip.land, start, near, 2.0)).is_equal_approx(2.0, 0.0001)
		assert_float(clip.raised(start, start)).override_failure_message(label).is_equal(0.0)
		assert_float(clip.raised(clip.land, start)).is_equal(0.0)
		# The inverse finds the time the root is at a place.
		var over := clip.time_at(-0.2, start, near, 2.0)
		assert_float(clip.forward_at(over, start, near, 2.0)).is_equal_approx(-0.2, 0.0001)


func test_a_vault_timed_by_its_clip_keeps_the_model_level_and_the_capsule_over_the_top() -> void:
	_settings.low_clip = _low_clip()
	_settings.landing_margin = 1.13
	for height: float in [0.5, 0.8, 0.95]:
		var wall := _obstacle(height, 0.4)
		var plan := await _measure()
		var label := "%.2f m" % height
		assert_int(plan.kind).override_failure_message(label).is_equal(VaultPlan.Kind.VAULT)
		assert_bool(plan.has_clip_timing()).override_failure_message(label).is_true()
		var clip := _settings.low_clip
		# 0.6 m before the face (and the radius): the clip starts where its root is that far.
		assert_float(plan.near).is_equal_approx(0.6 + RADIUS, 0.02)
		assert_float(plan.clip_start).is_equal_approx(clip.start_time(plan.near), 0.0001)
		assert_float(plan.clip_rate).is_equal_approx(1.0, 0.0001)
		assert_float(plan.duration).is_equal_approx(clip.land - plan.clip_start, 0.0001)
		assert_float(plan.clip_time(1.0)).is_equal_approx(clip.land, 0.0001)
		# The model's root starts and lands on the feet path.
		assert_vector(plan.root_at(clip, 0.0)).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.001)
		assert_vector(plan.root_at(clip, 1.0)).is_equal_approx(
			plan.end_point(), Vector3.ONE * 0.001
		)
		# At the hand plant it is where the clip had it before the face, lifted by the difference
		# to the clip's box and no more; the feet path is over the top there.
		var share := (clip.hand_plant - plan.clip_start) / (plan.duration * plan.clip_rate)
		var root := plan.root_at(clip, share)
		assert_float(-root.z - plan.near).override_failure_message(label).is_equal_approx(
			clip.keyed_forward(clip.hand_plant), 0.001
		)
		assert_float(root.y).override_failure_message(label).is_equal_approx(height - 0.8, 0.011)
		for step in 101:
			var at := plan.position_at(step / 100.0)
			if -at.z > 0.6 + RADIUS - RADIUS and -at.z < 0.6 + RADIUS + 0.4 + RADIUS:
				(
					assert_float(at.y)
					. override_failure_message("%s share %d" % [label, step])
					. is_greater(height - 0.01)
				)
		var copy := VaultPlan.new().from_array(plan.to_array())
		assert_vector(copy.root_at(clip, 0.5)).is_equal(plan.root_at(clip, 0.5))
		wall.free()


func test_a_landing_with_no_room_is_drawn_in_to_the_farthest_free_one() -> void:
	_settings.landing_margin = 1.13
	_obstacle(0.8, 0.4)
	var open := await _measure()
	var far := 0.6 + RADIUS + 0.4
	assert_float(-open.end_point().z - far).is_equal_approx(RADIUS + 1.13, 0.01)
	# A tall wall 1.5 m past the far face: the full landing would end inside it.
	var behind := _block(Vector3(0.0, 1.5, -(far + 1.5 + 0.1)), Vector3(3.0, 3.0, 0.2), false)
	var drawn_in := await _measure()
	assert_int(drawn_in.kind).is_equal(VaultPlan.Kind.VAULT)
	var past := -drawn_in.end_point().z - far
	assert_float(past).is_less(1.5 - RADIUS + 0.03)
	assert_float(past).is_greater_equal(RADIUS + _settings.min_landing_margin - 0.01)
	behind.free()
	# A low wall whose near edge is under the body's rim at the full landing: the landing is not
	# its edge (the feet would hang in the air) but the floor before it.
	var low := _block(Vector3(0.0, 0.45, -(far + 1.7 + 0.2)), Vector3(3.0, 0.9, 0.4))
	var before_it := await _measure()
	assert_int(before_it.kind).is_equal(VaultPlan.Kind.VAULT)
	assert_float(before_it.end_point().y).is_equal_approx(0.0, 0.01)
	assert_float(-before_it.end_point().z - far).is_less(1.7 - RADIUS + 0.03)
	low.free()
	# With only the one landing allowed, the same wall leaves none.
	_settings.min_landing_margin = 1.13
	_block(Vector3(0.0, 1.5, -(far + 1.5 + 0.1)), Vector3(3.0, 3.0, 0.2), false)
	var none := await _measure()
	assert_int(none.kind).is_not_equal(VaultPlan.Kind.VAULT)


func test_a_faster_entry_plays_the_clip_faster_inside_the_range() -> void:
	_settings.low_clip = _low_clip()
	_settings.landing_margin = 1.13
	_obstacle(0.8, 0.4)
	var slow := await _measure(Vector3.FORWARD, 0.0)
	var fast := await _measure(Vector3.FORWARD, 9.0)
	assert_float(slow.clip_rate).is_equal_approx(_settings.clip_rate_range.x, 0.0001)
	assert_float(fast.clip_rate).is_equal_approx(_settings.clip_rate_range.y, 0.0001)
	assert_float(fast.duration).is_less(slow.duration)


func test_an_obstacle_with_a_clip_of_its_own_is_timed_by_the_shares() -> void:
	_settings.low_clip = _low_clip()
	var wall := _obstacle(0.8, 0.4)
	(wall.get_child(1) as Vaultable).vault_clip = &"other/Roll"
	var plan := await _measure()
	assert_int(plan.kind).is_equal(VaultPlan.Kind.VAULT)
	assert_bool(plan.has_clip_timing()).is_false()
	assert_float(plan.times[1]).is_equal_approx(_settings.plant_at, 0.0001)
