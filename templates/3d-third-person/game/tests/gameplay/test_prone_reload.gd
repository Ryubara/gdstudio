# Reloading while lying down (kit #1185), in the template's main scene through simulated input:
# R plays the pistol's prone reload clip over the lying body (never the standing one), the left
# hand goes through the reload's phases and is on the pistol again at the end, the rounds are in,
# the hands and the pistol stay over the floor on every update, a reload with the pistol put away
# brings it out, a body that gets up stops the lying clip, a weapon with no prone reload shows no
# clip lying down, and a standing body still reloads with the standing clip.
extends GdUnitTestSuite

const PRONE_AIM := "parameters/Locomotion/prone/Aim/blend_amount"
const RELOAD_CLIP := &"ReloadClip"
## Open ground on the east side of the map, where the prone aim tour lies down too.
const OPEN_GROUND := Vector3(5.5, 0.0, 8.0)
## The lowest a hand's bone, the pistol's foot and its muzzle may be over the floor on any update
## of the live reload, in metres.
const HAND_FLOOR := 0.015
const PISTOL_FLOOR := 0.0
## How near its marker the left hand's bone is once the reload is over, in metres.
const BACK_ON := 0.01

var _runner: GdUnitSceneRunner
var _player: Player
var _animation: CharacterAnimation
var _skeleton: Skeleton3D
var _hold: WeaponHold
# What the live reload was on each update of the skeleton: the phases seen, and the lowest the
# left hand, the right hand, the pistol's foot and its muzzle got over the floor.
var _phases := {}
var _lowest := {}


func before_test() -> void:
	InputSim.release_all()
	_runner = scene_runner("res://main.tscn")
	var scene := _runner.scene()
	_player = scene.get_node("PlayerRig/Player")
	_animation = _player.get_node("Animation")
	_skeleton = (_player.get_node("Model") as CharacterModel).skeleton()
	_hold = _player.get_node("WeaponHold")
	_phases = {}
	_lowest = {}
	await InputSim.ticks(get_tree(), 12)
	_player.teleport(OPEN_GROUND, PI)
	await InputSim.ticks(get_tree(), 20)


func after_test() -> void:
	InputSim.release_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _lie_down() -> void:
	InputSim.key(KEY_Z, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_Z, false)
	await InputSim.ticks(get_tree(), 50)
	assert_bool(_player.prone).is_true()


# Aims and fires one round, so there is something to reload; the aim stays held.
func _aim_and_fire() -> void:
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	await InputSim.ticks(get_tree(), 50)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await InputSim.ticks(get_tree(), 6)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
	await InputSim.ticks(get_tree(), 20)
	assert_int(_player.weapon.ammo).is_less(_player.weapon.magazine_size)


func _press_reload() -> void:
	InputSim.key(KEY_R, true)
	await InputSim.ticks(get_tree(), 3)
	InputSim.key(KEY_R, false)
	assert_bool(_player.weapon.is_reloading()).is_true()


# The clip the reload layer holds now.
func _reload_clip() -> StringName:
	var root := _animation.tree.tree_root as AnimationNodeBlendTree
	return (root.get_node(RELOAD_CLIP) as AnimationNodeAnimation).animation


func _reload_ticks() -> int:
	return roundi(_player.weapon.definition.reload_time * 60.0)


func _bone(bone: StringName) -> Vector3:
	return (
		_skeleton.global_transform
		* _skeleton.get_bone_global_pose(_skeleton.find_bone(bone)).origin
	)


func _pistol_part(part: String) -> Node3D:
	return _player.get_node("Model/PistolHeld").find_child(part, true, false) as Node3D


# One update of the skeleton during the live reload.
func _read() -> void:
	if not _animation.is_reloading():
		return
	_phases[_hold.left_hand().phase] = true
	var floor_y := _player.global_position.y
	var heights := {
		"hand_l": _bone(&"hand_l").y,
		"hand_r": _bone(&"hand_r").y,
		"foot": _pistol_part("Magazine").global_position.y,
		"muzzle": _pistol_part("Muzzle").global_position.y,
	}
	for part: String in heights:
		_lowest[part] = minf(_lowest.get(part, 9.0), heights[part] - floor_y)


func test_a_reload_lying_down_plays_the_prone_reload() -> void:
	await _lie_down()
	await _aim_and_fire()
	var marker := _player.get_node("Model/PistolHeld/Pistol/SupportHand") as Node3D
	_skeleton.skeleton_updated.connect(_read)
	await _press_reload()
	var played := false
	for _tick in _reload_ticks() + 30:
		await InputSim.ticks(get_tree(), 1)
		if _animation.is_reloading():
			played = true
			# The standing clip never plays over the lying body.
			assert_str(String(_reload_clip())).is_equal(String(CharacterClips.PRONE_RELOAD))
	_skeleton.skeleton_updated.disconnect(_read)
	assert_bool(played).override_failure_message("no reload clip played").is_true()
	# The left hand went through the reload and the rounds are in.
	for phase: SupportHandPlan.Phase in [
		SupportHandPlan.Phase.LET_GO,
		SupportHandPlan.Phase.AWAY,
		SupportHandPlan.Phase.REACH,
		SupportHandPlan.Phase.INSERT,
		SupportHandPlan.Phase.SEATED,
		SupportHandPlan.Phase.RETURN,
	]:
		(
			assert_bool(_phases.has(phase))
			. override_failure_message("the left hand skipped phase %d" % phase)
			. is_true()
		)
	assert_int(_player.weapon.ammo).is_equal(_player.weapon.magazine_size)
	assert_bool(_animation.is_reloading()).is_false()
	# The hands and the pistol stayed over the floor on every update.
	for part: String in _lowest:
		var limit := HAND_FLOOR if part.begins_with("hand") else PISTOL_FLOOR
		(
			assert_float(_lowest[part])
			. override_failure_message(
				"%s got %.1f mm over the floor" % [part, _lowest[part] * 1e3]
			)
			. is_greater(limit)
		)
	# Back in the prone aim, both hands on the pistol.
	assert_float(_animation.tree.get(PRONE_AIM)).is_equal_approx(1.0, 0.001)
	var gap := [1.0]
	var read := func() -> void: gap[0] = _bone(&"hand_l").distance_to(marker.global_position)
	_skeleton.skeleton_updated.connect(read, CONNECT_ONE_SHOT)
	await InputSim.ticks(get_tree(), 3)
	(
		assert_float(gap[0])
		. override_failure_message("the left hand is %.1f mm off after the reload" % (gap[0] * 1e3))
		. is_less(BACK_ON)
	)


func test_a_reload_with_the_pistol_put_away_brings_it_out() -> void:
	await _lie_down()
	await _aim_and_fire()
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, false)
	await InputSim.ticks(get_tree(), 40)
	var view := _player.get_node("Model").get_node(_player.weapon.definition.view) as Node3D
	assert_bool(view.visible).override_failure_message("the pistol is not put away").is_false()
	await _press_reload()
	await InputSim.ticks(get_tree(), _reload_ticks() / 2)
	assert_bool(_animation.is_reloading()).is_true()
	assert_str(String(_reload_clip())).is_equal(String(CharacterClips.PRONE_RELOAD))
	assert_bool(view.visible).override_failure_message("the reload shows no pistol").is_true()
	await InputSim.ticks(get_tree(), _reload_ticks() / 2 + 40)
	assert_bool(view.visible).override_failure_message("the pistol stayed out").is_false()
	assert_int(_player.weapon.ammo).is_equal(_player.weapon.magazine_size)


func test_getting_up_stops_the_prone_reload() -> void:
	await _lie_down()
	await _aim_and_fire()
	await _press_reload()
	await InputSim.ticks(get_tree(), 10)
	assert_bool(_animation.is_reloading()).is_true()
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, false)
	InputSim.key(KEY_Z, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_Z, false)
	# Up before the reload's time is over: the lying clip is gone from the body that stands.
	await InputSim.ticks(get_tree(), 50)
	assert_bool(_player.prone).is_false()
	assert_bool(_animation.is_reloading()).is_false()


func test_a_weapon_with_no_prone_reload_shows_no_clip_lying_down() -> void:
	var own := _player.weapon.definition.duplicate() as WeaponDef
	own.prone_reload_clip = &""
	_player.weapon.definition = own
	await InputSim.ticks(get_tree(), 4)
	await _lie_down()
	await _aim_and_fire()
	await _press_reload()
	for _tick in 30:
		await InputSim.ticks(get_tree(), 1)
		assert_bool(_animation.is_reloading()).is_false()
		assert_float(_animation.tree.get(PRONE_AIM)).is_equal_approx(1.0, 0.001)


func test_a_standing_body_reloads_with_the_standing_clip() -> void:
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	await InputSim.ticks(get_tree(), 30)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await InputSim.ticks(get_tree(), 6)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
	await InputSim.ticks(get_tree(), 20)
	await _press_reload()
	await InputSim.ticks(get_tree(), 10)
	assert_bool(_animation.is_reloading()).is_true()
	assert_str(String(_reload_clip())).is_equal(String(_player.weapon.definition.reload_clip))


func test_each_body_plays_the_prone_reload_solved_on_it() -> void:
	var player: AnimationPlayer = _player.get_node("AnimationPlayer")
	var model := _player.get_node("Model") as CharacterModel
	var library := CharacterClips.LIBRARY_PRONE_RELOAD
	# The scene's own library is the default body's; the other body has its own file.
	assert_str(model.rig().scene_file_path).is_equal(CharacterBodies.FEMALE)
	var shared := player.get_animation_library(library)
	assert_str(shared.resource_path).ends_with("prone_reload.glb")
	var male := _animation.prone_reload_libraries[CharacterBodies.MALE]
	assert_str(male.resource_path).ends_with("prone_reload_male.glb")
	model.variant = load(CharacterBodies.MALE)
	await InputSim.ticks(get_tree(), 4)
	assert_str(model.rig().scene_file_path).is_equal(CharacterBodies.MALE)
	assert_object(player.get_animation_library(library)).is_same(male)
	assert_bool(player.has_animation(CharacterClips.PRONE_RELOAD)).is_true()
	model.variant = load(CharacterBodies.FEMALE)
	await InputSim.ticks(get_tree(), 4)
	assert_object(player.get_animation_library(library)).is_same(shared)
