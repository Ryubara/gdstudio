# Vaulting and mantling with the real player in the real physics world, driven by simulated input
# (the jump key, the pad's A, a finger on the touch Jump button) and by commands alone (a bot):
# it vaults over each height of wall that carries a `Vaultable`, refuses one without it, one too
# high or with no room to land, mantles where it should, never ends inside geometry, and a body put
# back mid-vault crosses on the same path. The probe alone is the kit's `test_vault_probe_alone.gd`.
extends GdUnitTestSuite

## Where the wall's near face is, ahead of the player (along -Z).
const FACE := 2.5
## The touch layer the template's `main.tscn` uses.
const TOUCH := "res://ui/touch/third_person_touch_controls.tscn"

var _arena: PlayArena
var _player: Player
var _settings: VaultSettings
var _states: Array[Character.State] = []
var _highest := 0.0
var _overlaps := 0


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	_player.tuning = (
		(load("res://gameplay/player/player_tuning.tres") as CharacterTuning).duplicate()
	)
	_settings = (load("res://gameplay/character/vault_settings.tres") as VaultSettings).duplicate()
	_player.vault_settings = _settings
	_states = []
	_highest = 0.0
	_overlaps = 0
	_player.state_changed.connect(func(state: Character.State) -> void: _states.append(state))
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	InputSim.pad_button(JOY_BUTTON_A, false)
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


# A new arena and player for the next round of a test.
func _reset() -> void:
	after_test()
	_arena.free()
	await before_test()


# A wall `height` high and `depth` deep across the way, its near face `FACE` ahead; with
# `vaultable` it carries the component.
func _wall(height: float, depth: float, vaultable := true) -> StaticBody3D:
	var wall := _arena.add_block(
		Vector2(0.0, -(FACE + depth / 2.0)), Vector3(4.0, height, depth), height
	)
	if vaultable:
		wall.add_child(Vaultable.new())
	return wall


# Holds W until the body is `gap` metres from the face, then sends `press` (a callable that
# presses jump) and keeps W held for `ticks` more, watching every tick.
func _run_and_press(press: Callable, gap := 0.9, ticks := 90) -> void:
	InputSim.key(KEY_W, true)
	for _tick in 120:
		await get_tree().physics_frame
		if -_player.global_position.z >= FACE - _player.tuning.radius - gap:
			break
	press.call(true)
	for tick in ticks:
		await get_tree().physics_frame
		_watch()
		if tick == 3:
			press.call(false)
	InputSim.key(KEY_W, false)


# Keeps the highest the feet went and counts ticks the capsule was inside something.
func _watch() -> void:
	_highest = maxf(_highest, _player.global_position.y)
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = _player.tuning.radius - 0.02
	capsule.height = _player.body_height() - 0.04
	query.shape = capsule
	query.transform = Transform3D(
		Basis.IDENTITY, _player.global_position + Vector3.UP * (_player.body_height() / 2.0)
	)
	query.collision_mask = _player.collision_mask
	query.exclude = [_player.get_rid()]
	if not _player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		_overlaps += 1


func _space_key(down: bool) -> void:
	InputSim.key(KEY_SPACE, down)


func _pad_a(down: bool) -> void:
	InputSim.pad_button(JOY_BUTTON_A, down)


func test_the_jump_key_vaults_over_each_height_and_lands_beyond() -> void:
	for height: float in [0.5, 0.8, 1.0, 1.2]:
		_wall(height, 0.4)
		await _run_and_press(_space_key)
		var label := "%.1f m" % height
		assert_bool(_states.has(Character.State.VAULT)).override_failure_message(label).is_true()
		assert_float(_highest).override_failure_message(label).is_greater(height)
		# Landed on the floor beyond the far face, running on, and never inside the wall.
		assert_float(-_player.global_position.z).override_failure_message(label).is_greater(
			FACE + 0.4 + _player.tuning.radius
		)
		assert_float(_player.global_position.y).override_failure_message(label).is_equal_approx(
			0.0, 0.02
		)
		assert_int(_overlaps).override_failure_message(label).is_equal(0)
		assert_bool(_player.is_on_floor()).override_failure_message(label).is_true()
		await _reset()


func test_the_pad_vaults_too() -> void:
	_wall(0.9, 0.4)
	await _run_and_press(_pad_a)
	assert_bool(_states.has(Character.State.VAULT)).is_true()
	assert_float(-_player.global_position.z).is_greater(FACE + 0.4)


func test_a_finger_on_the_touch_jump_button_vaults() -> void:
	var touch := (load(TOUCH) as PackedScene).instantiate() as TouchControls
	_arena.add_child(touch)
	await get_tree().process_frame
	var jump_index := -1
	for button in touch.buttons_root.get_children():
		if (button as TouchButton).action == &"jump":
			jump_index = button.get_index()
	assert_int(jump_index).is_greater_equal(0)
	var at := touch.button_center(jump_index)
	_wall(0.9, 0.4)
	var finger := func(down: bool) -> void:
		var event := InputEventScreenTouch.new()
		event.index = 4
		event.position = at
		event.pressed = down
		touch._input(event)
	await _run_and_press(finger)
	assert_bool(_states.has(Character.State.VAULT)).is_true()
	assert_float(-_player.global_position.z).is_greater(FACE + 0.4)


func test_a_wall_without_the_component_is_jumped_not_vaulted() -> void:
	_wall(0.9, 0.4, false)
	await _run_and_press(_space_key)
	assert_bool(_states.has(Character.State.VAULT)).is_false()
	assert_bool(_states.has(Character.State.MANTLE)).is_false()
	assert_bool(_states.has(Character.State.JUMP)).is_true()


func test_a_wall_too_high_is_neither_vaulted_nor_mantled() -> void:
	_wall(2.6, 0.4)
	await _run_and_press(_space_key)
	assert_bool(_states.has(Character.State.VAULT)).is_false()
	assert_bool(_states.has(Character.State.MANTLE)).is_false()
	assert_float(-_player.global_position.z).is_less(FACE)


func test_a_deep_block_is_mantled_and_the_body_stands_on_top() -> void:
	for height: float in [1.0, 1.7]:
		_wall(height, 12.0)
		await _run_and_press(_space_key, 0.9, 120)
		var label := "%.1f m" % height
		assert_bool(_states.has(Character.State.MANTLE)).override_failure_message(label).is_true()
		assert_float(_player.global_position.y).override_failure_message(label).is_equal_approx(
			height, 0.03
		)
		assert_int(_overlaps).override_failure_message(label).is_equal(0)
		await _reset()


func test_no_room_to_land_mantles_and_with_no_mantle_is_refused() -> void:
	var wall := _wall(1.0, 0.5)
	# A tall wall right behind it leaves no room to land.
	_arena.add_block(Vector2(0.0, -(FACE + 0.5 + 0.3)), Vector3(4.0, 3.0, 0.2), 3.0)
	await _run_and_press(_space_key)
	assert_bool(_states.has(Character.State.VAULT)).is_false()
	assert_bool(_states.has(Character.State.MANTLE)).is_true()
	assert_float(_player.global_position.y).is_equal_approx(1.0, 0.03)
	assert_int(_overlaps).is_equal(0)
	await _reset()
	wall = _wall(1.0, 0.5)
	(wall.get_child(1) as Vaultable).allow_mantle = false
	_arena.add_block(Vector2(0.0, -(FACE + 0.5 + 0.3)), Vector3(4.0, 3.0, 0.2), 3.0)
	await _run_and_press(_space_key)
	assert_bool(_states.has(Character.State.VAULT)).is_false()
	assert_bool(_states.has(Character.State.MANTLE)).is_false()
	assert_str(_player.vault_motion.last_refusal).is_equal(VaultPlan.NO_LANDING)


func test_a_bot_vaults_by_commands_alone_and_sprinting_vaults_with_the_automatic_trigger() -> void:
	_wall(0.9, 0.4)
	CommandDriver.take(_player)
	var players: Array[Player] = [_player]
	var walk := CommandDriver.walking(Vector3.FORWARD)
	await CommandDriver.run(get_tree(), players, walk, 30)
	var press := walk.clone()
	press.jump = true
	press.jump_pressed = true
	await CommandDriver.run(get_tree(), players, press, 60, func(_tick: int) -> void: _watch())
	assert_bool(_states.has(Character.State.VAULT)).is_true()
	assert_int(_overlaps).is_equal(0)
	# The automatic trigger: a sprint into the wall, no button.
	await _reset()
	_settings.trigger = VaultSettings.Trigger.AUTO_ON_SPRINT
	_wall(0.9, 0.4)
	CommandDriver.take(_player)
	players = [_player]
	var sprint := CommandDriver.walking(Vector3.FORWARD)
	sprint.sprint = true
	await CommandDriver.run(get_tree(), players, sprint, 90)
	assert_bool(_states.has(Character.State.VAULT)).is_true()
	assert_float(-_player.global_position.z).is_greater(FACE + 0.4)


func test_a_jump_with_the_automatic_trigger_only_is_a_jump() -> void:
	_settings.trigger = VaultSettings.Trigger.AUTO_ON_SPRINT
	_wall(0.9, 0.4)
	await _run_and_press(_space_key)
	assert_bool(_states.has(Character.State.VAULT)).is_false()


func test_a_body_put_back_mid_vault_crosses_on_the_same_path() -> void:
	_wall(1.0, 0.4)
	CommandDriver.take(_player)
	var players: Array[Player] = [_player]
	var walk := CommandDriver.walking(Vector3.FORWARD)
	await CommandDriver.run(get_tree(), players, walk, 30)
	var press := walk.clone()
	press.jump = true
	press.jump_pressed = true
	await CommandDriver.run(get_tree(), players, press, 6)
	assert_int(_player.state).is_equal(Character.State.VAULT)
	var kept := _player.state_snapshot()
	var hold := walk.clone()
	hold.jump = true
	var first: Array[Vector3] = []
	await CommandDriver.run(
		get_tree(), players, hold, 40, func(_t: int) -> void: first.append(_player.global_position)
	)
	_player.restore(kept)
	var second: Array[Vector3] = []
	await CommandDriver.run(
		get_tree(), players, hold, 40, func(_t: int) -> void: second.append(_player.global_position)
	)
	for index in first.size():
		assert_vector(second[index]).override_failure_message("tick %d" % index).is_equal_approx(
			first[index], Vector3.ONE * 0.0001
		)


func test_aim_drops_for_the_vault_and_no_shot_leaves() -> void:
	_wall(0.9, 0.4)
	var shots := []
	_player.weapon.fired.connect(func(shot: Projectile) -> void: shots.append(shot))
	CommandDriver.take(_player)
	var players: Array[Player] = [_player]
	var walk := CommandDriver.walking(Vector3.FORWARD)
	await CommandDriver.run(get_tree(), players, walk, 30)
	var press := walk.clone()
	press.jump_pressed = true
	press.aim = true
	press.fire = true
	press.fire_pressed = true
	await CommandDriver.run(get_tree(), players, press, 8)
	assert_int(_player.state).is_equal(Character.State.VAULT)
	assert_bool(_player.aiming).is_false()
	assert_array(shots).is_empty()


func test_the_clip_is_the_vault_or_the_climb_and_the_obstacles_own_wins() -> void:
	var animation := _player.get_node("Animation") as CharacterAnimation
	var wall := _wall(0.9, 0.4)
	await _run_and_press(_space_key, 0.9, 10)
	assert_str(str(animation.last_action())).is_equal(str(animation.vault_clip))
	await _reset()
	animation = _player.get_node("Animation") as CharacterAnimation
	_wall(1.0, 3.0)
	await _run_and_press(_space_key, 0.9, 10)
	assert_str(str(animation.last_action())).is_equal(str(animation.mantle_clip))
	await _reset()
	animation = _player.get_node("Animation") as CharacterAnimation
	wall = _wall(0.9, 0.4)
	(wall.get_child(1) as Vaultable).vault_clip = CharacterClips.ROLL
	await _run_and_press(_space_key, 0.9, 10)
	assert_str(str(animation.last_action())).is_equal(str(CharacterClips.ROLL))


func test_the_cooldown_follows_a_crossing_and_a_press_right_after_landing_chains() -> void:
	_wall(0.9, 0.4)
	CommandDriver.take(_player)
	var players: Array[Player] = [_player]
	var walk := CommandDriver.walking(Vector3.FORWARD)
	await CommandDriver.run(get_tree(), players, walk, 30)
	var press := walk.clone()
	press.jump_pressed = true
	var after_end: Array[float] = []
	var motion := _player.vault_motion
	var watch := func(_tick: int) -> void:
		if _states.has(Character.State.VAULT) and not motion.is_active() and after_end.is_empty():
			after_end.append(motion.cooldown)
	await CommandDriver.run(get_tree(), players, press, 60, watch)
	assert_array(after_end).is_not_empty()
	assert_float(after_end[0]).is_greater(0.0)
	# A second wall just past the landing: a press during the cooldown still vaults it (only the
	# automatic trigger waits).
	await _reset()
	_wall(0.9, 0.4)
	var second := _arena.add_block(Vector2(0.0, -(FACE + 2.3)), Vector3(4.0, 0.9, 0.4), 0.9)
	second.add_child(Vaultable.new())
	CommandDriver.take(_player)
	players = [_player]
	var started: Array[VaultPlan] = []
	_player.vault_motion.started.connect(func(plan: VaultPlan) -> void: started.append(plan))
	await CommandDriver.run(get_tree(), players, walk, 30)
	await CommandDriver.run(get_tree(), players, press, 1)
	var motion_now := _player.vault_motion
	assert_bool(motion_now.is_active()).is_true()
	for _tick in 90:
		if not motion_now.is_active():
			break
		await CommandDriver.run(get_tree(), players, walk, 1)
	# Just landed: the cooldown runs, and a press now vaults the second wall.
	assert_float(motion_now.cooldown).is_greater(0.0)
	# Pressed on the tick after the landing: a new plan, though the state stays `VAULT`.
	await CommandDriver.run(get_tree(), players, press, 60)
	assert_int(started.size()).is_equal(2)
	assert_float(-_player.global_position.z).is_greater(FACE + 2.5)


func test_no_settings_never_vaults() -> void:
	_player.vault_settings = null
	_wall(0.9, 0.4)
	await _run_and_press(_space_key)
	assert_bool(_states.has(Character.State.VAULT)).is_false()
