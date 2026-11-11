# Two clients, each in a view with a map of its own, and one game server over a real socket. Ada
# acts; every action is asserted from Bo's screen, on the puppet Bo's `RemotePlayers` draws of
# her (the same `player.tscn`, `Player.make_puppet()`): walk, sprint, crouch, aim (the pose and
# the barrel's pitch), jump and land, face, stop. The puppet stands as tall and faces the way her
# own body does (to the millimetre), never takes Bo's camera, and a late joiner sees both.
extends GdUnitTestSuite

var _rig: OnlineRig
var _ada: NetClient
var _bo: NetClient


func before_test() -> void:
	_rig = auto_free(OnlineRig.new(false))
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_ada = await _rig.join("Ada")
	_bo = await _rig.join("Bo")
	assert_object(_ada).is_not_null()
	assert_object(_bo).is_not_null()
	await _rig.wait(20)
	# On the open ground south of the dais, where a sprint along -X meets nothing for 14 m.
	_put(_ada, Vector3(3.0, 0.0, 15.0), -PI / 2.0)
	_put(_bo, Vector3(3.0, 0.0, 11.0), -PI / 2.0)
	await _rig.wait(30)


func test_each_client_draws_the_other_and_keeps_its_own_camera() -> void:
	var seen_by_bo := _bo.remote_players.puppet_at(_ada.slot)
	var seen_by_ada := _ada.remote_players.puppet_at(_bo.slot)
	assert_object(seen_by_bo).is_not_null()
	assert_object(seen_by_ada).is_not_null()
	assert_array(_bo.remote_players.slots()).is_equal([_ada.slot])
	assert_str(_bo.remote_players.name_of(_ada.slot)).is_equal("Ada")
	for index in _rig.clients.size():
		var client := _rig.clients[index]
		var drawn := _rig.views[index].get_camera_3d()
		var rig := client.player.get_parent() as PlayerRig
		assert_object(drawn).is_same(rig.camera_rig.camera)
		for puppet: Player in client.remote_players.get_children():
			assert_bool(puppet.is_in_group(Player.GROUP)).is_false()
			assert_int(puppet.collision_layer).is_equal(0)
			assert_object(puppet.controller).is_null()
	assert_bool(seen_by_bo.is_puppet).is_true()
	assert_bool(_ada.player.is_puppet).is_false()


func test_the_puppet_stands_as_tall_and_faces_as_the_body_does() -> void:
	await _act(_walking(Vector3.LEFT), 30)
	await _act(_standing(), 60)
	var body := _ada.player
	var puppet := _puppet()
	assert_float(puppet.global_position.distance_to(body.global_position)).is_less(0.006)
	assert_float(absf(angle_difference(puppet.facing, body.facing))).is_less(0.001)
	assert_float(absf(puppet.body_height() - body.body_height())).is_less(0.001)
	var model_offset := body.global_transform.affine_inverse() * body.model.global_transform
	var puppet_offset := puppet.global_transform.affine_inverse() * puppet.model.global_transform
	(
		assert_bool(model_offset.is_equal_approx(puppet_offset))
		. override_failure_message("model %s, puppet's %s" % [model_offset, puppet_offset])
		. is_true()
	)
	var head_body := _head_height(body)
	var head_puppet := _head_height(puppet)
	assert_float(head_body).is_greater(1.0)
	assert_float(absf(head_puppet - head_body)).is_less(0.001)
	var facing_body := body.model.global_basis.z
	var facing_puppet := puppet.model.global_basis.z
	assert_float(facing_body.angle_to(facing_puppet)).is_less(0.002)


func test_walk_sprint_and_stop_show_on_the_other_screen() -> void:
	var walk := _walking(Vector3.LEFT)
	walk.walk = true
	await _act(walk, 50)
	_assert_same_motion("walk")
	assert_int(_puppet().state).is_equal(Character.State.WALK)
	var sprint := _walking(Vector3.LEFT)
	sprint.sprint = true
	await _act(sprint, 50)
	_assert_same_motion("sprint")
	assert_int(_puppet().state).is_equal(Character.State.RUN)
	assert_bool(_puppet().is_sprinting()).is_true()
	await _act(_standing(), 40)
	_assert_same_motion("stop")
	assert_int(_puppet().state).is_equal(Character.State.IDLE)
	assert_float(_puppet().ground_speed()).is_less(0.05)


func test_crouch_shows_on_the_other_screen() -> void:
	var crouch := _standing()
	crouch.crouch = true
	await _act(crouch, 50)
	var puppet := _puppet()
	assert_bool(puppet.crouching).is_true()
	assert_int(puppet.state).is_equal(Character.State.CROUCH)
	assert_str(_animation(puppet).body_state()).is_equal(_animation(_ada.player).body_state())
	assert_float(absf(puppet.body_height() - _ada.player.body_height())).is_less(0.001)


func test_aim_and_the_barrel_pitch_show_on_the_other_screen() -> void:
	var aim := _standing()
	aim.aim = true
	aim.pitch = 0.35
	await _act(aim, 50)
	var puppet := _puppet()
	var body := _ada.player
	assert_bool(puppet.aiming).is_true()
	assert_float(puppet.aim_amount).is_equal_approx(body.aim_amount, 0.001)
	assert_float(absf(puppet.view_pitch - body.view_pitch)).is_less(SnapshotCodec.PITCH_STEP)
	var weights_body := _animation(body).pistol_weights()
	var weights_puppet := _animation(puppet).pistol_weights()
	assert_float(weights_puppet.y).is_equal_approx(weights_body.y, 0.02)
	assert_float(_animation(puppet).aim_pitch()).is_equal_approx(_animation(body).aim_pitch(), 1.0)
	# The barrel points up on both screens, by the same angle to within two degrees.
	var barrel_body := _barrel_pitch(body)
	var barrel_puppet := _barrel_pitch(puppet)
	prints("barrel pitch: body %.2f deg, puppet %.2f deg" % [barrel_body, barrel_puppet])
	assert_float(barrel_body).is_greater(8.0)
	assert_float(absf(barrel_puppet - barrel_body)).is_less(2.0)


func test_a_jump_and_its_landing_show_on_the_other_screen() -> void:
	var seen: Dictionary[int, bool] = {}
	var jump := _walking(Vector3.LEFT)
	jump.jump = true
	jump.jump_pressed = true
	_rig.controllers[0].next = jump
	var start_y := _puppet().global_position.y
	var highest := start_y
	for _frame in 90:
		await get_tree().physics_frame
		_rig.controllers[0].next.jump = false
		seen[_puppet().state] = true
		highest = maxf(highest, _puppet().global_position.y)
	assert_bool(seen.has(Character.State.JUMP)).is_true()
	assert_bool(seen.has(Character.State.FALL) or seen.has(Character.State.LAND)).is_true()
	assert_float(highest - start_y).is_greater(0.4)


func test_turning_shows_on_the_other_screen() -> void:
	for heading in [0.0, PI / 2.0, -2.5]:
		var look := Vector3(-sin(heading), 0.0, -cos(heading))
		await _act(_walking(look, look), 40)
		await _act(_standing(heading), 20)
		var facing_body := _ada.player.facing
		var facing_puppet := _puppet().facing
		(
			assert_float(absf(angle_difference(facing_puppet, facing_body)))
			. override_failure_message(
				"heading %.2f: %.4f vs %.4f" % [heading, facing_puppet, facing_body]
			)
			. is_less(0.002)
		)


func test_a_late_joiner_sees_everyone_already_there() -> void:
	await _act(_walking(Vector3.RIGHT), 30)
	await _act(_standing(), 20)
	var cy := await _rig.join("Cy")
	assert_object(cy).is_not_null()
	await _rig.wait(20)
	assert_array(cy.remote_players.slots()).is_equal([_ada.slot, _bo.slot])
	assert_str(cy.remote_players.name_of(_ada.slot)).is_equal("Ada")
	var ada_there := cy.remote_players.puppet_at(_ada.slot)
	assert_float(ada_there.global_position.distance_to(_ada.player.global_position)).is_less(0.01)
	# And the two already there draw the newcomer.
	assert_object(_ada.remote_players.puppet_at(cy.slot)).is_not_null()
	assert_object(_bo.remote_players.puppet_at(cy.slot)).is_not_null()


func test_a_player_who_leaves_is_taken_off_the_other_screen() -> void:
	_ada.link.close()
	(
		assert_bool(await _rig.until(func() -> bool: return _bo.remote_players.slots().is_empty()))
		. is_true()
	)


# --- Helpers ---


# Puts `client`'s body at `spot` facing `heading` on the server and on its own screen.
func _put(client: NetClient, spot: Vector3, heading: float) -> void:
	_rig.server_body(client).teleport(spot, heading)
	client.player.teleport(spot, heading)
	var stand := PlayerCommand.new()
	stand.yaw = heading - PI
	_rig.controllers[_rig.clients.find(client)].next = stand


func _puppet() -> Player:
	return _bo.remote_players.puppet_at(_ada.slot)


func _animation(character: Character) -> CharacterAnimation:
	return character.get_node("Animation") as CharacterAnimation


# Holds `command` as Ada's for `frames` physics frames (its presses on the first only).
func _act(command: PlayerCommand, frames: int) -> void:
	_rig.controllers[0].next = command
	await _rig.wait(frames)


func _walking(direction: Vector3, look := Vector3.ZERO) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.set_from_world(direction, look)
	return command


func _standing(heading := NAN) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.yaw = _ada.player.view_yaw if is_nan(heading) else heading
	return command


# The ground speed and the state Bo draws against Ada's own (the puppet is a tenth of a second
# behind, so both are read once the move is steady).
func _assert_same_motion(what: String) -> void:
	var puppet := _puppet()
	var body := _ada.player
	(
		assert_float(puppet.ground_speed())
		. override_failure_message(
			(
				"%s: puppet %.2f m/s, body %.2f m/s"
				% [what, puppet.ground_speed(), body.ground_speed()]
			)
		)
		. is_equal_approx(body.ground_speed(), 0.1 * maxf(body.ground_speed(), 0.5))
	)
	assert_int(puppet.state).override_failure_message(what).is_equal(body.state)
	assert_str(_animation(puppet).body_state()).is_equal(_animation(body).body_state())


# The head bone's height over the body's feet, metres.
func _head_height(character: Character) -> float:
	var skeleton := character.model.skeleton()
	var bone := skeleton.find_bone("head")
	if bone < 0:
		bone = skeleton.find_bone("Head")
	var rest := skeleton.global_transform * skeleton.get_bone_global_rest(bone)
	return rest.origin.y - character.global_position.y


# The barrel's look up, degrees (its muzzle's -Z, or +Z when that faces back along the facing).
func _barrel_pitch(character: Character) -> float:
	var muzzle := character.weapon.muzzle
	var forward := -muzzle.global_basis.z
	return rad_to_deg(asin(clampf(forward.normalized().y, -1.0, 1.0)))
