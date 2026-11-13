# The chest while aiming crouched and lying (kit #1351): with the rifle and the fists the chest
# stands within a set lean of upright, so the head stays in the shoulder camera's frame. Our crouch
# idle folds the trunk so the chest leans about 81 degrees forward; the pistol's and the rifle's aim
# clips and the aim offset stand it up (16 to 29 degrees), and the fists, which have no muzzle and
# no aim clips, kept the fold (`AimUprightModifier` stands it up now). Driven by commands, as a
# server or a bot drives a body, and read from the pose the skin gets each drawn frame
# (`ChestPoseProbe`), with the physics ticking slower than the frames.
extends GdUnitTestSuite

## The physics rate of the suite: three drawn frames a tick (the suites run at 60 frames a second).
const TICKS_PER_SECOND := 20
## The most the chest may lean off upright crouched while aiming, in degrees: the fists' upright
## turn holds its forward lean at `AimLayer.upright_max_lean` (30), and the crouch's turned
## shoulders add a few degrees to the side (34 in all); the rifle's reads 23, the pistol's 16 to 29.
const CROUCH_LEAN := 36.0
## The most it may lean lying while aiming, in degrees: lying the chest is raised off the floor on
## the elbows (the rifle's 23, the fists' prone idle 52), never folded into it.
const LYING_LEAN := 60.0
## The crouch idle's own fold, in degrees (81 to 82): the fault the upright turn mends.
const FOLDED := 70.0
## The aim pitches each case holds (negative looks down).
const PITCHES: Array[float] = [-30.0, 0.0, 20.0]

var _arena: PlayArena
var _player: Player
var _layer: AimLayer
var _probe: ChestPoseProbe


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3(0.0, 0.0, 20.0))
	CommandDriver.take(_player)
	await InputSim.ticks(get_tree(), 6)
	Engine.physics_ticks_per_second = TICKS_PER_SECOND
	_layer = _player.get_node("AimLayer")


func after_test() -> void:
	Engine.physics_ticks_per_second = 60
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


func test_the_rifle_aimed_crouched_and_lying_keeps_the_chest_up() -> void:
	_player.loadout.give(load("res://gameplay/weapon/rifle.tres") as WeaponDef, 30)
	await _stand(30)
	assert_str(String(_player.weapon.definition.resource_path)).ends_with("rifle.tres")
	await _every_stance("rifle")
	# The rifle's aim offset stands its chest: the upright turn stays off.
	assert_float(_layer.upright_weight()).is_equal(0.0)


func test_the_fists_aimed_crouched_and_lying_keep_the_chest_up() -> void:
	_player.loadout.toggle_unarmed()
	await _stand(30)
	await _every_stance("fists")


func test_the_pistol_aimed_crouched_keeps_the_chest_up() -> void:
	await _stand(30)
	_probe = ChestPoseProbe.attach(_player.model.skeleton())
	for pitch: float in PITCHES:
		await _hold("pistol", "crouched", pitch)
	assert_float(_layer.upright_weight()).is_equal(0.0)


func test_without_the_upright_turn_the_fists_aim_folded() -> void:
	# The fault the turn mends: the crouch idle's chest stays folded under the fists' aim.
	_layer.upright_disabled = true
	_player.loadout.toggle_unarmed()
	await _stand(30)
	_probe = ChestPoseProbe.attach(_player.model.skeleton())
	await _settle(_command(Vector3.ZERO, 0.0, "crouched"))
	assert_float(_probe.chest_leans[-1]).is_greater(FOLDED)


func test_the_upright_turn_comes_and_goes_with_the_aim() -> void:
	_player.loadout.toggle_unarmed()
	await _stand(30)
	_probe = ChestPoseProbe.attach(_player.model.skeleton())
	var aimed := _command(Vector3.ZERO, 0.0, "crouched")
	await _settle(aimed)
	assert_float(_layer.upright_weight()).is_equal_approx(1.0, 0.01)
	assert_bool(_layer.upright_modifier().active).is_true()
	# It runs after the spine's aim turn and before the head, which looks from the chest it leaves.
	var upright := _layer.upright_modifier().get_index()
	assert_int(upright).is_greater(_layer.modifier().get_index())
	assert_int(upright).is_less(_layer.head_modifier().get_index())
	var lowered := _command(Vector3.ZERO, 0.0, "crouched")
	lowered.aim = false
	await _settle(lowered)
	assert_float(_layer.upright_weight()).is_equal(0.0)
	assert_bool(_layer.upright_modifier().active).is_false()
	# Crouched with the aim down, the crouch keeps its own fold.
	assert_float(_probe.chest_leans[-1]).is_greater(FOLDED)


# Crouched (still and walking) and lying, each at every pitch of `PITCHES`.
func _every_stance(weapon: String) -> void:
	_probe = ChestPoseProbe.attach(_player.model.skeleton())
	for stance: String in ["crouched", "crouch walking", "lying"]:
		await _stand(30)
		for pitch: float in PITCHES:
			await _hold(weapon, stance, pitch)


# Aims `pitch` degrees up in `stance` until it settles, then reads the drawn frames.
func _hold(weapon: String, stance: String, pitch: float) -> void:
	var move := Vector3.RIGHT if stance == "crouch walking" else Vector3.ZERO
	await _settle(_command(move, pitch, stance))
	var label := "%s %s, pitch %+.0f" % [weapon, stance, pitch]
	assert_int(_probe.chest_leans.size()).override_failure_message(label + ": no frame").is_greater(
		0
	)
	var most := LYING_LEAN if stance == "lying" else CROUCH_LEAN
	(
		assert_float(_probe.largest())
		. override_failure_message(
			"%s: the chest leans %.1f degrees off upright" % [label, _probe.largest()]
		)
		. is_less(most)
	)
	print(
		(
			"%s: chest lean %.1f (forward %.1f), trunk %.1f"
			% [label, _probe.largest(), _probe.chest_pitches[-1], _probe.trunk_leans[-1]]
		)
	)


# Runs `command` until the stance and the aim settle, then records eight more ticks.
func _settle(command: PlayerCommand) -> void:
	await CommandDriver.run(get_tree(), [_player], command, 40)
	_probe.clear()
	await CommandDriver.run(get_tree(), [_player], command, 8)


# A command that aims `pitch` degrees up along the body's facing in `stance`, moving along `move`.
func _command(move: Vector3, pitch: float, stance: String) -> PlayerCommand:
	var look := CommandCodec.direction_from_angles(_player.facing + PI, deg_to_rad(pitch))
	var command := CommandDriver.walking(move, look)
	command.aim = true
	command.crouch = stance.begins_with("crouch")
	command.prone = stance == "lying"
	return command


# Stands up and lowers the weapon, back at the start.
func _stand(ticks: int) -> void:
	var idle := PlayerCommand.new()
	idle.yaw = 0.0
	_player.teleport(Vector3(0.0, 0.0, 20.0), PI)
	await CommandDriver.run(get_tree(), [_player], idle, ticks)
