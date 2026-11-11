# Dying and getting up, in the real physics world with simulated input: the Y key and the inspector
# checkbox kill and revive the character, a dead body ignores every gameplay input, getting up puts
# the body under the hips, and the key follows its export. How the ragdoll falls and moves is in
# test_ragdoll_physics.gd, the live exports of the Ragdoll node in test_ragdoll_live.gd.
extends GdUnitTestSuite

## The most ticks a dead body gets to come to rest (20 s).
const SETTLE_TICKS := 1200

var _arena: PlayArena
var _player: Player
var _ragdoll: CharacterRagdoll


func before_test() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3(0.0, 0.0, 0.0))
	_player.tuning = (
		(load("res://gameplay/player/player_tuning.tres") as CharacterTuning).duplicate()
	)
	_ragdoll = _player.ragdoll_body
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.release_all()


func _ticks(count: int) -> void:
	await InputSim.ticks(get_tree(), count)


func _press_y() -> void:
	InputSim.key(KEY_Y, true)
	await _ticks(2)
	InputSim.key(KEY_Y, false)
	await _ticks(1)


func test_the_character_the_player_and_the_ragdoll_pin_their_exports() -> void:
	var character_pins := {
		&"tuning": null,
		&"prone_tuning": null,
		&"slide_tuning": null,
		&"model": null,
		&"controller": null,
		&"weapon": null,
		&"loadout": null,
		&"ragdoll_body": null,
		&"ragdoll": false,
		&"ragdoll_by_command": true,
		&"vault_settings": null,
	}
	var body := auto_free(load("res://gameplay/character/character.gd").new()) as Character
	assert_array(ExportPins.differences(body, character_pins)).is_empty()
	assert_array(ExportPins.wrong_values(body, character_pins)).is_empty()
	# The human adds its own on top of the character's.
	var player_pins := character_pins.duplicate()
	player_pins.merge(
		{&"start_at_spawn": true, &"input_enabled": true, &"ragdoll_key": KEY_Y, &"inventory": null}
	)
	var fresh := auto_free(load("res://gameplay/player/player.gd").new()) as Player
	assert_array(ExportPins.differences(fresh, player_pins)).is_empty()
	assert_array(ExportPins.wrong_values(fresh, player_pins)).is_empty()
	var ragdoll_pins := {
		&"model": null,
		&"mass": 70.0,
		&"thickness": 1.0,
		&"joint_range": 1.0,
		&"hinge_passes": 6,
		&"cone_passes": 6,
		&"linear_damp": 0.1,
		&"angular_damp": 2.0,
		&"friction": 0.8,
		&"bounce": 0.0,
		&"carry_velocity": 1.0,
		&"pose_velocity": true,
		&"relax_gravity": 12.0,
		&"relax_time": 0.35,
		&"get_up_time": 0.4,
		&"max_active": 4,
		&"settle_time": 8.0,
		&"ragdoll_range": 0.0,
		&"editor_preview": true,
		&"collision_layer": PhysicsLayers.RAGDOLL,
		&"collision_mask": PhysicsLayers.RAGDOLL_MASK,
	}
	var ragdoll := auto_free(CharacterRagdoll.new()) as CharacterRagdoll
	assert_array(ExportPins.differences(ragdoll, ragdoll_pins)).is_empty()
	assert_array(ExportPins.wrong_values(ragdoll, ragdoll_pins)).is_empty()


func test_the_scene_wires_a_ragdoll_with_sixteen_bones_that_rest_while_alive() -> void:
	assert_object(_ragdoll).is_not_null()
	assert_int(_ragdoll.body_count()).is_equal(16)
	assert_bool(_ragdoll.is_active()).is_false()
	for bone in [&"pelvis", &"Head", &"hand_l", &"hand_r", &"foot_l", &"foot_r"]:
		assert_object(_ragdoll.body(bone)).is_not_null()


# A character that never dies never pays for its bones (gdstudio #926: 16 bodies and 33 nodes
# from the spawn, about 25 microseconds a frame each): they are made on the first death.
func test_a_living_character_carries_no_physical_bone_until_it_dies() -> void:
	var skeleton := _player.model.skeleton()
	await _ticks(30)
	assert_int(skeleton.find_children("*", "PhysicalBone3D", true, false).size()).is_equal(0)
	_player.die()
	await _ticks(2)
	assert_bool(_ragdoll.is_limp()).is_true()
	assert_int(skeleton.find_children("*", "PhysicalBone3D", true, false).size()).is_equal(16)
	_player.revive()
	await _ticks(60)
	# Made once: getting up keeps them for the next death.
	assert_int(skeleton.find_children("*", "PhysicalBone3D", true, false).size()).is_equal(16)


func test_y_kills_and_revives_and_the_checkbox_follows() -> void:
	var died := [0]
	var revived := [0]
	_player.died.connect(func() -> void: died[0] += 1)
	_player.revived.connect(func() -> void: revived[0] += 1)
	await _press_y()
	assert_int(_player.state).is_equal(Player.State.DEAD)
	assert_bool(_player.ragdoll).is_true()
	assert_bool(_ragdoll.is_limp()).is_true()
	assert_int(died[0]).is_equal(1)
	await _ticks(30)
	await _press_y()
	assert_bool(_player.is_dead()).is_false()
	assert_bool(_player.ragdoll).is_false()
	assert_bool(_ragdoll.is_limp()).is_false()
	assert_int(revived[0]).is_equal(1)


func test_the_inspector_checkbox_kills_and_revives() -> void:
	_player.ragdoll = true
	assert_bool(_player.is_dead()).is_true()
	assert_bool(_ragdoll.is_limp()).is_true()
	await _ticks(20)
	_player.ragdoll = false
	assert_bool(_player.is_dead()).is_false()
	await _ticks(2)
	assert_int(_player.state).is_not_equal(Player.State.DEAD)


func test_a_dead_body_ignores_every_gameplay_input() -> void:
	var shots := [0]
	_player.weapon.fired.connect(func(_p: Projectile) -> void: shots[0] += 1)
	_player.die()
	# Wait until every bone sleeps, not a fixed time: the pose at death is on the real clock, so
	# some falls are still sliding after three seconds and moved the hips with no key pressed.
	_ragdoll.settle_time = 1.0
	for _tick in SETTLE_TICKS:
		if _ragdoll.is_settled():
			break
		await get_tree().physics_frame
	assert_bool(_ragdoll.is_settled()).is_true()
	var spot := _player.global_position
	var hips := _ragdoll.hips()
	for key in [KEY_W, KEY_SPACE, KEY_SHIFT, KEY_C, KEY_E]:
		InputSim.key(key, true)
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await _ticks(45)
	assert_vector(_player.global_position).is_equal_approx(spot, Vector3.ONE * 0.001)
	assert_vector(_player.velocity).is_equal(Vector3.ZERO)
	assert_int(_player.state).is_equal(Player.State.DEAD)
	assert_bool(_player.aiming).is_false()
	assert_bool(_player.crouching).is_false()
	assert_int(shots[0]).is_equal(0)
	# Nothing pushes the ragdoll either: the hips stay where they came to rest.
	assert_float(_ragdoll.hips().distance_to(hips)).is_less(0.05)


func test_a_hit_does_nothing_to_a_dead_body() -> void:
	_player.die()
	var hits := [0]
	_player.took_hit.connect(func(_a: float, _s: Node3D) -> void: hits[0] += 1)
	_player.hit(1.0, null)
	await _ticks(2)
	assert_int(hits[0]).is_equal(0)
	assert_int(_player.state).is_equal(Player.State.DEAD)


func test_getting_up_puts_the_body_under_the_hips_facing_the_chest() -> void:
	InputSim.key(KEY_W, true)
	await _ticks(30)
	InputSim.key(KEY_W, false)
	_player.die()
	await _ticks(180)
	var hips := _ragdoll.hips()
	var facing := _ragdoll.facing()
	_player.revive()
	(
		assert_float(
			Vector2(_player.global_position.x - hips.x, _player.global_position.z - hips.z).length()
		)
		. is_less(0.01)
	)
	assert_float(_player.global_position.y).is_equal_approx(0.0, 0.02)
	var forward := Vector3.BACK.rotated(Vector3.UP, _player.facing)
	assert_float(forward.dot(facing)).is_greater(0.99)
	# The capsule collides again and the body stands on the floor.
	assert_bool((_player.get_node("%Body") as CollisionShape3D).disabled).is_false()
	await _ticks(10)
	assert_bool(_player.is_on_floor()).is_true()


func test_the_pose_blends_back_over_the_get_up_time() -> void:
	_ragdoll.get_up_time = 0.5
	_player.die()
	await _ticks(60)
	_player.revive()
	assert_bool(_ragdoll.is_active()).is_true()
	await _ticks(15)
	assert_bool(_ragdoll.is_active()).is_true()
	await _ticks(30)
	assert_bool(_ragdoll.is_active()).is_false()


func test_moving_after_getting_up_works() -> void:
	_player.die()
	await _ticks(60)
	_player.revive()
	var spot := _player.global_position
	InputSim.key(KEY_W, true)
	await _ticks(30)
	assert_float(spot.distance_to(_player.global_position)).is_greater(1.0)


func test_the_camera_target_follows_the_hips_and_returns() -> void:
	var target := _player.get_node("%CameraTarget") as Node3D
	InputSim.key(KEY_W, true)
	await _ticks(30)
	InputSim.key(KEY_W, false)
	_player.die()
	await _ticks(120)
	assert_float(target.global_position.distance_to(_ragdoll.hips() + Vector3.UP * 0.25)).is_less(
		0.05
	)
	_player.revive()
	assert_vector(target.position).is_equal_approx(
		Vector3(0.0, _player.tuning.camera_height, 0.0), Vector3.ONE * 0.001
	)


func test_teleport_revives_at_once() -> void:
	_player.die()
	await _ticks(30)
	_player.teleport(Vector3(3.0, 0.0, 3.0))
	assert_bool(_player.is_dead()).is_false()
	assert_bool(_ragdoll.is_active()).is_false()
	assert_vector(_player.global_position).is_equal(Vector3(3.0, 0.0, 3.0))


func test_the_key_follows_its_export_and_none_removes_it() -> void:
	_player.ragdoll_key = KEY_U
	InputSim.key(KEY_Y, true)
	await _ticks(2)
	InputSim.key(KEY_Y, false)
	assert_bool(_player.is_dead()).is_false()
	InputSim.key(KEY_U, true)
	await _ticks(2)
	InputSim.key(KEY_U, false)
	assert_bool(_player.is_dead()).is_true()
	_player.ragdoll_key = KEY_NONE
	assert_array(InputMap.action_get_events(Player.RAGDOLL_ACTION)).is_empty()
	InputSim.key(KEY_U, true)
	await _ticks(2)
	InputSim.key(KEY_U, false)
	assert_bool(_player.is_dead()).is_true()
	_player.ragdoll_key = KEY_Y


func test_the_input_switch_turns_the_key_off() -> void:
	_player.input_enabled = false
	await _press_y()
	assert_bool(_player.is_dead()).is_false()


func test_it_works_after_the_model_is_swapped_at_run_time() -> void:
	await _swap_to_male()
	assert_int(_ragdoll.body_count()).is_equal(16)
	assert_object(_ragdoll.body(&"pelvis").get_parent().get_parent()).is_same(
		_player.model.skeleton()
	)
	_player.die()
	await _ticks(180)
	assert_float(_ragdoll.hips().y).is_between(0.05, 0.35)


func _swap_to_male() -> void:
	var slot := _player.model
	var old := slot.rig()
	slot.remove_child(old)
	old.free()
	var male := (
		(load("res://assets/characters/mannequin/mannequin_male.glb") as PackedScene).instantiate()
	)
	slot.add_child(male)
	await _ticks(3)
