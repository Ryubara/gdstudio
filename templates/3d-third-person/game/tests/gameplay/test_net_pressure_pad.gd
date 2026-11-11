# The prototype map's pressure pad in an online game, with clients joined to a real server over a
# real socket on 127.0.0.1 (`OnlineRig`): the server's copy senses the bodies and opens the room's
# door, every client paints its plate from the server's `entity` events (or the WELCOME's table when
# it joins late), so player two sees the pad pressed by player one's puppet.
extends GdUnitTestSuite

## South of the pad (`Triggers/PressurePad`, x 11.5 to 14.5, z -6.5 to -3.5) on the room's floor.
const SOUTH_OF_PAD := Vector3(13.0, 0.0, -1.0)
## On the pad.
const ON_PAD := Vector3(13.0, 0.0, -5.0)
## Where Bo watches from, clear of the pad.
const BO_SPOT := Vector3(10.0, 0.0, -1.0)
## The body's facing for a view that looks along -Z (`facing` is `yaw + PI`).
const FACING_NORTH := PI
## A push along the view's forward (the view looks along -Z with yaw 0).
const FORWARD := Vector2(0.0, 1.0)

var _rig: OnlineRig


func before_test() -> void:
	_rig = auto_free(OnlineRig.new(false))
	add_child(_rig)


func test_player_two_sees_the_pad_pressed_by_player_ones_puppet_and_the_door_open() -> void:
	assert_bool(_rig.start()).is_true()
	var ada := await _rig.join("Ada")
	var bo := await _rig.join("Bo")
	await _rig.wait(20)
	_place(ada, SOUTH_OF_PAD)
	_place(bo, BO_SPOT)
	await _rig.wait(10)
	var server_pad := _pad(_rig.server_view)
	var bos_pad := _pad(_rig.views[1])
	var adas_pad := _pad(_rig.views[0])
	var bos_door := _rig.views[1].find_child("MainDoor", true, false) as Door
	assert_bool(bos_pad.is_active()).is_false()
	assert_object(_plate_color(bos_pad)).is_equal(bos_pad.plate_idle_color)
	# Ada walks onto the pad with her own commands; the server's copy feels her body.
	_rig.controllers[0].next.move = FORWARD
	assert_bool(await _rig.until(server_pad.is_active, 120)).is_true()
	_rig.controllers[0].next.move = Vector2.ZERO
	assert_bool(await _rig.until(bos_pad.is_active, 60)).is_true()
	assert_object(_plate_color(bos_pad)).is_equal(bos_pad.plate_active_color)
	assert_bool(await _rig.until(adas_pad.is_active, 60)).is_true()
	# The door the pad opens, seen opening on Bo's screen.
	assert_bool(await _rig.until(func() -> bool: return bos_door.openness() > 0.0, 120)).is_true()
	# Ada walks back off; the plate turns back on Bo's screen.
	_rig.controllers[0].next.move = -FORWARD
	assert_bool(await _rig.until(func() -> bool: return not server_pad.is_active(), 120)).is_true()
	_rig.controllers[0].next.move = Vector2.ZERO
	assert_bool(await _rig.until(func() -> bool: return not bos_pad.is_active(), 60)).is_true()
	assert_object(_plate_color(bos_pad)).is_equal(bos_pad.plate_idle_color)
	# Bo's copy felt nothing itself: it paints what the server says.
	assert_bool(bos_pad.monitoring).is_false()
	assert_bool(server_pad.monitoring).is_true()


func test_a_player_who_joins_late_sees_the_pad_pressed_at_once() -> void:
	assert_bool(_rig.start()).is_true()
	var ada := await _rig.join("Ada")
	await _rig.wait(20)
	_place(ada, ON_PAD)
	var server_pad := _pad(_rig.server_view)
	assert_bool(await _rig.until(server_pad.is_active, 60)).is_true()
	var cy := await _rig.join("Cy")
	assert_object(cy).is_not_null()
	var cys_pad := _pad(_rig.views[1])
	# The first frame after the WELCOME: pressed, not idle and then pressed.
	assert_bool(cys_pad.is_active()).is_true()
	assert_object(_plate_color(cys_pad)).is_equal(cys_pad.plate_active_color)


func test_over_a_bad_link_player_two_sees_one_press_and_one_release() -> void:
	# 120 ms each way with 30 ms of jitter: the plate is late by the trip and never flickers.
	_rig.delay = 0.12
	_rig.jitter = 0.03
	assert_bool(_rig.start()).is_true()
	var ada := await _rig.join("Ada", 480)
	var bo := await _rig.join("Bo", 480)
	assert_object(bo).is_not_null()
	await _rig.wait(30)
	_place(ada, SOUTH_OF_PAD)
	_place(bo, BO_SPOT)
	await _rig.wait(30)
	var server_pad := _pad(_rig.server_view)
	var bos_pad := _pad(_rig.views[1])
	var seen: Array[bool] = [bos_pad.is_active()]
	var server_seen: Array[bool] = [server_pad.is_active()]
	var pressed_at := -1
	var bo_pressed_at := -1
	_rig.controllers[0].next.move = FORWARD
	for frame in 600:
		if frame == 240:
			_rig.controllers[0].next.move = -FORWARD
		elif server_pad.is_active() and frame < 240:
			_rig.controllers[0].next.move = Vector2.ZERO
		await get_tree().physics_frame
		if server_pad.is_active() != server_seen[-1]:
			server_seen.append(server_pad.is_active())
			if pressed_at < 0:
				pressed_at = frame
		if bos_pad.is_active() != seen[-1]:
			seen.append(bos_pad.is_active())
			if bo_pressed_at < 0:
				bo_pressed_at = frame
	prints(
		(
			"pressure pad over 120 ms each way: Bo's plate %d frames after the server's"
			% [bo_pressed_at - pressed_at]
		)
	)
	assert_array(server_seen).contains_exactly([false, true, false])
	assert_array(seen).contains_exactly([false, true, false])
	# One way of the trip at most, and the jitter: about 9 frames, never a round trip's 20.
	assert_int(bo_pressed_at - pressed_at).is_between(1, 14)


func _pad(view: Node) -> TriggerZone:
	return view.find_child("PressurePad", true, false) as TriggerZone


static func _plate_color(zone: TriggerZone) -> Color:
	var plate := zone.get_node("%Plate") as MeshInstance3D
	return (plate.material_override as StandardMaterial3D).albedo_color


# Puts the client's body and its server body at one spot (a test's shortcut for a walk there).
func _place(client: NetClient, at: Vector3) -> void:
	client.player.teleport(at, FACING_NORTH)
	_rig.server_body(client).teleport(at, FACING_NORTH)
