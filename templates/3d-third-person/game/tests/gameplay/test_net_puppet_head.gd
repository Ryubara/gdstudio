# The head of a puppet while its player aims (kit #1334): on another screen the head sits level on
# a straight neck and looks along the aim, as on the player's own, from what a puppet already has
# (its facing, its view's pitch, the aim's heading and the aim bit); nothing new is sent. Ada aims
# the pistol, then the rifle, level and down in a game served over a loopback link; Bo's puppet of
# her is read from the pose its skin gets each drawn frame (`HeadPoseProbe`).
extends GdUnitTestSuite

## Where Ada stands, facing west (-X), and where Bo stands and watches.
const ADA_AT := Vector3(5.0, 0.0, 16.6)
const WEST := -PI / 2.0
const ALONG_YAW := PI / 2.0
const BO_AT := Vector3(-3.5, 0.0, 13.3)
## How far the puppet's head may roll off level, face off the aim, or roll on the neck, in degrees.
const LEVEL := 3.0
const LOOK := 4.0
const ROLL_ON_NECK := 8.0

var _rig: OnlineRig
var _ada: NetClient
var _bo: NetClient


func after_test() -> void:
	_rig = null
	_ada = null
	_bo = null


func test_a_puppet_aiming_holds_its_head_level_on_the_neck() -> void:
	_rig = auto_free(OnlineRig.new(true))
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_ada = await _rig.join("Ada")
	_bo = await _rig.join("Bo")
	assert_object(_ada).is_not_null()
	assert_object(_bo).is_not_null()
	await _rig.wait(20)
	_put(_bo, BO_AT, PI)
	_put(_ada, ADA_AT, WEST)
	await _rig.wait(20)
	var puppet := _bo.remote_players.puppet_at(_ada.slot) as Player
	assert_object(puppet).is_not_null()
	var probe := HeadPoseProbe.attach(puppet.model.skeleton())
	probe.layer = puppet.get_node("AimLayer") as AimLayer
	await _check(puppet, probe, "pistol")
	# The rifle: Ada's own body and the server's take it; a puppet's weapon is the one of its last
	# shot (`ClientCombat`), so the puppet is handed it as a shot of it would.
	var rifle := load("res://gameplay/weapon/rifle.tres") as WeaponDef
	_rig.server_body(_ada).loadout.give(rifle, 30)
	_ada.player.loadout.give(rifle, 30)
	puppet.loadout.give(rifle, 30)
	puppet.loadout.equip_now(puppet.loadout.slot_of(rifle))
	await _drive(_command(0.0, false), 40)
	assert_str(String(puppet.weapon.definition.resource_path)).ends_with("rifle.tres")
	await _check(puppet, probe, "rifle")


func _check(puppet: Player, probe: HeadPoseProbe, weapon: String) -> void:
	for pitch: float in [0.0, -25.0]:
		await _drive(_command(pitch, true), 40)
		probe.clear()
		for _frame in 6:
			await get_tree().process_frame
		var label := "%s puppet, pitch %+.0f" % [weapon, pitch]
		var layer := probe.layer
		assert_bool(puppet.aiming).override_failure_message(label + ": not aiming").is_true()
		assert_float(layer.head_weight()).override_failure_message(label).is_greater(0.99)
		var world := probe.model_turns[-1]
		var on_neck := probe.turns[-1]
		var neck := probe.neck_turns[-1]
		print(
			(
				(
					"%s: head off level %.1f, off the aim %.1f, on the neck (pitch %.1f, roll %.1f), neck"
					% [label, world.y, probe.misses[-1], on_neck.x, on_neck.y]
				)
				+ " (pitch %.1f, roll %.1f)" % [neck.x, neck.y]
			)
		)
		assert_float(absf(world.y)).override_failure_message(label + ": off level").is_less(LEVEL)
		assert_float(probe.misses[-1]).override_failure_message(label + ": off the aim").is_less(
			LOOK
		)
		(
			assert_float(maxf(absf(on_neck.y), absf(neck.y)))
			. override_failure_message(label + ": rolled on the neck")
			. is_less(ROLL_ON_NECK)
		)
		# The head faces where the player's own screen has it face.
		var own := _ada.player.get_node("AimLayer") as AimLayer
		assert_float(own.head_weight()).is_greater(0.99)


# Ada standing, looking `pitch` degrees up along her facing.
func _command(pitch: float, aim: bool) -> PlayerCommand:
	var command := CommandDriver.walking(
		Vector3.ZERO, CommandCodec.direction_from_angles(ALONG_YAW, deg_to_rad(pitch))
	)
	command.aim = aim
	return command


func _drive(command: PlayerCommand, ticks: int) -> void:
	_rig.controllers[_rig.clients.find(_ada)].next = command
	await _rig.wait(ticks)


func _put(client: NetClient, spot: Vector3, heading: float) -> void:
	_rig.server_body(client).teleport(spot, heading)
	client.player.teleport(spot, heading)
	var stand := PlayerCommand.new()
	stand.yaw = heading - PI
	_rig.controllers[_rig.clients.find(client)].next = stand
