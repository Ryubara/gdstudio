# Both hands are drawn on the rifle through a jump and its landing (gdstudio #1464). The pose the
# skeleton ends an update with had them on, while the frames drawn at each landing showed the
# rifle 145 mm off them: the engine draws a physics-interpolated node between its place at the
# last two ticks (`SceneTreeFTI`), and the hold moves the rifle every frame, outside the ticks, so
# the rifle was drawn where the hold had put it a frame before while the skin is drawn with the
# bones of this frame. So this reads what the engine draws: the rifle's hand places and the
# skeleton by `get_global_transform_interpolated()`, at the start of the frame after an update
# with no tick between them (the physics ticks slower than the frames, as in `test_aim_chest.gd`),
# and the hands' bones as the skin got them in that update. Driven by simulated keys and mouse, on
# both bodies: a standing jump, a running jump and an aimed jump.
extends GdUnitTestSuite

const RIFLE := "res://gameplay/weapon/rifle.tres"
## The physics rate of the suite: three drawn frames a tick (the suites run at 60 frames a second),
## so two frames in three start with no tick since the last update and show the interpolation.
const TICKS_PER_SECOND := 20
## How far a hand's drawn bone may be from its drawn place on the rifle, in metres. The pose has
## them 0.0 mm apart; before the fix a standing landing read 145 mm (both bodies, both hands),
## after it 0.2 mm at most.
const HAND := 0.002
## Ticks after the jump key for the jump and its landing to be over.
const JUMP_TICKS := 40

var _arena: PlayArena
var _player: Player
var _skeleton: Skeleton3D
var _hold: TwoHandHold
var _bones := PackedInt32Array()
var _targets: Array[Node3D] = []
var _poses: Array[Transform3D] = [Transform3D(), Transform3D()]
var _updated_tick := -1
var _worst := [0.0, 0.0]
var _worst_at := ["", ""]
var _frames := 0
var _landed := 0
var _label := ""
var _jumps: Array[String] = []


func before_test() -> void:
	InputSim.release_all()
	# One suite object runs every parameter: what the last run counted goes.
	_updated_tick = -1
	_worst = [0.0, 0.0]
	_worst_at = ["", ""]
	_frames = 0
	_landed = 0
	_jumps.clear()


func after_test() -> void:
	Engine.physics_ticks_per_second = 60
	InputSim.release_all()
	if get_tree().process_frame.is_connected(_on_frame):
		get_tree().process_frame.disconnect(_on_frame)
	if _arena != null:
		AudioDrain.stop_all(_arena)
	_arena = null


func test_the_hands_are_drawn_on_the_rifle_through_jumps_and_landings(
	body: String, _test_parameters := [["female"], ["male"]]
) -> void:
	await _player_with_rifle(body)
	# A standing jump.
	await _jump("standing")
	# A running jump.
	InputSim.key(KEY_W, true)
	await InputSim.ticks(get_tree(), 10)
	await _jump("running")
	InputSim.key(KEY_W, false)
	# An aimed jump.
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	await InputSim.ticks(get_tree(), 10)
	await _jump("aimed")
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, false)
	var landed := "%s: landings seen: %s" % [body, _jumps]
	assert_int(_landed).override_failure_message(landed).is_equal(3)
	assert_int(_frames).is_greater(60)
	for hand in 2:
		(
			assert_float(_worst[hand])
			. override_failure_message(
				(
					"%s: the %s hand is drawn %.1f mm off its place on the rifle (%s)"
					% [body, ["right", "left"][hand], _worst[hand] * 1000.0, _worst_at[hand]]
				)
			)
			. is_less(HAND)
		)


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
	var view := Camera3D.new()
	view.position = Vector3(0.0, 1.3, 3.0)
	_arena.add_child(view)
	view.make_current()
	await InputSim.ticks(get_tree(), 10)
	_player.loadout.give(load(RIFLE) as WeaponDef, 60)
	await InputSim.ticks(get_tree(), 60)
	assert_str(_player.weapon.definition.display_name).is_equal("Rifle")
	Engine.physics_ticks_per_second = TICKS_PER_SECOND
	_skeleton = _player.model.skeleton()
	_hold = _player.model.find_children("*", "TwoHandHold", true, false)[0] as TwoHandHold
	_targets = [
		_hold.find_child("RightHandTarget", true, false) as Node3D,
		_hold.find_child("LeftHandTarget", true, false) as Node3D,
	]
	_bones = PackedInt32Array([_skeleton.find_bone(&"hand_r"), _skeleton.find_bone(&"hand_l")])
	_skeleton.skeleton_updated.connect(_on_updated)
	get_tree().process_frame.connect(_on_frame)
	await InputSim.ticks(get_tree(), 10)


func _jump(label: String) -> void:
	while not _player.is_on_floor():
		await get_tree().physics_frame
	await InputSim.ticks(get_tree(), 10)
	var was_on_floor := true
	InputSim.key(KEY_SPACE, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_SPACE, false)
	var left := false
	for tick in JUMP_TICKS:
		await get_tree().physics_frame
		var on_floor := _player.is_on_floor()
		if not on_floor:
			left = true
		if left and on_floor and not was_on_floor:
			_landed += 1
			_jumps.append(label)
		was_on_floor = on_floor
		_label = "%s jump, tick %d" % [label, tick]


# The bones the skin gets in this update (the skeleton forgets the modifiers' pose after it).
func _on_updated() -> void:
	for hand in 2:
		_poses[hand] = _skeleton.get_bone_global_pose(_bones[hand])
	_updated_tick = Engine.get_physics_frames()


# The start of a frame: the engine has interpolated every node for it. With no tick since the last
# update, what it shows is the last update's bones under the skeleton's drawn place and the
# rifle's hand places where it draws them.
func _on_frame() -> void:
	if _updated_tick < 0 or Engine.get_physics_frames() != _updated_tick:
		return
	if not _hold.is_visible_in_tree():
		return
	_frames += 1
	var skeleton_drawn := _skeleton.get_global_transform_interpolated()
	for hand in 2:
		var bone_drawn := (skeleton_drawn * _poses[hand]).origin
		var place_drawn := _targets[hand].get_global_transform_interpolated().origin
		var off := bone_drawn.distance_to(place_drawn)
		if off > _worst[hand]:
			_worst[hand] = off
			_worst_at[hand] = _label
