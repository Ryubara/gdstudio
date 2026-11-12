# The aim's heading off the body on another screen (kit #1277). Sliding, the body keeps along the
# slide and the aim layer turns the upper body to the aim (kit #1253). A puppet was placed with its
# view along its facing, so on Bo's screen Ada's pistol followed her aim's pitch but pointed along
# the slide. Now an aiming player's entry carries the aim's heading off the body (one signed byte),
# and the puppet's view is turned by it: the layer turns the puppet's upper body the same way. Ada
# slides and aims 50 degrees to each side in a game served over a loopback link; Bo's puppet of her
# is read from the muzzle its drawn pose leaves.
extends GdUnitTestSuite

## Where Ada slides from, westwards (-X) along z = 16.6, clear of the prototype level's parts
## (`tools/capture/puppet_aim_tour.tscn` films the same lane).
const START := Vector3(5.0, 0.0, 16.6)
## Her heading along the lane, and the view's yaw that looks along it (`direction_from_angles`).
const WEST := -PI / 2.0
const ALONG_YAW := PI / 2.0
## Where Bo stands and watches, off to the side.
const BO_AT := Vector3(-3.5, 0.0, 13.3)
## Degrees the aim is held off the slide, to the character's left (and then its right).
const AIM := 50.0
## How far the puppet may point off the aim, or off Ada's own screen, in degrees.
const TOLERANCE := 4.0

var _rig: OnlineRig
var _ada: NetClient
var _bo: NetClient


func after_test() -> void:
	_rig = null
	_ada = null
	_bo = null


func test_a_sliding_player_s_aim_to_the_side_turns_the_puppet_s_upper_body() -> void:
	_rig = auto_free(OnlineRig.new(true))
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_ada = await _rig.join("Ada")
	_bo = await _rig.join("Bo")
	assert_object(_ada).is_not_null()
	assert_object(_bo).is_not_null()
	await _rig.wait(20)
	_put(_bo, BO_AT, PI)
	# A long slide on the flat, on the server and on Ada's own screen alike, so each aim is held
	# well inside it (copies: the tuning file is a cached resource other suites read).
	var long_slide := _ada.player.slide_tuning.duplicate() as SlideTuning
	long_slide.max_time = 4.0
	long_slide.friction = 0.4
	long_slide.drag = 0.0
	_ada.player.slide_tuning = long_slide
	_rig.server_body(_ada).slide_tuning = long_slide
	_put(_ada, START, WEST)
	await _rig.wait(20)
	await _slide()
	var tick_before := _tick_bytes()
	# One slide: the aim to the left, then across to the right.
	for side: float in [AIM, -AIM]:
		await _aim(side)
		var label := "aim %+.0f" % side
		# What it costs: the TICK of these two players is one byte longer while Ada aims.
		assert_int(_tick_bytes()).is_equal(tick_before + SnapshotCodec.AIM_YAW_SIZE)
		var served := _rig.server_body(_ada)
		assert_bool(served.sliding).override_failure_message(label + ": not sliding").is_true()
		assert_float(rad_to_deg(served.aim_yaw)).is_equal_approx(side, 2.0)
		var puppet := _bo.remote_players.puppet_at(_ada.slot)
		assert_object(puppet).is_not_null()
		# The puppet slides along the slide, as the server's body does.
		assert_bool(puppet.aiming).is_true()
		assert_int(puppet.state).is_equal(Character.State.SLIDE)
		assert_float(absf(rad_to_deg(angle_difference(puppet.facing, WEST)))).is_less(3.0)
		assert_float(rad_to_deg(puppet.aim_yaw)).is_equal_approx(side, 2.0)
		# Its pistol points at its aim, to the side of the slide.
		var layer := puppet.get_node("AimLayer") as AimLayer
		assert_float(layer.weight()).is_greater(0.9)
		var miss := _muzzle_miss(puppet)
		(
			assert_float(miss)
			. override_failure_message(
				"%s: the puppet's muzzle is %.1f degrees off" % [label, miss]
			)
			. is_less(TOLERANCE)
		)
		var heading := _muzzle_heading_off_facing(puppet)
		(
			assert_float(heading)
			. override_failure_message(
				"%s: the puppet's pistol points %.1f degrees off its body" % [label, heading]
			)
			. is_equal_approx(side, TOLERANCE)
		)
		# And where Ada's own screen points it.
		var own := _muzzle_heading_off_facing(_ada.player)
		print(
			(
				"%s: puppet muzzle %.2f off its aim, %.2f off its body; own screen %.2f"
				% [label, miss, heading, own]
			)
		)
		assert_float(absf(heading - own)).is_less(TOLERANCE)


# Sprints west and drops into a slide, as a player does.
func _slide() -> void:
	var run := CommandDriver.walking(Vector3.LEFT, Vector3.LEFT)
	run.sprint = true
	await _drive(run, 30)
	var slide := CommandDriver.walking(Vector3.LEFT, Vector3.LEFT)
	slide.sprint = true
	slide.crouch = true
	await _drive(slide, 4)
	(
		assert_bool(_rig.server_body(_ada).sliding)
		. override_failure_message("the slide did not start")
		. is_true()
	)


# Aims `side` degrees off the slide, still sliding.
func _aim(side: float) -> void:
	var aimed := CommandDriver.walking(
		Vector3.LEFT, CommandCodec.direction_from_angles(ALONG_YAW + deg_to_rad(side), 0.0)
	)
	aimed.sprint = true
	aimed.crouch = true
	aimed.aim = true
	# The aim pose comes up and the puppet, drawn a little behind, catches up.
	await _drive(aimed, 30)
	for _frame in 2:
		await get_tree().process_frame


# The bytes of the TICK the server sends for its two seated players, with no event.
func _tick_bytes() -> int:
	var players: Array[PlayerEntry] = []
	for client in [_ada, _bo]:
		players.append(NetServer.entry_of(client.slot, _rig.server_body(client)))
	var size := SnapshotCodec.tick(0, 0, [], players).size()
	print("tick bytes, two players, Ada aiming %s: %d" % [players[0].aim, size])
	return size


func _drive(command: PlayerCommand, ticks: int) -> void:
	_rig.controllers[_rig.clients.find(_ada)].next = command
	await _rig.wait(ticks)


# Degrees between the way the muzzle points and the way from it to the layer's aim point.
func _muzzle_miss(body: Character) -> float:
	var layer := body.get_node("AimLayer") as AimLayer
	var muzzle := body.weapon.muzzle
	var toward := layer.aim_point(1.0) - muzzle.global_position
	return rad_to_deg((-muzzle.global_basis.z).angle_to(toward))


# Degrees the muzzle's heading is off the way the body faces (positive to the character's left).
func _muzzle_heading_off_facing(body: Character) -> float:
	var forward := -body.weapon.muzzle.global_basis.z
	var heading := atan2(-forward.x, -forward.z)
	return rad_to_deg(angle_difference(body.facing - PI, heading))


func _put(client: NetClient, spot: Vector3, heading: float) -> void:
	_rig.server_body(client).teleport(spot, heading)
	client.player.teleport(spot, heading)
	var stand := PlayerCommand.new()
	stand.yaw = heading - PI
	_rig.controllers[_rig.clients.find(client)].next = stand
