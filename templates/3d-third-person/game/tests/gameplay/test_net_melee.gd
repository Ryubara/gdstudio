# Melee online (gdstudio #1254). Over a real socket with clients driven by hand (`NetServerRig`): a
# blow is a 4-byte MELEE event to the others (never to its thrower), what it meets a HIT to
# everyone, it spends no round and fires no SHOT, and a blow whose shot block starts far off the
# body is refused and thrown nowhere. Then with two predicting clients at 150 ms each way
# (`OnlineRig`): a blow Ada's screen draws on a running guard lands on the server, met where her
# screen drew it (the rewind, moved on by the ticks from the press to the blow's window), and with
# the rewind off the same blow misses.
extends GdUnitTestSuite

## How far apart the two hand-driven bodies stand (inside the pistol's blow reach).
const APART := 1.0
## Open ground west of the push cubes, as `test_net_ai_rewind.gd` uses it.
const LANE_START := Vector3(-14.0, 0.3, 13.0)
const DELAY := 0.15
const CHEST := 1.2

var _rig: Node
var _ada: NetClient
var _aim_at := Callable()
var _press_when := Callable()
var _pressed := false


func after_test() -> void:
	_rig = null
	_ada = null
	_aim_at = Callable()
	_press_when = Callable()
	_pressed = false


func test_a_blow_is_a_small_event_to_the_others_and_its_hit_reaches_everyone() -> void:
	var rig := auto_free(NetServerRig.new()) as NetServerRig
	_rig = rig
	add_child(rig)
	assert_bool(rig.start()).is_true()
	var ada := await rig.join("Ada")
	var bo := await rig.join("Bo")
	var thrower := rig.server.body_at(0)
	var victim := rig.server.body_at(1)
	_face_each_other(thrower, victim)
	await rig.wait(4)
	var ammo: int = thrower.weapon.ammo
	var full: float = Health.of(victim).value
	ada.send_command(_blow_at(thrower, victim.global_position + Vector3.UP * CHEST))
	var heard := func() -> bool:
		return (
			not bo.heard(NetEvent.Kind.HIT).is_empty()
			and not ada.heard(NetEvent.Kind.HIT).is_empty()
		)
	assert_bool(await rig.until(heard, 60)).is_true()
	assert_int(rig.server.combat.melees).is_equal(1)
	assert_int(bo.heard(NetEvent.Kind.MELEE).size()).is_equal(1)
	assert_array(ada.heard(NetEvent.Kind.MELEE)).is_empty()
	var melee: NetEvent = bo.heard(NetEvent.Kind.MELEE)[0]
	assert_int(melee.slot).is_equal(0)
	assert_int(SnapshotCodec.event_size(melee)).is_equal(4)
	var hit: NetEvent = bo.heard(NetEvent.Kind.HIT)[0]
	assert_int(hit.code).is_equal(NetHits.Kind.PLAYER)
	assert_int(NetHits.slot_of(hit.id)).is_equal(1)
	# The server's body has no model and so no hit zones: the capsule takes the blow whole.
	var category := thrower.weapon.definition.category
	assert_float(full - Health.of(victim).value).is_equal_approx(category.melee_damage, 0.01)
	assert_int(thrower.weapon.ammo).is_equal(ammo)
	assert_array(bo.heard(NetEvent.Kind.SHOT)).is_empty()
	assert_int(rig.server.combat.shots).is_equal(0)


func test_a_blow_from_far_off_the_body_is_refused_and_thrown_nowhere() -> void:
	var rig := auto_free(NetServerRig.new()) as NetServerRig
	_rig = rig
	add_child(rig)
	assert_bool(rig.start()).is_true()
	var ada := await rig.join("Ada")
	var bo := await rig.join("Bo")
	var thrower := rig.server.body_at(0)
	_face_each_other(thrower, rig.server.body_at(1))
	await rig.wait(4)
	var hostile := _blow_at(thrower, rig.server.body_at(1).global_position + Vector3.UP * CHEST)
	hostile.origin += Vector3(50.0, 0.0, 0.0)
	ada.send_command(hostile)
	await rig.wait(40)
	assert_int(rig.server.combat.melees).is_equal(0)
	assert_array(bo.heard(NetEvent.Kind.MELEE)).is_empty()
	assert_array(bo.heard(NetEvent.Kind.HIT)).is_empty()
	assert_int(ada.heard(NetEvent.Kind.REJECTED).size()).is_equal(1)


func test_at_150_ms_each_way_a_blow_drawn_on_a_running_guard_lands() -> void:
	var runner := await _run_guard(0.6)
	assert_bool(await _strike(runner)).is_true()


func test_with_the_rewind_off_the_blow_drawn_on_the_running_guard_misses() -> void:
	var runner := await _run_guard(0.0)
	assert_bool(await _strike(runner)).is_false()


# --- Helpers ---


# Puts `victim` `APART` metres in front of `thrower`, both facing each other.
func _face_each_other(thrower: Character, victim: Character) -> void:
	var spot := thrower.global_position
	thrower.teleport(spot, PI)
	victim.teleport(spot + Vector3(0.0, 0.0, -APART), 0.0)


# A command that aims at `point` from `body`'s eye, with its shot block, pressing melee.
static func _blow_at(body: Character, point: Vector3) -> PlayerCommand:
	var eye := body.global_position + Vector3.UP * body.tuning.camera_height
	var angles := CommandCodec.direction_angles(point - eye)
	var command := PlayerCommand.new()
	command.yaw = angles.x
	command.pitch = angles.y
	command.has_shot = true
	command.origin = eye
	command.shot_yaw = angles.x
	command.shot_pitch = angles.y
	command.melee_pressed = true
	return command


# Ada strikes once at the lane in front of her, led by the guard her screen draws; true when the
# server's guard was hit.
func _strike(runner: AiCharacter) -> bool:
	var rig := _rig as OnlineRig
	var puppet := _ada.ai_replica.puppet_of(_id_of(runner))
	var health := Health.of(runner)
	var full := health.value
	# Straight ahead at the lane, pressed as the drawn guard is the blow's delay away from it: the
	# guard runs on while the fist goes out, as a player leads a runner.
	var ahead := Vector3(_ada.player.global_position.x, CHEST, LANE_START.z)
	_aim_at = func() -> Vector3: return ahead
	var lead := runner.velocity.length() * _ada.player.weapon.definition.blow_hit_start()
	_press_when = func() -> bool: return puppet.global_position.x >= ahead.x - lead
	var pressed := func() -> bool: return _pressed
	assert_bool(await rig.until(pressed, 400)).is_true()
	var drawn_behind := runner.global_position.x - puppet.global_position.x
	await rig.wait(60)
	prints(
		(
			"blow, rewind %.2f s: drawn %.2f m behind the server, hit %s"
			% [rig.server.ai_rewind_seconds, drawn_behind, health.value < full]
		)
	)
	assert_int(rig.server.combat.melees).is_equal(1)
	# Far enough behind that a blow at the server's guard would not meet the drawn one.
	assert_float(drawn_behind).is_greater(0.8)
	return health.value < full


# The rig at `DELAY` each way, Ada a metre off a lane a guard runs along.
func _run_guard(rewind_seconds: float) -> AiCharacter:
	var rig := auto_free(OnlineRig.new(false)) as OnlineRig
	_rig = rig
	rig.delay = DELAY
	rig.prepare_server = func(server: NetServer) -> void: server.ai_rewind_seconds = rewind_seconds
	add_child(rig)
	assert_bool(rig.start()).is_true()
	_ada = await rig.join("Ada", 600)
	assert_object(_ada).is_not_null()
	var spot := LANE_START + Vector3(5.0, 0.0, APART)
	rig.server_body(_ada).teleport(spot, PI)
	_ada.player.teleport(spot, PI)
	rig.controllers[0].plan = _ada_plan
	var runner := AiNetStage.walker(LANE_START, Vector3.RIGHT, 1.0)
	AiNetStage.server_map(rig.server).add_child(runner)
	var drawn := func() -> bool:
		var puppet := _ada.ai_replica.puppet_of(_id_of(runner))
		return puppet != null and puppet.visible
	assert_bool(await rig.until(drawn, 120)).is_true()
	return runner


# Ada's controller: aims at the drawn guard's chest with the shot block from her eye, and presses
# melee once, on the tick the drawn guard is in front of her.
func _ada_plan(_tick: int) -> PlayerCommand:
	var command := PlayerCommand.new()
	if not _aim_at.is_valid():
		return command
	var body := _ada.player
	var eye := body.global_position + Vector3.UP * body.tuning.camera_height
	var angles := CommandCodec.direction_angles((_aim_at.call() as Vector3) - eye)
	command.yaw = angles.x
	command.pitch = angles.y
	command.has_shot = true
	command.origin = eye
	command.shot_yaw = angles.x
	command.shot_pitch = angles.y
	if not _pressed and _press_when.call():
		command.melee_pressed = true
		_pressed = true
	return command


static func _id_of(walker: AiCharacter) -> int:
	return int(walker.get_meta(NetHits.AI_META, -1))
