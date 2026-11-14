# The trunk through a switch to the rifle (kit #1327): as the rifle comes out after the pistol, the
# chest turns to the hold's `chest_turn` and no further, the spine under it never stands farther
# from the model's front than the chest, and the head keeps the facing the locomotion clip gives
# it. Before kit #1333 a stop out of a run swung the clip's chest 47 degrees to the left while the
# pistol went down; the stance took 77 degrees off it, a third on each spine bone, and the head
# rode the chest: spine_02 stood 42 degrees and the head 77 degrees to the right for three frames.
# The player is driven with simulated input, standing, out of a run and out of a sprint, given the
# rifle as the pickup gives it and switched to it by its key, on both bodies, and read on every
# update of the skeleton from the moment the switch starts until the rifle has settled.
#
# Under a clip whose chest swings far on the top bone alone (a library run: 0, 8 and 47 degrees from
# the front on the three spine bones), taking the gap to `chest_turn` off in even thirds left the
# lower spine twisted past the chest: spine_01 27 and spine_02 44 degrees with the chest on its 30
# (kit #1379). `ChestSwing` plays such a clip over the template's own: the chest 45 degrees each way
# over a stride, the head turned back by as much the way a run counters it in the neck.
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
## The lower spine bones: under a wide chest swing they must stay inside `chest_turn` all through
## the switch, while the chest itself comes from the clip's swing to the hold's turn.
const LOWER: Array[String] = ["spine_01", "spine_02"]
## How far `ChestSwing` swings the chest each way, in degrees, and over how long, in seconds.
const WIDE_SWING := 45.0
const SWING_PERIOD := 0.7
## The ticks read once the rifle has settled under the wide swing: more than a stride.
const SETTLED_TICKS := 30

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


# Under a clip that swings the chest 45 degrees each way on the top bone (kit #1379): through the
# pickup the lower spine stays inside the chest's turn, and once the rifle has settled the whole
# spine does, standing and out of a run.
func test_the_lower_spine_stays_inside_the_chest_turn_under_a_wide_chest_swing(
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
	var swing := ChestSwing.new()
	swing.swing = WIDE_SWING
	swing.period = SWING_PERIOD
	_skeleton.add_child(swing)
	_skeleton.move_child(swing, 0)
	await _move(gait)
	_start_reading()
	_player.loadout.give(load(RIFLE) as WeaponDef, 60)
	await _stop_and_read(gait)
	_assert_trunk("%s, %s, wide swing" % [body, gait], LOWER)
	_start_reading()
	await InputSim.ticks(get_tree(), SETTLED_TICKS)
	_reading = false
	_assert_trunk("%s, %s, wide swing, settled" % [body, gait], SPINE, SETTLED_TICKS / 2)


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


func _assert_trunk(tag: String, bones := SPINE, least := READ_TICKS / 2) -> void:
	var hold := _player.model.get_node_or_null("RifleHeld") as TwoHandHold
	assert_object(hold).is_not_null()
	var limit := absf(hold.chest_turn) + SPINE_SLACK
	var line := "TRUNK %-32s" % tag
	for key in _worst:
		line += " %s %.1f@%d" % [key, _worst[key], _worst_at[key]]
	print(line)
	assert_int(_updates).is_greater(least)
	for bone in bones:
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


# A locomotion clip whose chest swings far on the top bone alone, played over the template's own
# (kit #1379): the first modifier, it turns `spine_03` about the model's up axis by `swing` degrees
# each way over `period` seconds and the head back by as much, as a run counters the shoulders'
# swing in the neck.
class ChestSwing:
	extends SkeletonModifier3D

	var swing := 45.0
	var period := 0.7
	var _time := 0.0

	func _process_modification_with_delta(delta: float) -> void:
		var skeleton := get_skeleton()
		if skeleton == null:
			return
		_time += delta
		var angle := deg_to_rad(swing * sin(TAU * _time / period))
		_turn(skeleton, skeleton.find_bone("spine_03"), angle)
		_turn(skeleton, skeleton.find_bone("Head"), -angle)

	func _turn(skeleton: Skeleton3D, bone: int, angle: float) -> void:
		var parent := skeleton.get_bone_parent(bone)
		var above := HandPoseModifier.global_pose(skeleton, parent)
		var pose := above * skeleton.get_bone_pose(bone)
		var turned := Transform3D(Basis(Vector3.UP, angle) * pose.basis, pose.origin)
		skeleton.set_bone_pose(bone, above.affine_inverse() * turned)
