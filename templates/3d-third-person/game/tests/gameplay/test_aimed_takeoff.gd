# A jump begun while a gait transition plays (gdstudio #1462): the pistol up, the body jogs, stops
# and jumps before the stop clip ends. The transition hands the body to the jump state, so the
# jump's clip plays, and at the takeoff the gun turns in the character's space no faster than it
# turned in the stop it leaves or at the same body's aimed takeoff from a still stand. Before, the
# transition's own step sent the machine back to the ground state on the frame the jump was asked
# for: the body flew the whole jump on the ground's pose, and the stop clip's held pose gave way to
# the ground's in one tick, a step of the gun of 3 to 4 degrees (183 to 244 degrees a second).
# Read at `skeleton_updated`, after every modifier, on both bodies.
extends GdUnitTestSuite

const PISTOL := "res://gameplay/weapon/pistol.tres"
## Ticks of the aim before the jog, of the jog, and of the stop clip before the jump.
const AIM_TICKS := 20
const JOG_TICKS := 45
const STOP_TICKS := 8
## Ticks read from the jump press, and the updates in the jump state that are its takeoff.
const READ_TICKS := 24
const TAKEOFF_UPDATES := 4
## How many updates into the jump the body machine may still name another state.
const JUMP_STATE_BY := 2
## How much faster than the stop it leaves, or a still stand's takeoff, the gun may turn at the
## takeoff, and the least bound (degrees a second), as `test_jump_weapon_hold.gd` holds the jump.
const OVER_GROUND := 1.25
const TURN_FLOOR := 5.0

var _arena: PlayArena
var _player: Player
var _animation: CharacterAnimation
var _skeleton: Skeleton3D
var _hand := -1
var _muzzle_in_hand := Transform3D.IDENTITY
var _updates: Array[Dictionary] = []


func before_test() -> void:
	InputSim.release_all()


func after_test() -> void:
	InputSim.release_all()
	if _arena != null:
		AudioDrain.stop_all(_arena)
	_arena = null


func test_the_female_body_jumps_from_an_aimed_stop() -> void:
	await _takeoffs("female")


func test_the_male_body_jumps_from_an_aimed_stop() -> void:
	await _takeoffs("male")


func _takeoffs(body: String) -> void:
	await _player_with(body)
	var still := await _jump(false)
	var from_stop := await _jump(true)
	var still_turn := _fastest(still, true)
	var stop_turn := _fastest(from_stop, true)
	var in_stop := _fastest(from_stop, false)
	var bound := maxf(maxf(still_turn.whole, in_stop.whole), TURN_FLOOR) * OVER_GROUND
	var message := (
		(
			"%s: at the takeoff from a stop the gun turns %.0f degrees a second in the character's"
			+ " space (update %d of the jump; the muzzle's line %.0f), in the stop before it %.0f,"
			+ " at the takeoff from a still stand %.0f (the line %.0f)"
		)
		% [
			body,
			stop_turn.whole,
			stop_turn.at,
			stop_turn.line,
			in_stop.whole,
			still_turn.whole,
			still_turn.line,
		]
	)
	prints("AIMED_TAKEOFF " + message)
	assert_float(stop_turn.whole).override_failure_message(message).is_less_equal(bound)
	for run: Array[Dictionary] in [still, from_stop]:
		var first := _first_jump_state(run)
		(
			assert_int(first)
			. override_failure_message(
				(
					"%s, %s: the body machine is in the jump state from update %d of the jump"
					% [body, run[-1].way, first]
				)
			)
			. is_less_equal(JUMP_STATE_BY)
		)


# A player of `body` in an arena with the pistol out, looked at by a fixed camera behind it.
func _player_with(body: String) -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	if body == "male":
		var slot := _player.model
		var old := slot.rig()
		slot.remove_child(old)
		old.free()
		slot.add_child((load(CharacterBodies.MALE) as PackedScene).instantiate())
	var view := Camera3D.new()
	view.position = Vector3(0.0, 1.3, 3.0)
	_arena.add_child(view)
	view.make_current()
	await InputSim.ticks(get_tree(), 10)
	_animation = _player.get_node(^"Animation") as CharacterAnimation
	_skeleton = _player.model.skeleton()
	var pistol := load(PISTOL) as WeaponDef
	if _player.weapon == null or _player.weapon.definition != pistol:
		_player.loadout.give(pistol, 60)
	await InputSim.ticks(get_tree(), 60)
	assert_object(_player.weapon.definition).is_equal(pistol)
	# The muzzle rides a bone attachment, which moves later in the skeleton's own signal: read it
	# from the bone it rides and its fixed place there.
	var muzzle := _player.weapon.muzzle
	var cursor: Node = muzzle
	while cursor != null and not cursor is BoneAttachment3D:
		cursor = cursor.get_parent()
	assert_object(cursor).is_not_null()
	_hand = _skeleton.find_bone((cursor as BoneAttachment3D).bone_name)
	_muzzle_in_hand = _bone(_hand).affine_inverse() * muzzle.global_transform


# One aimed jump from the middle of the arena, read on every update: from a stop (the aim up, a
# jog, the stick let go, read from there, and the jump pressed while the stop clip plays) or from
# a still stand with the aim up (read from the press).
func _jump(from_stop: bool) -> Array[Dictionary]:
	_player.teleport(Vector3.ZERO, PI)
	await InputSim.ticks(get_tree(), 20)
	_updates.clear()
	var reader := _read.bind("from a stop" if from_stop else "from a still stand")
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	if from_stop:
		await InputSim.ticks(get_tree(), AIM_TICKS)
		InputSim.key(KEY_W, true)
		await InputSim.ticks(get_tree(), JOG_TICKS)
		InputSim.key(KEY_W, false)
		_skeleton.skeleton_updated.connect(reader)
		await InputSim.ticks(get_tree(), STOP_TICKS)
		(
			assert_bool(_animation.gait.transitions.is_playing())
			. override_failure_message("no stop clip plays when the jump is pressed")
			. is_true()
		)
	else:
		await InputSim.ticks(get_tree(), 40)
		(
			assert_bool(_animation.gait.transitions.is_playing())
			. override_failure_message("a transition plays at the still stand's jump")
			. is_false()
		)
		_skeleton.skeleton_updated.connect(reader)
	InputSim.key(KEY_SPACE, true)
	for tick in READ_TICKS:
		if tick == 10:
			InputSim.key(KEY_SPACE, false)
		await get_tree().physics_frame
	_skeleton.skeleton_updated.disconnect(reader)
	InputSim.release_all()
	await InputSim.ticks(get_tree(), 60)
	var run: Array[Dictionary] = []
	run.assign(_updates)
	return run


func _read(way: String) -> void:
	var muzzle := _bone(_hand) * _muzzle_in_hand
	(
		_updates
		. append(
			{
				"way": way,
				"state": Character.State.keys()[_player.state],
				"machine": _animation.body_state(),
				"in_body": _skeleton.global_transform.affine_inverse() * muzzle,
				"frame": Engine.get_physics_frames(),
				"raised": _animation.pistol_weights().y,
			}
		)
	)


# The fastest the gun turns in the character's space between updates a tick apart (degrees a
# second), whole (`whole`, and the update of the jump it is on, `at`) and along the muzzle's line
# (`line`): over the takeoff (the first `TAKEOFF_UPDATES` updates in the jump state), or before
# the jump.
func _fastest(run: Array[Dictionary], takeoff: bool) -> Dictionary:
	var most := {"whole": 0.0, "line": 0.0, "at": -1}
	var in_jump := 0
	for index in range(1, run.size()):
		var now := run[index]
		var last := run[index - 1]
		in_jump = in_jump + 1 if now.state == "JUMP" else 0
		var counted := in_jump > 0 and in_jump <= TAKEOFF_UPDATES
		if takeoff != counted or (not takeoff and now.state != "IDLE" and now.state != "WALK"):
			continue
		var ticks: int = now.frame - last.frame
		if ticks <= 0:
			continue
		assert_float(now.raised).is_greater_equal(1.0)
		var seconds := ticks / float(Engine.physics_ticks_per_second)
		var from: Transform3D = last.in_body
		var to: Transform3D = now.in_body
		var whole := rad_to_deg(
			from.basis.get_rotation_quaternion().angle_to(to.basis.get_rotation_quaternion())
		)
		if whole / seconds > most.whole:
			most.whole = whole / seconds
			most.at = in_jump
		most.line = maxf(most.line, rad_to_deg((-from.basis.z).angle_to(-to.basis.z)) / seconds)
	return most


# The first update in the jump state (1 the first) on which the body machine is in its jump state
# too, or a large number if it never is.
func _first_jump_state(run: Array[Dictionary]) -> int:
	var in_jump := 0
	for entry in run:
		if entry.state != "JUMP":
			continue
		in_jump += 1
		if entry.machine == CharacterAnimation.JUMP:
			return in_jump
	return 1 << 20


func _bone(bone: int) -> Transform3D:
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(bone)
