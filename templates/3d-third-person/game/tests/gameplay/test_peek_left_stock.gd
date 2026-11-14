# The rifle's stock out of the left upper arm on a left peek lean (gdstudio #1484): leaning left
# the rifle goes to the left shoulder (#1435), and its stock went 27 to 35 mm into the female's
# left upper arm and 5 to 19 mm into the male's, measured over the whole body as the sprint test
# measures it (`BodyClearance.HOLDING`: only the forearms and hands left out). The butt's push to
# the skin looks at the torso's bones alone, and on the right shoulder the upper arm hangs clear of
# the stock, so nothing saw it on the left. Now the left shoulder's pocket is nearer the chest's
# middle (`TwoHandHold.left_pocket_in`), and leaning left, aimed standing and crouched and at the
# low ready, on both prototype bodies, no point of the rifle is more than 10 mm inside the body,
# both hands are on their places, and over the lean's way in no update goes deeper.
extends GdUnitTestSuite

const RIFLE := "res://gameplay/weapon/rifle.tres"
## How deep a point of the rifle may be in the body, in metres: the hold's own stock test's 10 mm.
const BODY_DEPTH := 0.01
## How far a hand may be from its place on the rifle, in metres.
const HAND_GAP := 0.005
## Ticks upright and aimed before the lean, and held leaning before the reads.
const SETTLE := 40
## The updates read while the lean is held, and the ticks of the way in that are read.
const HELD_READS := 6
const WAY_IN := 16

var _arena: PlayArena
var _player: Player
var _skeleton: Skeleton3D
var _hold: TwoHandHold
var _contact: HandContact
var _clearance: BodyClearance


func before_test() -> void:
	InputSim.release_all()


func after_test() -> void:
	InputSim.release_all()
	if _arena != null:
		AudioDrain.stop_all(_arena)
	_arena = null


func test_the_stock_stays_out_of_the_left_upper_arm(
	body: String,
	crouched: bool,
	aimed: bool,
	_test_parameters := [
		["female", false, true],
		["female", true, true],
		["male", false, true],
		["male", true, true],
		["female", false, false],
		["male", true, false],
	]
) -> void:
	await _player_with_rifle(body)
	var tag := (
		"%s %s %s" % [body, "crouched" if crouched else "standing", "aimed" if aimed else "low"]
	)
	await _step(_command(false, crouched, aimed), SETTLE)
	var worst := {"depth": 0.0, "bone": &"", "right": 0.0, "left": 0.0}
	# The way in, a read every other tick, then the lean held.
	for tick in WAY_IN:
		await _step(_command(true, crouched, aimed), 1)
		if tick % 2 == 1:
			worst = _worse(worst, await _read())
	await _step(_command(true, crouched, aimed), SETTLE)
	for _read_index in HELD_READS:
		await _step(_command(true, crouched, aimed), 1)
		worst = _worse(worst, await _read())
	var share := _hold.side
	prints(
		(
			"LEFT STOCK %-24s side %.2f deepest %5.1f mm in %s, hands off %.1f / %.1f mm"
			% [tag, share, worst.depth * 1e3, worst.bone, worst.right * 1e3, worst.left * 1e3]
		)
	)
	assert_float(share).override_failure_message(tag + ": not on the left shoulder").is_equal(1.0)
	(
		assert_float(worst.depth)
		. override_failure_message(
			"%s: the rifle %.1f mm inside %s" % [tag, worst.depth * 1e3, worst.bone]
		)
		. is_less_equal(BODY_DEPTH)
	)
	assert_float(worst.right).is_less(HAND_GAP)
	assert_float(worst.left).is_less(HAND_GAP)


# A player of `body` in an arena at the origin facing -Z with the rifle out, stepped by commands.
func _player_with_rifle(body: String) -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	if body == "male":
		var slot := _player.model
		var old := slot.rig()
		slot.remove_child(old)
		old.free()
		slot.add_child((load(CharacterBodies.MALE) as PackedScene).instantiate())
	_player._present_facing()
	CommandDriver.take(_player)
	await InputSim.ticks(get_tree(), 2)
	_skeleton = _player.model.skeleton()
	_player.loadout.give(load(RIFLE) as WeaponDef, 60)
	await _step(PlayerCommand.new(), 60)
	assert_str(_player.weapon.definition.display_name).is_equal("Rifle")
	_hold = _player.model.get_node("RifleHeld") as TwoHandHold
	var near := _hold.get_node(^"Pivot/Rifle/Near") as Node3D
	_contact = HandContact.new(_skeleton)
	_contact.set_weapon(near)
	_clearance = BodyClearance.new(_skeleton, _contact, near, BodyClearance.HOLDING)


func _step(command: PlayerCommand, count: int) -> void:
	var stepped := command.clone()
	for tick in count:
		await get_tree().physics_frame
		_player.step(stepped, CommandDriver.tick_seconds())
		stepped.clear_edges()


func _command(leaning: bool, crouched: bool, aimed: bool) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.lean_left = leaning
	command.aim = aimed
	command.crouch = crouched
	var ahead := CommandCodec.direction_angles(Vector3.FORWARD)
	command.yaw = ahead.x
	command.pitch = ahead.y
	return command


# The deepest point of the rifle in the body and each hand's distance from its place, on the
# skeleton's next update.
func _read() -> Dictionary:
	await _skeleton.skeleton_updated
	_contact.snapshot()
	var found := _clearance.deepest(_hold.get_node(^"Pivot/Rifle/Near") as Node3D)
	return {
		"depth": found.depth,
		"bone": found.bone,
		"right": _gap("RightHandTarget", &"hand_r"),
		"left": _gap("LeftHandTarget", &"hand_l"),
	}


func _gap(marker: String, bone_name: StringName) -> float:
	var target := _hold.find_child(marker, true, false) as Node3D
	var pose := (
		_skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone(bone_name))
	)
	return pose.origin.distance_to(target.global_position)


func _worse(worst: Dictionary, read: Dictionary) -> Dictionary:
	var out := worst.duplicate()
	if read.depth > out.depth:
		out.depth = read.depth
		out.bone = read.bone
	out.right = maxf(out.right, read.right)
	out.left = maxf(out.left, read.left)
	return out
