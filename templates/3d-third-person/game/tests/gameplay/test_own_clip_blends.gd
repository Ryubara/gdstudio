# Every move into or out of one of our own clips (the gaits, the starts and stops, the crouch)
# blends: no bone moves further in one frame than the clips themselves move it (gdstudio #1416).
# The player is stepped and its tree advanced by hand; the drawn pose (after every modifier) is read
# at `skeleton_updated`, and the largest move of a body bone in the model's frame, from one frame to
# the next, is compared with the largest the gait moves it while it plays alone.
#
# On main the momentum blend started on the frame the state machine reported its new state, a
# frame before the tree drew it, so it carried nothing and the new pose arrived whole: 88 cm in one
# frame at a walk's stop, 68 cm into the crouch. And the starts never played: the body is past
# `standing_speed` on the tick it is asked to move, so the idle snapped to the walk.
extends GdUnitTestSuite

# Parts of the bone names left out: what the hold, the IK and the root move on their own.
const SKIPPED: Array[String] = [
	"thumb", "index", "middle", "ring", "pinky", "ik_", "root", "socket"
]
# A frame's move may reach this many times the gait's own largest, and never less than `FLOOR`.
const SHARE := 1.6
const FLOOR := 0.15

var _arena: PlayArena
var _player: Player
var _animation: CharacterAnimation
var _skeleton: Skeleton3D
var _bones: Array[int] = []
var _last: Array[Vector3] = []
var _moves: Array[float] = []


func before_test() -> void:
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3.ZERO)
	_animation = _player.get_node("Animation")
	CommandDriver.take(_player)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_skeleton = _player.model.skeleton()
	for bone in _skeleton.get_bone_count():
		var bone_name := String(_skeleton.get_bone_name(bone)).to_lower()
		if not SKIPPED.any(func(part: String) -> bool: return bone_name.contains(part)):
			_bones.append(bone)
	_skeleton.skeleton_updated.connect(_on_skeleton_updated)
	_animation.set_throttled(true)


func after_test() -> void:
	if (
		is_instance_valid(_skeleton)
		and _skeleton.skeleton_updated.is_connected(_on_skeleton_updated)
	):
		_skeleton.skeleton_updated.disconnect(_on_skeleton_updated)


func _on_skeleton_updated() -> void:
	var largest := 0.0
	var seen := _last.size() == _bones.size()
	_last.resize(_bones.size())
	for index in _bones.size():
		var place := _skeleton.get_bone_global_pose(_bones[index]).origin
		if seen:
			largest = maxf(largest, place.distance_to(_last[index]))
		_last[index] = place
	_moves.append(largest)


func _command(push: float, walk := false, sprint := false, crouch := false) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.move = Vector2(0.0, push)
	command.walk = walk
	command.sprint = sprint
	command.crouch = crouch
	return command


# Steps `count` ticks of `command`; the largest frame-to-frame move of a bone over them, in metres.
func _largest(command: PlayerCommand, count: int) -> float:
	var step := CommandDriver.tick_seconds()
	var from := _moves.size()
	for tick in count:
		await get_tree().physics_frame
		_player.step(command, step)
		_animation.advance(step)
	# One more update, for a skeleton that draws a frame after the tree.
	await get_tree().process_frame
	var largest := 0.0
	for index in range(from, _moves.size()):
		largest = maxf(largest, _moves[index])
	return largest


# Starts from standing, moves with `moving` long enough to play the gait alone, stops; four times,
# each stop at another point of the gait's cycle. Returns `[start, gait, stop]`, each the largest
# frame-to-frame move of a bone.
func _start_and_stop(moving: PlayerCommand) -> Array[float]:
	var found: Array[float] = [0.0, 0.0, 0.0]
	for lap in 4:
		await _largest(_command(0.0), 40)
		found[0] = maxf(found[0], await _largest(moving, 50))
		found[1] = maxf(found[1], await _largest(moving, 40 + lap * 7))
		found[2] = maxf(found[2], await _largest(_command(0.0), 80))
	return found


func _check(label: String, largest: float, gait: float) -> void:
	var limit := maxf(gait * SHARE, FLOOR)
	(
		assert_float(largest)
		. override_failure_message(
			(
				"%s: a bone moved %.0f cm in one frame; the gait itself moves one %.0f cm at most"
				% [label, largest * 100.0, gait * 100.0]
			)
		)
		. is_less_equal(limit)
	)


func test_a_walk_starts_and_stops_with_no_snap() -> void:
	var found := await _start_and_stop(_command(1.0, true))
	_check("the walk's start", found[0], found[1])
	_check("the walk's stop", found[2], found[1])


func test_a_jog_starts_and_stops_with_no_snap() -> void:
	var found := await _start_and_stop(_command(1.0))
	_check("the jog's start", found[0], found[1])
	_check("the jog's stop", found[2], found[1])


func test_a_sprint_starts_and_stops_with_no_snap() -> void:
	var found := await _start_and_stop(_command(1.0, false, true))
	_check("the sprint's start", found[0], found[1])
	_check("the sprint's stop", found[2], found[1])


func test_the_crouch_goes_down_and_up_with_no_snap() -> void:
	await _largest(_command(0.0), 40)
	var still := await _largest(_command(0.0), 30)
	var down := await _largest(_command(0.0, false, false, true), 60)
	assert_str(String(_animation.body_state())).is_equal(String(CharacterAnimation.CROUCH))
	var up := await _largest(_command(0.0), 60)
	_check("into the crouch", down, still)
	_check("out of the crouch", up, still)


func test_a_crouch_during_a_stop_is_kept() -> void:
	# A stop that plays is ended by the crouch; the machine goes on to the crouch, not back to the
	# ground state the transition would have handed over to.
	await _largest(_command(0.0), 40)
	await _largest(_command(1.0), 60)
	await _largest(_command(0.0), 3)
	assert_bool(_animation.gait.transitions.is_playing()).is_true()
	await _largest(_command(0.0, false, false, true), 30)
	assert_str(String(_animation.body_state())).is_equal(String(CharacterAnimation.CROUCH))


func test_a_start_plays_when_the_body_is_asked_to_move(
	walk: bool,
	sprint: bool,
	start: String,
	_test_parameters := [
		[true, false, "gds/Idle_To_Walk"],
		[false, false, "gds/Idle_To_Jog"],
		[false, true, "gds/Idle_To_Sprint"],
	]
) -> void:
	# The template's acceleration has the body past `standing_speed` on the first tick of the
	# press; the start is picked all the same.
	await _largest(_command(0.0), 40)
	await _largest(_command(1.0, walk, sprint), 2)
	assert_bool(_animation.gait.transitions.is_playing()).is_true()
	assert_str(String(_animation.gait.transitions.clip)).starts_with(start)
