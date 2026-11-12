# The pistol points along the view while the character aims, whatever the legs' clip does to the
# pelvis (kit #1154): `AimBrace` holds the upper body's turn on the stance the aim poses were made
# on. The library's pistol poses stand on a pelvis turned 13 degrees; over the template's own idle,
# which stands square, and over the library's walk, the pistol pointed 13 to 18 degrees off.
extends GdUnitTestSuite

## The aim pose's own turn from the view is 3 degrees to the side and 1.5 up.
const ALONG_THE_VIEW := 4.0

var _arena: PlayArena
var _player: Player
var _players: Array[Player] = []
var _animation: CharacterAnimation


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	CommandDriver.take(_player)
	_players = [_player]
	_animation = _player.get_node("Animation")
	await InputSim.ticks(get_tree(), 4)


func after_test() -> void:
	AudioDrain.stop_all(_arena)


func _aiming(direction := Vector3.ZERO) -> PlayerCommand:
	var command := CommandDriver.walking(direction, Vector3.FORWARD)
	command.aim = true
	return command


func _brace() -> AimBrace:
	return _player.model.skeleton().get_node_or_null(^"AimBrace") as AimBrace


# How far the pistol's barrel is turned from the aim ray, in degrees: to the side (x) and up (y).
func _off_the_view() -> Vector2:
	var ray := _player.aim_ray()
	var out := -_player.weapon.muzzle.global_basis.z.normalized()
	var side := Vector2(ray[1].x, ray[1].z).angle_to(Vector2(out.x, out.z))
	return Vector2(rad_to_deg(side), rad_to_deg(asin(out.y) - asin(ray[1].y)))


func test_the_pistol_points_along_the_view_standing_and_walking() -> void:
	assert_str(String(_animation.idle_clip)).is_equal(String(CharacterClips.IDLE))
	await CommandDriver.run(get_tree(), _players, _aiming(), 44)
	# Through the idle's whole loop, weight on one foot and on the other.
	for sample in 5:
		var off := _off_the_view()
		assert_float(off.length()).override_failure_message("standing: %s" % off).is_less(
			ALONG_THE_VIEW
		)
		await CommandDriver.run(get_tree(), _players, _aiming(), 120)
	# And through a stride of the walk.
	await CommandDriver.run(get_tree(), _players, _aiming(Vector3.FORWARD), 30)
	for sample in 8:
		var off := _off_the_view()
		assert_float(off.length()).override_failure_message("walking: %s" % off).is_less(
			ALONG_THE_VIEW
		)
		await CommandDriver.run(get_tree(), _players, _aiming(Vector3.FORWARD), 10)


func test_without_the_brace_the_pistol_turns_with_the_pelvis() -> void:
	# The fault the brace is for, so the test above measures it. The aim layer (kit #1253) turns
	# the spine onto the aim after the clips and covers the same fault, so it is off here: this
	# measures the clips and the brace alone.
	(_player.get_node("AimLayer") as AimLayer).disabled = true
	_animation.aim_brace = false
	await CommandDriver.run(get_tree(), _players, _aiming(), 44)
	assert_object(_brace()).is_null()
	assert_float(absf(_off_the_view().x)).is_greater(10.0)
	_animation.aim_brace = true
	await CommandDriver.run(get_tree(), _players, _aiming(), 4)
	assert_float(_off_the_view().length()).is_less(ALONG_THE_VIEW)


func test_with_the_aim_layer_on_the_pistol_points_along_the_view_with_or_without_the_brace(
) -> void:
	# The two overlap: either one alone puts the barrel on the view over the square idle.
	_animation.aim_brace = false
	await CommandDriver.run(get_tree(), _players, _aiming(), 44)
	var loose := _off_the_view()
	assert_float(loose.length()).override_failure_message("no brace: %s" % loose).is_less(
		ALONG_THE_VIEW
	)
	_animation.aim_brace = true
	await CommandDriver.run(get_tree(), _players, _aiming(), 4)
	assert_float(_off_the_view().length()).is_less(ALONG_THE_VIEW)


func test_over_the_stance_the_poses_were_made_on_the_brace_changes_little() -> void:
	# The library idle is that stance: the brace turns the pistol under 2.5 degrees there.
	_animation.idle_clip = CharacterClips.stand_in(CharacterClips.IDLE)
	await CommandDriver.run(get_tree(), _players, _aiming(), 44)
	var held := _off_the_view()
	_animation.aim_brace = false
	await CommandDriver.run(get_tree(), _players, _aiming(), 4)
	var loose := _off_the_view()
	(
		assert_float(held.distance_to(loose))
		. override_failure_message("%s, %s" % [held, loose])
		. is_less(2.5)
	)
	assert_float(loose.length()).is_less(ALONG_THE_VIEW)


func test_the_brace_weighs_what_the_aim_weighs_on_the_ground_and_nothing_in_a_crouch() -> void:
	# Not aiming: there is no brace yet (a character that never aims carries no node for it).
	await CommandDriver.run(get_tree(), _players, CommandDriver.walking(Vector3.ZERO), 10)
	assert_object(_brace()).is_null()
	await CommandDriver.run(get_tree(), _players, _aiming(), 44)
	var brace := _brace()
	assert_object(brace).is_not_null()
	assert_bool(brace.active).is_true()
	# It runs before the hands close on the weapon.
	for child in brace.get_skeleton().get_children():
		if child is SkeletonModifier3D:
			assert_object(child).is_same(brace)
			break
	# The aim let go: off, and no work for the skeleton.
	await CommandDriver.run(get_tree(), _players, CommandDriver.walking(Vector3.ZERO), 40)
	assert_bool(brace.active).is_false()
	assert_float(brace.influence).is_equal(0.0)
	await CommandDriver.run(get_tree(), _players, _aiming(), 44)
	assert_float(brace.influence).is_equal_approx(_animation.pistol_weights().y, 0.001)
	assert_float(brace.influence).is_greater(0.99)
	# Crouched, the aim leans with the crouch as it did before: the brace lets go.
	var crouched := _aiming()
	crouched.crouch = true
	await CommandDriver.run(get_tree(), _players, crouched, 40)
	assert_str(String(_animation.body_state())).is_equal(String(CharacterAnimation.CROUCH))
	assert_float(_animation.pistol_weights().y).is_greater(0.99)
	assert_float(brace.influence).is_equal(0.0)
	assert_bool(brace.active).is_false()
	# Standing up again it holds again.
	await CommandDriver.run(get_tree(), _players, _aiming(), 40)
	assert_float(brace.influence).is_greater(0.99)
	# A dead character's skeleton is the ragdoll's.
	_player.die()
	assert_bool(brace.active).is_false()
