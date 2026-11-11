# The `Weapon` aims along a ray it is handed and steps when it is told: `fire(origin, direction)`
# and `aim_point(origin, direction)` give what the weapon gave while it read the camera itself
# (`CameraAim`, the old formula kept as a fixture), a weapon with no muzzle fires from beside its
# shooter, and the cooldown is counted by `tick()`, never by a clock.
extends GdUnitTestSuite

const WEAPON := "res://gameplay/weapon/weapon.tscn"

var _arena: PlayArena
var _player: Player
var _camera: Camera3D
var _players: Array[Player] = []


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	CommandDriver.take(_player)
	_players = [_player]
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 1.3, 3.0)
	_arena.add_child(_camera)
	_camera.make_current()
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	AudioDrain.stop_all(_arena)


func _weapon() -> Weapon:
	return _player.weapon


func _ready_to_fire() -> void:
	_weapon().make_ready()


# A weapon of its own in the arena, with no muzzle.
func _bare_weapon() -> Weapon:
	var weapon := load(WEAPON).instantiate() as Weapon
	weapon.position = Vector3(5.0, 1.0, 5.0)
	_arena.add_child(weapon)
	return weapon


func test_a_ray_gives_the_aim_point_and_the_shot_the_camera_formula_gave() -> void:
	# A wall close behind the character, a block ahead of it and open floor.
	_arena.add_block(Vector2(0.0, 1.2), Vector3(8.0, 4.0, 0.4), 4.0)
	_arena.add_block(Vector2(1.5, -9.0), Vector3(2.0, 3.0, 2.0), 3.0)
	await InputSim.ticks(get_tree(), 2)
	var poses: Array[Transform3D] = []
	for yaw: float in [0.0, 25.0, -40.0, 90.0, 150.0, 180.0, -120.0]:
		for pitch: float in [-35.0, -8.0, 0.0, 20.0, 60.0]:
			var basis := Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0))
			# Behind the character along its own view, a little to the side, as a shoulder
			# camera sits; at 180 degrees the lens is in front of the character, and at 0 it
			# is behind the wall at the character's back.
			poses.append(
				Transform3D(basis, Vector3(0.0, 1.4, 0.0) + basis * Vector3(0.4, 0.2, 3.0))
			)
	var compared := 0
	for pose in poses:
		_camera.global_transform = pose
		_camera.force_update_transform()
		var ray := CameraAim.crosshair_ray(_camera)
		var old_point := CameraAim.aim_point(_weapon())
		var old_way := CameraAim.direction_from(_weapon(), _weapon().muzzle.global_position)
		(
			assert_vector(_weapon().aim_point(ray[0], ray[1]))
			. override_failure_message("aim point at %s" % pose)
			. is_equal_approx(old_point, Vector3.ONE * 0.0001)
		)
		_ready_to_fire()
		var shot := _weapon().fire(ray[0], ray[1])
		assert_object(shot).is_not_null()
		(
			assert_vector(shot.velocity.normalized())
			. override_failure_message("shot at %s" % pose)
			. is_equal_approx(old_way, Vector3.ONE * 0.0001)
		)
		assert_vector(shot.global_position).is_equal(_weapon().muzzle.global_position)
		shot.free()
		compared += 1
	assert_int(compared).is_equal(35)


func test_a_point_behind_the_muzzle_shoots_along_the_ray() -> void:
	# A thin wall between the character's chest and its outstretched gun: what the ray meets
	# is nearer than the muzzle, and a shot turned to it would fly backwards.
	var command := CommandDriver.walking(Vector3.ZERO, Vector3.FORWARD)
	command.aim = true
	await CommandDriver.run(get_tree(), _players, command, 40)
	_arena.add_block(Vector2(0.0, -0.5), Vector3(4.0, 3.0, 0.2), 3.0)
	await InputSim.ticks(get_tree(), 4)
	var along := Vector3.FORWARD
	var start := Vector3(0.3, 1.3, 3.0)
	var point := _weapon().aim_point(start, along)
	assert_float(point.z).is_equal_approx(-0.4, 0.01)
	assert_float(_weapon().muzzle.global_position.z).is_less(point.z - 0.05)
	_ready_to_fire()
	var shot := _weapon().fire(start, along)
	assert_vector(shot.velocity.normalized()).is_equal_approx(along, Vector3.ONE * 0.0001)


func test_with_no_ray_the_shot_goes_straight_out_of_the_muzzle_whatever_a_camera_does() -> void:
	_camera.rotation = Vector3(deg_to_rad(30.0), deg_to_rad(70.0), 0.0)
	await InputSim.ticks(get_tree(), 2)
	_ready_to_fire()
	var shot := _weapon().fire()
	var out := -_weapon().muzzle.global_basis.z
	assert_float(shot.velocity.normalized().dot(out)).is_greater(0.9999)
	var marker := _weapon().muzzle
	assert_vector(_weapon().aim_point()).is_equal_approx(
		marker.global_position + out * _weapon().definition.aim_range, Vector3.ONE * 0.001
	)


func test_a_weapon_with_no_muzzle_fires_from_beside_its_shooter() -> void:
	# The arm up, aiming level along -Z: where the pistol's muzzle is, the default offset is.
	var command := CommandDriver.walking(Vector3.ZERO, Vector3.FORWARD)
	command.aim = true
	await CommandDriver.run(get_tree(), _players, command, 40)
	await InputSim.ticks(get_tree(), 4)
	var ray := _player.aim_ray()
	_ready_to_fire()
	var held := _weapon().fire(ray[0], ray[1])
	var held_start := held.global_position
	var held_way := held.velocity.normalized()
	_weapon().muzzle = null
	assert_bool(_weapon().can_fire()).is_false()
	_ready_to_fire()
	assert_bool(_weapon().can_fire()).is_true()
	assert_array(_weapon()._get_configuration_warnings()).is_empty()
	var bare := _weapon().fire(ray[0], ray[1])
	assert_object(bare).is_not_null()
	# It starts `no_muzzle_offset` from the ray's point beside the shooter, in the ray's axes.
	var offset := _weapon().no_muzzle_offset
	var want := ray[0] + Vector3(offset.x, offset.y, offset.z)
	assert_vector(bare.global_position).is_equal_approx(want, Vector3.ONE * 0.0001)
	# And that is where the pistol is: both shots start close together and fly the same way.
	print(
		(
			"muzzle from the eye in the view's axes: %s; no muzzle: %s; apart %.3f m, %.2f deg"
			% [
				held_start - ray[0],
				bare.global_position - ray[0],
				held_start.distance_to(bare.global_position),
				rad_to_deg(held_way.angle_to(bare.velocity.normalized())),
			]
		)
	)
	assert_float(held_start.distance_to(bare.global_position)).is_less(offset.length())
	assert_float(held_start.distance_to(bare.global_position)).is_less(0.05)
	assert_float(rad_to_deg(held_way.angle_to(bare.velocity.normalized()))).is_less(0.2)


func test_the_no_muzzle_offset_is_read_by_the_next_shot_and_turns_with_the_ray() -> void:
	var weapon := _bare_weapon()
	weapon.shooter = _player
	assert_array(weapon._get_configuration_warnings()).is_empty()
	weapon.no_muzzle_offset = Vector3(0.5, 0.25, -1.0)
	# A level ray along +X from above the shooter: right is +Z, forward +X.
	var start := Vector3(0.0, 1.5, 0.0)
	var shot := weapon.fire(start, Vector3.RIGHT)
	assert_vector(shot.global_position).is_equal_approx(
		Vector3(1.0, 1.75, 0.5), Vector3.ONE * 0.0001
	)
	weapon.make_ready()
	weapon.no_muzzle_offset = Vector3.ZERO
	shot = weapon.fire(start, Vector3.RIGHT)
	assert_vector(shot.global_position).is_equal_approx(start, Vector3.ONE * 0.0001)
	# A ray that starts behind the shooter (a camera's) is moved up to the shooter's depth.
	weapon.make_ready()
	shot = weapon.fire(Vector3(-4.0, 1.5, 0.0), Vector3.RIGHT)
	assert_vector(shot.global_position).is_equal_approx(start, Vector3.ONE * 0.0001)


func test_a_weapon_with_no_muzzle_and_no_shooter_cannot_fire_and_says_so() -> void:
	var weapon := _bare_weapon()
	assert_bool(weapon.can_fire()).is_false()
	assert_object(weapon.fire(Vector3.UP, Vector3.FORWARD)).is_null()
	assert_array(weapon._get_configuration_warnings()).has_size(1)
	# With no muzzle and no ray it shoots out of its own -Z.
	weapon.shooter = _player
	weapon.rotation.y = deg_to_rad(90.0)
	var shot := weapon.fire()
	assert_vector(shot.global_position).is_equal_approx(
		weapon.global_position, Vector3.ONE * 0.0001
	)
	assert_vector(shot.velocity.normalized()).is_equal_approx(Vector3.LEFT, Vector3.ONE * 0.0001)


func test_a_weapon_on_its_own_counts_its_cooldown_and_stops_when_told() -> void:
	var weapon := _bare_weapon()
	weapon.shooter = _player
	assert_bool(weapon.self_ticking).is_true()
	# Its own copy: the pistol's definition is shared by every weapon that holds it.
	weapon.definition = weapon.definition.duplicate()
	weapon.definition.fire_rate = 10.0
	weapon.fire()
	await InputSim.ticks(get_tree(), 9)
	assert_bool(weapon.can_fire()).is_true()
	# Off, while it runs: the cooldown stands still until someone ticks it.
	weapon.fire()
	weapon.self_ticking = false
	await InputSim.ticks(get_tree(), 30)
	assert_bool(weapon.can_fire()).is_false()
	weapon.self_ticking = true
	await InputSim.ticks(get_tree(), 9)
	assert_bool(weapon.can_fire()).is_true()


func test_the_cooldown_is_counted_in_ticks_never_read_from_a_clock() -> void:
	var weapon := _bare_weapon()
	weapon.shooter = _player
	weapon.self_ticking = false
	# Its own copy: the pistol's definition is shared by every weapon that holds it.
	weapon.definition = weapon.definition.duplicate()
	weapon.definition.fire_rate = 4.0
	weapon.fire()
	# Half a second of frames and of real time: nothing ticked it, so it has not cooled.
	await InputSim.ticks(get_tree(), 30)
	assert_bool(weapon.can_fire()).is_false()
	# Fifteen ticks of a sixtieth are a quarter of a second, in one frame or in fifteen.
	for tick in 14:
		weapon.tick(1.0 / 60.0)
	assert_bool(weapon.can_fire()).is_false()
	weapon.tick(1.0 / 60.0)
	weapon.tick(1.0 / 60.0)
	assert_bool(weapon.can_fire()).is_true()


func test_a_characters_weapon_cools_only_when_the_character_is_stepped() -> void:
	assert_bool(_weapon().self_ticking).is_false()
	# Its own copy: the pistol's definition is shared by every weapon that holds it.
	_weapon().definition = _weapon().definition.duplicate()
	_weapon().definition.fire_rate = 4.0
	_ready_to_fire()
	assert_object(_weapon().fire()).is_not_null()
	# The body is not stepped (the driver took it): its weapon waits with it.
	await InputSim.ticks(get_tree(), 40)
	assert_bool(_weapon().can_fire()).is_false()
	await CommandDriver.run(get_tree(), _players, PlayerCommand.new(), 14)
	assert_bool(_weapon().can_fire()).is_false()
	await CommandDriver.run(get_tree(), _players, PlayerCommand.new(), 2)
	assert_bool(_weapon().can_fire()).is_true()
	# Dead, it still cools: the cooldown is the last thing of every step.
	_ready_to_fire()
	_weapon().fire()
	_player.die()
	await CommandDriver.run(get_tree(), _players, PlayerCommand.new(), 16)
	assert_bool(_weapon()._cooldown <= 0.0).is_true()
	# A weapon given to a character later is stepped by it too.
	var other := _bare_weapon()
	assert_bool(other.self_ticking).is_true()
	_player.weapon = other
	assert_bool(other.self_ticking).is_false()


func test_the_step_state_puts_back_the_cooldown_and_the_spreads_place() -> void:
	var weapon := _bare_weapon()
	weapon.shooter = _player
	weapon.self_ticking = false
	# Its own copy: the pistol's definition is shared by every weapon that holds it.
	weapon.definition = weapon.definition.duplicate()
	weapon.definition.spread = 6.0
	weapon.fire()
	weapon.tick(0.1)
	var kept: Array = []
	weapon.save_step_state(kept)
	# Five of the gun's, eight of the melee blow's (gdstudio #1254).
	assert_array(kept).has_size(13)
	assert_float(kept[0]).is_equal_approx(0.15, 0.0001)
	weapon.make_ready()
	var first := weapon.fire().velocity
	weapon.make_ready()
	var second := weapon.fire().velocity
	assert_bool(first.is_equal_approx(second)).is_false()
	weapon.load_step_state(kept)
	assert_float(weapon._cooldown).is_equal_approx(0.15, 0.0001)
	weapon.make_ready()
	assert_vector(weapon.fire().velocity).is_equal(first)
	# The same array is written again, not a new one.
	weapon.save_step_state(kept)
	# Five of the gun's, eight of the melee blow's (gdstudio #1254).
	assert_array(kept).has_size(13)
	# An empty state (a character that had no weapon) changes nothing.
	var cooling := weapon._cooldown
	weapon.load_step_state([])
	assert_float(weapon._cooldown).is_equal(cooling)
