# The aim layer comes on by as much as the weapon is up and never folds the upper body (kit
# #1318): on every frame of an aim going up and coming down, standing, crouched and lying, the
# chest turns by the aim's weight times the turn the full aim needs, never more. The layer used to
# solve its turn on the drawn pose, the aim pose blended with the carry pose whose muzzle points at
# the floor, and asked for a 70 degree lift there; and it wrote each bone once per pass, so Godot's
# `influence` blended from the first pass and the chest took that lift whole (80 degrees at a tenth
# of the aim). Read from the chest (`spine_03`) after the skeleton's modifiers, against its pose
# right before the layer, which a probe modifier records.
extends GdUnitTestSuite

## Degrees the chest may turn past its share of the full aim's turn on any frame (the share is the
## aim's weight).
const MARGIN := 3.0
## Degrees the chest turns at most once a standing aim is all the way up (the clips aim it).
const STANDING_FULL := 6.0


# Records a bone's pose where it sits among the skeleton's modifiers.
class PoseProbe:
	extends SkeletonModifier3D
	var bone := -1
	var recorded := Transform3D.IDENTITY

	func _process_modification_with_delta(_delta: float) -> void:
		var skeleton := get_skeleton()
		if skeleton != null and bone >= 0:
			recorded = HandPoseModifier.global_pose(skeleton, bone)


var _arena: PlayArena
var _player: Player
var _layer: AimLayer
var _probe: PoseProbe
var _chest := -1
# Per drawn frame: the aim's weight and the degrees the layer turned the chest.
var _weights := PackedFloat32Array()
var _turns := PackedFloat32Array()


func before_test() -> void:
	InputSim.release_all()
	_arena = auto_free(PlayArena.new())
	add_child(_arena)
	_player = _arena.add_player(Vector3(0.0, 0.0, 26.0))
	CommandDriver.take(_player)
	_layer = _player.get_node("AimLayer")
	await InputSim.ticks(get_tree(), 6)
	var skeleton := _player.model.skeleton()
	_chest = skeleton.find_bone(&"spine_03")
	_probe = PoseProbe.new()
	_probe.bone = _chest
	skeleton.add_child(_probe)
	skeleton.move_child(_probe, _layer.modifier().get_index())
	skeleton.skeleton_updated.connect(_record)
	_weights.clear()
	_turns.clear()


func after_test() -> void:
	InputSim.release_all()
	AudioDrain.stop_all(_arena)


func _record() -> void:
	var skeleton := _player.model.skeleton()
	var drawn := HandPoseModifier.global_pose(skeleton, _chest)
	var change := drawn.basis.orthonormalized() * _probe.recorded.basis.orthonormalized().inverse()
	_weights.append(_layer.weight())
	_turns.append(rad_to_deg(change.get_rotation_quaternion().get_angle()))


# Settles into the move, then aims for `held` ticks and lets go for as long; returns the turn of
# the full aim (the most the chest turns while the weight is 1).
func _aim_in_and_out(command: PlayerCommand, held: int = 30) -> float:
	await CommandDriver.run(get_tree(), [_player], command, 60)
	_weights.clear()
	_turns.clear()
	command.aim = true
	await CommandDriver.run(get_tree(), [_player], command, held)
	command.aim = false
	await CommandDriver.run(get_tree(), [_player], command, held)
	var full := 0.0
	var between := 0
	for index in _weights.size():
		if _weights[index] >= 1.0:
			full = maxf(full, _turns[index])
		elif _weights[index] > 0.0:
			between += 1
	var middle := _weights[_weights.size() / 4]
	assert_float(middle).override_failure_message("never aimed (%.2f)" % middle).is_equal(1.0)
	assert_int(between).override_failure_message("no frame between off and on").is_greater(3)
	return full


# Fails on a frame between off and on where the chest turns more than the aim's weight times the
# full aim's turn `full`, and a margin.
func _assert_no_fold(label: String, full: float) -> void:
	for index in _weights.size():
		var weight := _weights[index]
		if weight <= 0.0 or weight >= 1.0:
			continue
		var most := weight * full + MARGIN
		(
			assert_float(_turns[index])
			. override_failure_message(
				(
					"%s: at an aim weight of %.2f the chest turns %.1f degrees (most %.1f, full %.1f)"
					% [label, weight, _turns[index], most, full]
				)
			)
			. is_less_equal(most)
		)


func _command(pitch: float) -> PlayerCommand:
	var look := CommandCodec.direction_from_angles(0.0, deg_to_rad(pitch))
	return CommandDriver.walking(Vector3.ZERO, look)


func test_standing_the_chest_never_folds_as_the_aim_goes_up_and_down() -> void:
	for pitch: float in [0.0, 30.0, -30.0]:
		var full := await _aim_in_and_out(_command(pitch))
		if pitch == 0.0:
			assert_float(full).is_less(STANDING_FULL)
		_assert_no_fold("standing, pitch %s" % pitch, full)


func test_crouched_the_chest_never_folds_as_the_aim_goes_up_and_down() -> void:
	var command := _command(0.0)
	command.crouch = true
	var full := await _aim_in_and_out(command)
	assert_bool(_player.crouching).is_true()
	_assert_no_fold("crouched", full)


func test_lying_the_chest_never_folds_as_the_aim_goes_up_and_down() -> void:
	var command := _command(0.0)
	command.prone = true
	var full := await _aim_in_and_out(command)
	assert_bool(_player.prone).is_true()
	_assert_no_fold("lying", full)


func test_a_shot_from_the_carry_keeps_the_chest_too() -> void:
	# Fire aims by itself and shoots once the arm is half up; the shot keeps the turn found before
	# it, which was the fold's whole lift.
	var command := _command(0.0)
	await CommandDriver.run(get_tree(), [_player], command, 60)
	_weights.clear()
	_turns.clear()
	command.fire = true
	command.fire_pressed = true
	await CommandDriver.run(get_tree(), [_player], command, 1)
	command.fire_pressed = false
	await CommandDriver.run(get_tree(), [_player], command, 30)
	command.fire = false
	await CommandDriver.run(get_tree(), [_player], command, 40)
	var full := 0.0
	for index in _weights.size():
		if _weights[index] >= 1.0:
			full = maxf(full, _turns[index])
	assert_float(_turns[_turns.size() - 1]).is_equal(0.0)
	# Standing, the clips aim the pistol already: the kept turn is a few degrees, not a lift.
	(
		assert_float(full)
		. override_failure_message("the shot keeps a turn of %.1f degrees" % full)
		. is_less(STANDING_FULL)
	)
	_assert_no_fold("a shot from the carry", full)
