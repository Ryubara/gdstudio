# The legs stand still under a standing aim (kit #1206): `AimStance` holds the idle on its steadiest
# pose as the arm comes up. Without it the template's idle shifts the weight from foot to foot and
# the muzzle sways 34 mm to each side of its middle while the player holds the aim.
extends GdUnitTestSuite

## How far the muzzle may wander from its place through a held aim, in metres.
const STEADY := 0.010
## The barrel's limit from the aim ray, as `test_aim_brace.gd` holds it, in degrees.
const ALONG_THE_VIEW := 4.0
## A planted foot's limit while the stance blends in or out (`own-animation.md#checks`), metres.
const PLANTED := 0.005
## Ten seconds of ticks: the idle's whole loop.
const HELD_TICKS := 600

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


func _stance() -> AimStance:
	return _animation._brace.stance


func _aiming() -> PlayerCommand:
	var command := CommandDriver.walking(Vector3.ZERO, Vector3.FORWARD)
	command.aim = true
	return command


func _standing() -> PlayerCommand:
	return CommandDriver.walking(Vector3.ZERO, Vector3.FORWARD)


# How far the pistol's barrel is turned from the aim ray, in degrees.
func _off_the_view() -> float:
	var ray := _player.aim_ray()
	return rad_to_deg(ray[1].angle_to(-_player.weapon.muzzle.global_basis.z))


func _feet() -> PackedVector3Array:
	var skeleton := _player.model.skeleton()
	var feet := PackedVector3Array()
	for bone in [&"foot_l", &"foot_r", &"ball_l", &"ball_r"]:
		var pose := skeleton.get_bone_global_pose(skeleton.find_bone(bone))
		feet.append(skeleton.global_transform * pose.origin)
	return feet


# The muzzle's places through `ticks` of `command`, one a tick.
func _muzzle_through(command: PlayerCommand, ticks: int) -> PackedVector3Array:
	var places: Array[Vector3] = []
	var each := func(_tick: int) -> void: places.append(_player.weapon.muzzle.global_position)
	await CommandDriver.run(get_tree(), _players, command, ticks, each)
	assert_int(places.size()).is_equal(ticks)
	return PackedVector3Array(places)


# The furthest a place is from the middle of their spread (half the largest span, by axis).
static func _sway(places: PackedVector3Array) -> float:
	var low := places[0]
	var high := places[0]
	for place in places:
		low = low.min(place)
		high = high.max(place)
	return ((high - low) * 0.5).length()


func test_the_held_aim_keeps_the_muzzle_in_place_for_ten_seconds() -> void:
	assert_str(String(_animation.idle_clip)).is_equal(String(CharacterClips.IDLE))
	await CommandDriver.run(get_tree(), _players, _aiming(), 44)
	assert_float(_stance().amount(_animation.tree)).is_equal_approx(1.0, 0.001)
	var places := await _muzzle_through(_aiming(), HELD_TICKS)
	var sway := _sway(places)
	print("held aim, muzzle sway over 10 s: %.1f mm" % (sway * 1000.0))
	assert_float(sway).override_failure_message("sway %.4f m" % sway).is_less(STEADY)
	assert_float(_off_the_view()).is_less(ALONG_THE_VIEW)


func test_without_the_stance_the_idle_sways_the_muzzle() -> void:
	# The fault the stance is for, so the test above measures it.
	_animation.aim_stance = false
	await CommandDriver.run(get_tree(), _players, _aiming(), 44)
	assert_float(_stance().amount(_animation.tree)).is_equal(0.0)
	var sway := _sway(await _muzzle_through(_aiming(), HELD_TICKS))
	print("held aim without the stance, muzzle sway over 10 s: %.1f mm" % (sway * 1000.0))
	assert_float(sway).is_greater(0.025)


func test_the_barrel_stays_along_the_view_through_the_held_aim() -> void:
	await CommandDriver.run(get_tree(), _players, _aiming(), 44)
	var worst := 0.0
	for sample in 20:
		worst = maxf(worst, _off_the_view())
		await CommandDriver.run(get_tree(), _players, _aiming(), HELD_TICKS / 20)
	print("held aim, barrel off the view at most %.2f deg" % worst)
	assert_float(worst).is_less(ALONG_THE_VIEW)


func test_the_feet_stay_planted_as_the_stance_comes_in_and_goes() -> void:
	# The aim comes up at five places of the idle's loop, the weight on one foot, the other, between.
	# A lambda keeps a copy of a float it uses, so the furthest drift is kept in an array.
	var worst: Array[float] = [0.0]
	# The first aim turns the body to the view: done before anything is measured.
	await CommandDriver.run(get_tree(), _players, _aiming(), 44)
	for start in 5:
		await CommandDriver.run(get_tree(), _players, _standing(), 120)
		for command: PlayerCommand in [_aiming(), _standing()]:
			var planted := _feet()
			var each := func(_tick: int) -> void:
				var feet := _feet()
				for foot in feet.size():
					worst[0] = maxf(worst[0], feet[foot].distance_to(planted[foot]))
			await CommandDriver.run(get_tree(), _players, command, 30, each)
	print("feet while the stance blends: at most %.1f mm" % (worst[0] * 1000.0))
	assert_float(worst[0]).override_failure_message("feet %.4f m" % worst[0]).is_less(PLANTED)
	assert_float(worst[0]).is_greater(0.0)


func test_the_stance_follows_the_arm_and_leaves_the_gaits_alone() -> void:
	await CommandDriver.run(get_tree(), _players, _standing(), 10)
	assert_float(_stance().amount(_animation.tree)).is_equal(0.0)
	await CommandDriver.run(get_tree(), _players, _aiming(), 44)
	var aim := _animation.pistol_weights().y
	assert_float(_stance().amount(_animation.tree)).is_equal_approx(aim, 0.001)
	# The held frame is the idle's middle, not its start.
	assert_float(_stance().held_at).is_greater(0.0)
	# Walking aimed, the blend space is on the walk: the idle point has no weight there.
	var walking := CommandDriver.walking(Vector3.FORWARD, Vector3.FORWARD)
	walking.aim = true
	await CommandDriver.run(get_tree(), _players, walking, 40)
	assert_float(_player.ground_speed()).is_greater(1.0)
	# Let go, the idle plays again.
	await CommandDriver.run(get_tree(), _players, _standing(), 60)
	assert_float(_stance().amount(_animation.tree)).is_equal(0.0)
