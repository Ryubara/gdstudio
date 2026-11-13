# The trunk through a switch to the rifle (kit #1327): as the rifle comes out after the pistol, the
# chest turns to the hold's `chest_turn` and no further, the spine under it never stands farther
# from the model's front than the chest, and the head keeps the facing the locomotion clip gives
# it. Before kit #1333 a stop out of a run swung the clip's chest 47 degrees to the left while the
# pistol went down; the stance took 77 degrees off it, a third on each spine bone, and the head
# rode the chest: spine_02 stood 42 degrees and the head 77 degrees to the right for three frames.
# The player is driven with simulated input, standing, out of a run and out of a sprint, given the
# rifle as the pickup gives it and switched to it by its key, on both bodies, and read on every
# update of the skeleton from the moment the switch starts until the rifle has settled.
extends GdUnitTestSuite

const RIFLE := "res://gameplay/weapon/rifle.tres"
## The spine bones the rifle's stance turns, from the hips up; the last is the chest.
const SPINE: Array[String] = ["spine_01", "spine_02", "spine_03"]
## How far past the hold's `chest_turn` a spine bone may stand from the model's front, in degrees:
## the stance puts the chest on it to a tenth of a degree.
const SPINE_SLACK := 1.0
## How far the head may stand from the model's front through the switch, in degrees: the clips
## keep it within 5; it stood 77 degrees off before kit #1333.
const HEAD_LIMIT := 15.0
## The ticks read after the switch starts: the pistol's `holster_time` and the rifle's
## `draw_time` with the blends' settling after them.
const READ_TICKS := 90

var _arena: PlayArena
var _player: Player
var _skeleton: Skeleton3D
var _reading := false
var _worst: Dictionary[String, float] = {}
var _worst_at: Dictionary[String, int] = {}
var _updates := 0


func before_test() -> void:
	InputSim.release_all()


func after_test() -> void:
	InputSim.release_all()
	if _arena != null:
		AudioDrain.stop_all(_arena)
	_arena = null


# The rifle given as the floating pickup gives it (`WeaponLoadout.give`, brought out at once),
# standing still, out of a run that stops as it comes out, and out of a sprint that stops.
func test_the_trunk_stays_on_the_chest_turn_as_the_rifle_is_picked_up(
	body: String,
	gait: String,
	_test_parameters := [
		["female", "standing"],
		["female", "run"],
		["female", "sprint"],
		["male", "standing"],
		["male", "run"],
		["male", "sprint"],
	]
) -> void:
	await _player_in(body)
	await _move(gait)
	_start_reading()
	_player.loadout.give(load(RIFLE) as WeaponDef, 60)
	await _stop_and_read(gait)
	_assert_trunk("%s, %s, picked up" % [body, gait])


# The rifle already carried, switched to from the pistol by its key, standing and out of a run.
func test_the_trunk_stays_on_the_chest_turn_as_the_rifle_is_switched_to(
	body: String,
	gait: String,
	_test_parameters := [
		["female", "standing"],
		["female", "run"],
		["male", "standing"],
		["male", "run"],
	]
) -> void:
	await _player_in(body)
	_player.loadout.give(load(RIFLE) as WeaponDef, 60)
	await InputSim.ticks(get_tree(), 60)
	await _tap(KEY_1)
	await InputSim.ticks(get_tree(), 60)
	assert_str(_player.weapon.definition.display_name).is_equal("Pistol")
	await _move(gait)
	_start_reading()
	await _tap(KEY_2)
	await _stop_and_read(gait)
	_assert_trunk("%s, %s, switched" % [body, gait])


# A player of `body` in an arena with the pistol out, read on every update of its skeleton.
func _player_in(body: String) -> void:
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
	_skeleton.skeleton_updated.connect(_read)
	assert_str(_player.weapon.definition.display_name).is_equal("Pistol")


# Gets the character into `gait` (standing: still) and holds it long enough for the blends to end.
func _move(gait: String) -> void:
	if gait == "standing":
		await InputSim.ticks(get_tree(), 30)
		return
	InputSim.key(KEY_W, true)
	if gait == "sprint":
		InputSim.key(KEY_SHIFT, true)
	await InputSim.ticks(get_tree(), 60)


# Keeps moving a third of a second into the switch (the rifle tour's walk into the pickup), stops,
# and reads until the rifle has settled.
func _stop_and_read(gait: String) -> void:
	if gait != "standing":
		await InputSim.ticks(get_tree(), 20)
		InputSim.key(KEY_W, false)
		InputSim.key(KEY_SHIFT, false)
		await InputSim.ticks(get_tree(), READ_TICKS - 20)
	else:
		await InputSim.ticks(get_tree(), READ_TICKS)
	_reading = false
	assert_str(_player.weapon.definition.display_name).is_equal("Rifle")


func _start_reading() -> void:
	_worst.clear()
	_worst_at.clear()
	_updates = 0
	_reading = true


func _tap(key: Key) -> void:
	InputSim.key(key, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(key, false)


func _assert_trunk(tag: String) -> void:
	var hold := _player.model.get_node_or_null("RifleHeld") as TwoHandHold
	assert_object(hold).is_not_null()
	var limit := absf(hold.chest_turn) + SPINE_SLACK
	var line := "TRUNK %-32s" % tag
	for key in _worst:
		line += " %s %.1f@%d" % [key, _worst[key], _worst_at[key]]
	print(line)
	assert_int(_updates).is_greater(READ_TICKS / 2)
	for bone in SPINE:
		(
			assert_float(_worst[bone])
			. override_failure_message(
				(
					(
						"%s: %s stood %.1f degrees from the model's front on update %d of the switch, "
						+ "past the chest turn's %.1f"
					)
					% [tag, bone, _worst[bone], _worst_at[bone], limit]
				)
			)
			. is_less_equal(limit)
		)
	(
		assert_float(_worst["Head"])
		. override_failure_message(
			(
				"%s: the head looked %.1f degrees off the model's front on update %d of the switch"
				% [tag, _worst["Head"], _worst_at["Head"]]
			)
		)
		. is_less_equal(HEAD_LIMIT)
	)


# One update of the skeleton, after its modifiers: how far each spine bone and the head stand from
# the model's front about the up axis, the worst of each kept with the update it came on.
func _read() -> void:
	if not _reading:
		return
	_updates += 1
	for bone in SPINE + ["Head"]:
		var off := absf(_yaw(bone))
		if off > _worst.get(bone, -1.0):
			_worst[bone] = off
			_worst_at[bone] = _updates


# Where the turn of `bone` from its rest sends the model's front, in degrees about the up axis
# (the way the hold's `chest_turn` counts).
func _yaw(bone: String) -> float:
	var index := _skeleton.find_bone(bone)
	var turned := (
		_skeleton.get_bone_global_pose(index).basis.orthonormalized()
		* _skeleton.get_bone_global_rest(index).basis.orthonormalized().inverse()
	)
	var ahead := turned * Vector3.BACK
	return rad_to_deg(atan2(ahead.x, ahead.z))
