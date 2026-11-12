# The shots of a press online (gdstudio #1335): a predicting client and the game server in one
# process (`OnlineRig`, lockstep loopback). The client's controller aims and then presses fire for
# one tick, taps it for less than the shot interval and holds it two seconds, as a player's input
# would; the client's body fires what it predicts at once and the server's body fires the same
# commands. For every weapon, one shot a press and automatic, the two counts are the same shot for
# shot, and each press gave what it gives offline (`test_fire_count.gd`). The fists' press is a blow
# (gdstudio #1254), counted as a shot: one a press, held or not, automatic or not.
extends GdUnitTestSuite

const WEAPONS: Array[String] = [
	"res://gameplay/weapon/pistol.tres",
	"res://gameplay/weapon/rifle.tres",
	"res://gameplay/weapon/fists.tres",
]
const AIM_TICKS := 40
const SETTLE_TICKS := 60
const HOLD_SECONDS := 2.0
## Where the client stands, on open ground, looking along -Z.
const SPOT := Vector3(-3.0, 0.3, -6.0)

var _rig: OnlineRig
var _client: NetClient
## The ticks of the controller (its `ticks`) on which fire is held, and from which aim is held.
var _fire_ticks: Dictionary[int, bool] = {}
var _aim_from := 1 << 30
var _automatic: Dictionary[String, bool] = {}


func before_test() -> void:
	for path in WEAPONS:
		_automatic[path] = (load(path) as WeaponDef).automatic
	_rig = auto_free(OnlineRig.new())
	add_child(_rig)
	assert_bool(_rig.start()).is_true()
	_client = await _rig.join("Ada", 600)
	assert_object(_client).is_not_null()
	_rig.server_body(_client).teleport(SPOT, PI)
	_client.player.teleport(SPOT, PI)
	_rig.controllers[0].plan = _plan


func after_test() -> void:
	for path in _automatic:
		(load(path) as WeaponDef).automatic = _automatic[path]
	_rig = null
	_client = null


func test_the_client_predicts_the_shots_the_server_fires() -> void:
	var client_shots := [0]
	var server_shots := [0]
	var server_body := _rig.server_body(_client)
	_client.player.weapon.fired.connect(func(_s: Projectile) -> void: client_shots[0] += 1)
	server_body.weapon.fired.connect(func(_s: Projectile) -> void: server_shots[0] += 1)
	_client.player.weapon.melee_started.connect(func(_b: int) -> void: client_shots[0] += 1)
	server_body.weapon.melee_started.connect(func(_b: int) -> void: server_shots[0] += 1)
	var seen: Array[String] = []
	for automatic: bool in [false, true]:
		for path in WEAPONS:
			# One definition, shared by both bodies as by every weapon that loads it.
			var definition := load(path) as WeaponDef
			definition.automatic = automatic
			for body: Character in [_client.player, server_body]:
				body.weapon.definition = definition
				body.weapon.make_ready()
			await _rig.wait(SETTLE_TICKS)
			var label := "%s automatic %s" % [path.get_file(), automatic]
			var interval := floori(definition.shot_interval() * Engine.physics_ticks_per_second)
			var hold := roundi(HOLD_SECONDS * Engine.physics_ticks_per_second)
			var presses: Array[int] = [1, interval - 1, hold]
			for press in presses:
				var at := _rig.controllers[0].ticks
				_aim_from = at
				_fire_ticks.clear()
				for tick in press:
					_fire_ticks[at + AIM_TICKS + tick] = true
				client_shots[0] = 0
				server_shots[0] = 0
				await _rig.wait(AIM_TICKS + press + SETTLE_TICKS)
				var expected := 1.0
				var slack := 0.0
				if press == hold and automatic and definition.kind != WeaponDef.Kind.MELEE:
					expected = HOLD_SECONDS * definition.fire_rate
					slack = 1.0
				seen.append(
					(
						"%s, %d ticks: client %d server %d"
						% [label, press, client_shots[0], server_shots[0]]
					)
				)
				assert_int(client_shots[0]).override_failure_message(seen.back()).is_equal(
					server_shots[0]
				)
				(
					assert_float(float(client_shots[0]))
					. override_failure_message(seen.back())
					. is_between(expected - slack, expected + slack)
				)
	prints("shots online:", seen)


# Aim straight ahead from the eye, with the shot block, and hold fire on the planned ticks.
func _plan(tick: int) -> PlayerCommand:
	var command := PlayerCommand.new()
	var ahead := CommandCodec.direction_angles(Vector3.FORWARD)
	command.yaw = ahead.x
	if tick < _aim_from or _client == null:
		return command
	var body := _client.player
	var eye := body.global_position + Vector3.UP * body.tuning.camera_height
	command.aim = true
	command.has_shot = true
	command.origin = eye
	command.shot_yaw = ahead.x
	command.shot_pitch = ahead.y
	command.fire = _fire_ticks.has(tick)
	command.fire_pressed = command.fire and not _fire_ticks.has(tick - 1)
	return command
