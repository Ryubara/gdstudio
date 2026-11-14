# The weapon in the hands is drawn in the frame its place is worked out (gdstudio #1473): with
# physics interpolation on, a node a script places outside the physics tick (the rifle's `Pivot`
# from the skeleton's modifiers, the pistol's `BoneAttachment3D` at `skeleton_updated`) was drawn
# between its last two places, a frame behind the skin, which draws the bones of this update: the
# rifle trailed the hands by a frame of the pose's movement (tens of millimetres at a sprint,
# 0.7 m on the frame a slide's end jumped to the crouch). Read after every frame at the suites' 60
# ticks, where the renderer was sent the meshes (`AfterFrameReader`), through a sprint, a sprint
# into a slide that ends in the crouch, standing up and an aim while walking: the rifle's grip and
# hand guard are drawn where this update puts them from the drawn hands (the hand on its place or
# not), on both bodies, and the pistol where its seat has it on the drawn hand. Jumps and their
# landings are `test_rifle_drawn_hands.gd`'s (gdstudio #1464, the same cause).
extends GdUnitTestSuite

const RIFLE := "res://gameplay/weapon/rifle.tres"
## How far a weapon may be drawn from where it is on the drawn skin, in metres.
const DRAWN_GAP := 0.001
## The fewest reads a run makes (a run that read none would prove nothing).
const MIN_READS := 150

var _arena: PlayArena
var _player: Player
var _skeleton: Skeleton3D
var _reader: AfterFrameReader
# What the skin draws this update (the bones forget the modifiers after the frame): each watched
# bone's pose in the skeleton's space, by name.
var _poses := {}
var _names: Array[StringName] = []
var _bones := PackedInt32Array()
# What is read after each frame: [the drawn gap in metres, the frame, what was measured].
var _gaps: Array[Array] = []
var _measure: Callable


func after_test() -> void:
	InputSim.release_all()
	if _arena != null:
		AudioDrain.stop_all(_arena)
	_arena = null


func test_the_rifle_is_drawn_on_the_drawn_hands(
	body: String, _test_parameters := [["female"], ["male"]]
) -> void:
	await _player_with(body, true)
	assert_str(_player.weapon.definition.display_name).is_equal("Rifle")
	var rifle := _player.model.get_node(^"RifleHeld/Pivot/Rifle") as Node3D
	var mesh := rifle.find_children("*", "VisualInstance3D", true, false)[0] as VisualInstance3D
	var targets := {
		&"hand_r": rifle.get_node(^"RightHandTarget") as Node3D,
		&"hand_l": rifle.get_node(^"LeftHandTarget") as Node3D,
	}
	_watch([&"hand_r", &"hand_l"])
	_measure = func() -> void:
		var drawn_mesh := mesh.get_global_transform_interpolated()
		var to_mesh := mesh.global_transform.affine_inverse()
		for bone: StringName in targets:
			var target: Node3D = targets[bone]
			# The hand's place on the rifle from the hand, as worked out in this update and as drawn
			# (the same, the hand on it or not, when both are drawn from this update).
			var placed: Transform3D = _skeleton.global_transform * _poses[bone]
			var worked_out := target.global_position - placed.origin
			var gun := (drawn_mesh * to_mesh * target.global_transform).origin
			var drawn := gun - _drawn_bone(bone)
			_gaps.append([drawn.distance_to(worked_out), Engine.get_process_frames(), bone])
	await _tour()
	_assert_drawn_together("%s rifle" % body)


func test_the_pistol_is_drawn_on_the_drawn_hand() -> void:
	await _player_with("female", false)
	assert_str(_player.weapon.definition.display_name).is_equal("Pistol")
	var seat := _player.model.get_node(^"PistolHeld") as Node3D
	var mesh := seat.find_children("*", "VisualInstance3D", true, false)[0] as VisualInstance3D
	_watch([&"hand_r"])
	_measure = func() -> void:
		# Where the mesh is on the skin in this update, carried by the drawn skeleton.
		var on_skin := _skeleton.global_transform.affine_inverse() * mesh.global_transform
		var expected := (_skeleton.get_global_transform_interpolated() * on_skin).origin
		var drawn := mesh.get_global_transform_interpolated().origin
		_gaps.append([drawn.distance_to(expected), Engine.get_process_frames(), &"pistol"])
	await _tour()
	_assert_drawn_together("pistol")


# A player of `body` in an arena with the rifle (or the pistol it starts with) in the hands, a
# camera as the game has, and a reader after each frame.
func _player_with(body: String, rifle: bool) -> void:
	InputSim.release_all()
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
	_skeleton = _player.model.skeleton()
	if rifle:
		_player.loadout.give(load(RIFLE) as WeaponDef, 60)
	await InputSim.ticks(get_tree(), 60)
	_reader = auto_free(AfterFrameReader.new())
	add_child(_reader)
	_gaps.clear()
	_poses.clear()


# Records `names` at each update outside the tick and asks for a read after the frame.
func _watch(names: Array[StringName]) -> void:
	_names = names
	_bones.clear()
	for bone in names:
		_bones.append(_skeleton.find_bone(bone))
	_skeleton.skeleton_updated.connect(_on_updated)
	_reader.read = func() -> void:
		if _poses.size() == _names.size():
			_measure.call()


func _on_updated() -> void:
	if Engine.is_in_physics_frame():
		return
	for index in _names.size():
		_poses[_names[index]] = _skeleton.get_bone_global_pose(_bones[index])
	_reader.ask()


func _drawn_bone(bone: StringName) -> Vector3:
	return (_skeleton.get_global_transform_interpolated() * (_poses[bone] as Transform3D)).origin


# Fast moves, as a player makes them: a sprint into a slide that ends in the crouch, standing up,
# and an aim while walking.
func _tour() -> void:
	var tree := get_tree()
	InputSim.key(KEY_W, true)
	InputSim.key(KEY_SHIFT, true)
	await InputSim.ticks(tree, 40)
	InputSim.key(KEY_C, true)
	await InputSim.ticks(tree, 70)
	InputSim.key(KEY_SHIFT, false)
	InputSim.key(KEY_C, false)
	await InputSim.ticks(tree, 30)
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	await InputSim.ticks(tree, 30)
	InputSim.release_all()
	await InputSim.ticks(tree, 2)
	_skeleton.skeleton_updated.disconnect(_on_updated)


func _assert_drawn_together(tag: String) -> void:
	(
		assert_int(_gaps.size())
		. override_failure_message("%s: %d reads after the frame" % [tag, _gaps.size()])
		. is_greater_equal(MIN_READS)
	)
	var worst: Array = [0.0, -1, &""]
	var over := 0
	for gap: Array in _gaps:
		if gap[0] > DRAWN_GAP:
			over += 1
		if gap[0] > worst[0]:
			worst = gap
	var message := (
		"%s: drawn %.1f mm off the drawn skin at frame %d (%s); %d of %d reads over %.1f mm"
		% [tag, worst[0] * 1000.0, worst[1], worst[2], over, _gaps.size(), DRAWN_GAP * 1000.0]
	)
	assert_float(worst[0]).override_failure_message(message).is_less_equal(DRAWN_GAP)
