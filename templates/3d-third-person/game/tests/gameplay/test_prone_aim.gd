# Aiming while lying down (kit #1111), in the template's main scene through simulated input: the
# lying body aims with the prone aim clips and no standing weapon layer, the pose follows the look
# to the prone limits, a shot kicks it, both hands are on the pistol, a weapon with no prone aim
# keeps the standing layer; and the camera's prone aim view keeps the shoulders, the hands and
# the pistol in the picture above the HUD's bottom row, the pistol beside the head, with the lens
# over the floor.
extends GdUnitTestSuite

const PRONE_AIM := "parameters/Locomotion/prone/Aim/blend_amount"
const PRONE_LOOK := "parameters/Locomotion/prone/AimPose/blend_position"
const STANDING_AIM := "parameters/Aim/blend_amount"
const STANDING_GRIP := "parameters/Armed/blend_amount"
const SHOOT := "parameters/Shoot/active"
## What must be in the picture while aiming lying down: the shoulders, the hands and the head.
const IN_VIEW: Array[StringName] = [&"upperarm_l", &"upperarm_r", &"hand_l", &"hand_r", &"Head"]
## The picture the view is checked in: the template's own, 1920 by 1080.
const ASPECT := 16.0 / 9.0
## How near the picture's edge a point may be, as a share of the picture's size.
const EDGE := 0.01
## Where the HUD's bottom row (health, ammo) starts, as a share of the picture's height: the
## shoulders, the hands, the head and the muzzle stay above it.
const HUD_ROW := 0.84
## How far the line from the lens to the pistol's muzzle passes from the middle of the head, in
## metres: more than the head's half width, so the pistol shows beside it.
const BESIDE_HEAD := 0.11
## The lowest the lens may be over the floor, in metres (the near plane is 5 cm).
const LENS_FLOOR := 0.2

## Open ground on the east side of the map, where the prone aim tour lies down too.
const OPEN_GROUND := Vector3(5.5, 0.0, 8.0)

var _runner: GdUnitSceneRunner
var _scene: Node
var _player: Player
var _rig: PlayerCamera
var _camera: Camera3D
var _animation: CharacterAnimation
var _skeleton: Skeleton3D


func before_test() -> void:
	InputSim.release_all()
	_runner = scene_runner("res://main.tscn")
	_scene = _runner.scene()
	_player = _scene.get_node("PlayerRig/Player")
	_rig = _scene.get_node("PlayerRig/PlayerCamera")
	_camera = _scene.get_node("PlayerRig/Camera")
	_animation = _player.get_node("Animation")
	_skeleton = (_player.get_node("Model") as CharacterModel).skeleton()
	await InputSim.ticks(get_tree(), 12)
	# Open ground, so no wall draws the camera in.
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


func _aim(ticks := 50) -> void:
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, true)
	await InputSim.ticks(get_tree(), ticks)


func _look(pitch: float) -> void:
	_rig.orbit(Vector2(0.0, pitch - _rig.pitch))
	await InputSim.ticks(get_tree(), 40)


func _bone(bone: StringName) -> Vector3:
	return (
		_skeleton.global_transform
		* _skeleton.get_bone_global_pose(_skeleton.find_bone(bone)).origin
	)


# Where a point of the world is in a 16:9 picture of the game's camera (0 to 1 across and down;
# a headless run's own picture is square), or far outside it when the point is behind the lens.
func _on_picture(at: Vector3) -> Vector2:
	var seen := _camera.get_camera_transform().affine_inverse() * at
	if seen.z >= 0.0:
		return Vector2(-9.0, -9.0)
	var half := -seen.z * tan(deg_to_rad(_camera.fov) / 2.0)
	return Vector2(0.5 + 0.5 * seen.x / (half * ASPECT), 0.5 - 0.5 * seen.y / half)


func _muzzle() -> Node3D:
	return _player.get_node("Model/PistolHeld").find_child("Muzzle", true, false) as Node3D


func test_a_lying_body_aims_with_the_prone_clips_and_no_standing_layer() -> void:
	var tree := _animation.tree
	await _lie_down()
	assert_float(tree.get(PRONE_AIM)).is_equal(0.0)
	await _aim()
	assert_float(tree.get(PRONE_AIM)).is_equal_approx(1.0, 0.001)
	assert_float(tree.get(STANDING_AIM)).is_equal(0.0)
	assert_float(tree.get(STANDING_GRIP)).is_equal(0.0)
	# The hold still knows the weapon is in the hand and aimed.
	assert_vector(_animation.pistol_weights()).is_equal_approx(Vector2.ONE, Vector2(0.001, 0.001))
	assert_float(_animation.prone_hold_share()).is_equal_approx(1.0, 0.001)
	assert_bool((_player.get_node("Model/PistolHeld") as Node3D).visible).is_true()
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, false)
	await InputSim.ticks(get_tree(), 40)
	assert_float(tree.get(PRONE_AIM)).is_equal(0.0)
	assert_bool((_player.get_node("Model/PistolHeld") as Node3D).visible).is_false()


func test_a_standing_body_aims_with_the_standing_layer() -> void:
	var tree := _animation.tree
	await _aim()
	assert_float(tree.get(STANDING_AIM)).is_equal_approx(1.0, 0.001)
	assert_float(tree.get(STANDING_GRIP)).is_equal_approx(1.0, 0.001)
	assert_float(tree.get(PRONE_AIM)).is_equal(0.0)
	assert_float(_animation.prone_hold_share()).is_equal(0.0)


func test_the_prone_aim_follows_the_look_and_the_barrel_with_it() -> void:
	var prone := _player.prone_tuning
	var angles := _player.weapon.definition.prone_aim_angles
	await _lie_down()
	await _aim()
	for look: float in [0.0, prone.look_up_limit, -angles.x, -prone.look_down_limit]:
		await _look(-look)
		var posed: float = _animation.tree.get(PRONE_LOOK)
		# Past the look the down clip is made for, the pose stays on that clip.
		var wanted := clampf(look, -angles.x, angles.y)
		assert_float(posed).is_equal_approx(wanted, 0.5)
		# The aim layer turns the spine for the rest, within the prone `aim_limits` (kit #1253).
		var aimed := rad_to_deg(_player.prone_tuning.aim_limits.clamp_pitch(deg_to_rad(look)))
		var barrel := -_muzzle().global_basis.z.normalized()
		var up := rad_to_deg(asin(barrel.y))
		(
			assert_float(up)
			. override_failure_message("looking %.0f: the barrel points %.1f up" % [look, up])
			. is_equal_approx(aimed, 2.5)
		)
		# Along the way the body faces.
		var ahead := Vector3(sin(_player.facing), 0.0, cos(_player.facing))
		var flat := Vector3(barrel.x, 0.0, barrel.z).normalized()
		var out := rad_to_deg(flat.angle_to(ahead))
		(
			assert_float(out)
			. override_failure_message(
				"looking %.0f: the barrel points %.1f to the side" % [look, out]
			)
			. is_less(2.5)
		)


func test_a_shot_lying_down_kicks_the_prone_aim_and_plays_no_standing_shot() -> void:
	await _lie_down()
	await _aim()
	await _look(0.0)
	var shots := [0]
	_player.weapon.fired.connect(func(_projectile: Projectile) -> void: shots[0] += 1)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	var highest := 0.0
	for _tick in 8:
		await InputSim.ticks(get_tree(), 1)
		highest = maxf(highest, _animation.tree.get(PRONE_LOOK))
		assert_bool(_animation.tree.get(SHOOT)).is_false()
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
	assert_int(shots[0]).is_greater(0)
	assert_float(highest).is_greater(_animation.prone_shot_kick * 0.5)
	await InputSim.ticks(get_tree(), 40)
	assert_float(_animation.tree.get(PRONE_LOOK)).is_equal_approx(0.0, 0.5)
	# Standing, the shot clip plays as before.
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, false)
	InputSim.key(KEY_Z, true)
	await InputSim.ticks(get_tree(), 2)
	InputSim.key(KEY_Z, false)
	await InputSim.ticks(get_tree(), 90)
	assert_bool(_player.prone).is_false()
	await _aim(30)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	var played := false
	for _tick in 8:
		await InputSim.ticks(get_tree(), 1)
		played = played or _animation.tree.get(SHOOT)
	assert_bool(played).is_true()


func test_a_reload_lying_down_never_plays_the_standing_clip() -> void:
	await _lie_down()
	await _aim()
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await InputSim.ticks(get_tree(), 6)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
	await InputSim.ticks(get_tree(), 20)
	InputSim.key(KEY_R, true)
	await InputSim.ticks(get_tree(), 3)
	InputSim.key(KEY_R, false)
	assert_bool(_player.weapon.is_reloading()).is_true()
	# The standing reload clip does not play over the lying body: the reload layer holds the
	# weapon's prone reload (kit #1185, `test_prone_reload.gd`), and the prone aim stays under it.
	var root := _animation.tree.tree_root as AnimationNodeBlendTree
	var layer := root.get_node(&"ReloadClip") as AnimationNodeAnimation
	for _tick in 30:
		await InputSim.ticks(get_tree(), 1)
		if _animation.is_reloading():
			assert_str(String(layer.animation)).is_not_equal(
				String(_player.weapon.definition.reload_clip)
			)
		assert_float(_animation.tree.get(PRONE_AIM)).is_equal_approx(1.0, 0.001)


func test_both_hands_are_on_the_pistol_in_the_running_game() -> void:
	var hold := _player.get_node("WeaponHold") as WeaponHold
	var marker := _player.get_node("Model/PistolHeld/Pistol/SupportHand") as Node3D
	await _lie_down()
	await _aim(70)
	# Level, the look-up limit, the down clip's look and the look-down limit, where the pose stays
	# on the down clip (a spine turned on to 40 degrees put the muzzle 20 cm under the floor).
	for look: float in [0.0, 12.0, -25.0, -40.0]:
		await _look(-look)
		assert_float(hold.support_shortfall()).is_less(0.005)
		var gap := [1.0]
		var read := func() -> void: gap[0] = _bone(&"hand_l").distance_to(marker.global_position)
		_skeleton.skeleton_updated.connect(read, CONNECT_ONE_SHOT)
		await InputSim.ticks(get_tree(), 3)
		(
			assert_float(gap[0])
			. override_failure_message(
				"looking %.0f: the left hand is %.1f mm off" % [look, gap[0] * 1e3]
			)
			. is_less(0.01)
		)
		# The hands and the pistol stay over the floor.
		var floor_y := _player.global_position.y
		assert_float(_bone(&"hand_l").y).is_greater(floor_y + 0.02)
		assert_float(_muzzle().global_position.y).is_greater(floor_y)


func test_each_body_plays_the_prone_aim_solved_on_it() -> void:
	var player: AnimationPlayer = _player.get_node("AnimationPlayer")
	var model := _player.get_node("Model") as CharacterModel
	var library := CharacterClips.LIBRARY_PRONE_AIM
	# The scene's own library is the default body's; the other body has its own file.
	assert_str(model.rig().scene_file_path).is_equal(CharacterBodies.FEMALE)
	var shared := player.get_animation_library(library)
	assert_str(shared.resource_path).ends_with("prone_aim.glb")
	var male := _animation.prone_aim_libraries[CharacterBodies.MALE]
	assert_str(male.resource_path).ends_with("prone_aim_male.glb")
	model.variant = load(CharacterBodies.MALE)
	await InputSim.ticks(get_tree(), 4)
	assert_str(model.rig().scene_file_path).is_equal(CharacterBodies.MALE)
	assert_object(player.get_animation_library(library)).is_same(male)
	assert_bool(player.has_animation(CharacterClips.PRONE_AIM_UP)).is_true()
	model.variant = load(CharacterBodies.FEMALE)
	await InputSim.ticks(get_tree(), 4)
	assert_object(player.get_animation_library(library)).is_same(shared)


func test_a_weapon_with_no_prone_aim_keeps_the_standing_layer() -> void:
	var own := _player.weapon.definition.duplicate() as WeaponDef
	own.prone_aim_clip = &""
	_player.weapon.definition = own
	await InputSim.ticks(get_tree(), 4)
	await _lie_down()
	await _aim()
	assert_float(_animation.tree.get(PRONE_AIM)).is_equal(0.0)
	assert_float(_animation.tree.get(STANDING_AIM)).is_equal_approx(1.0, 0.001)
	assert_float(_animation.prone_hold_share()).is_equal(0.0)


func test_the_camera_takes_the_prone_aim_view_and_gives_it_back() -> void:
	await _aim()
	assert_float(_rig.prone_aim_blend()).is_equal(0.0)
	assert_float(_rig.current_distance()).is_equal_approx(_rig.aim_distance, 0.001)
	assert_vector(_rig.current_offset()).is_equal(_rig.offset)
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, false)
	await _lie_down()
	assert_float(_rig.prone_aim_blend()).is_equal(0.0)
	await _aim()
	assert_float(_rig.prone_aim_blend()).is_equal_approx(1.0, 0.001)
	assert_float(_rig.current_distance()).is_equal_approx(_rig.prone_aim_distance, 0.001)
	assert_float(_rig.current_fov()).is_equal_approx(_rig.prone_aim_fov, 0.001)
	assert_float(_rig.current_view_offset().x).is_equal_approx(_rig.prone_aim_shoulder, 0.001)
	# The point the view turns about is ahead of the body's middle, the way the camera looks.
	var heading := -_camera.global_basis.z
	heading = Vector3(heading.x, 0.0, heading.z).normalized()
	var moved := _rig.current_offset() - _rig.offset
	assert_float(moved.dot(heading)).is_equal_approx(_rig.prone_aim_ahead, 0.001)
	assert_float(moved.y).is_equal_approx(_rig.prone_aim_rise, 0.001)
	# Firing without the aim button lying down takes the same view.
	InputSim.mouse_button(MOUSE_BUTTON_RIGHT, false)
	await InputSim.ticks(get_tree(), 40)
	assert_float(_rig.prone_aim_blend()).is_equal(0.0)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, true)
	await InputSim.ticks(get_tree(), 40)
	assert_float(_rig.prone_aim_blend()).is_equal_approx(1.0, 0.001)
	InputSim.mouse_button(MOUSE_BUTTON_LEFT, false)
	# Off: the lying body aims with the standing aim view.
	_rig.prone_aim_view = false
	await _aim()
	assert_float(_rig.current_distance()).is_equal_approx(_rig.aim_distance, 0.001)
	assert_vector(_rig.current_offset()).is_equal(_rig.offset)


func test_the_prone_aim_view_shows_the_shoulders_the_hands_and_the_pistol() -> void:
	var prone := _player.prone_tuning
	await _lie_down()
	await _aim(70)
	for look: float in [0.0, prone.look_up_limit, -25.0]:
		await _look(-look)
		var points := {"muzzle": _muzzle().global_position}
		for bone in IN_VIEW:
			points[String(bone)] = _bone(bone)
		for point: String in points:
			var at: Vector3 = points[point]
			var on_screen := _on_picture(at)
			var inside := (
				on_screen.x > EDGE
				and on_screen.x < 1.0 - EDGE
				and on_screen.y > EDGE
				and on_screen.y < HUD_ROW
			)
			(
				assert_bool(inside)
				. override_failure_message(
					"looking %.0f: %s is at %s of the picture" % [look, point, on_screen]
				)
				. is_true()
			)
		# The pistol shows beside the head, not behind it: the line from the lens to the muzzle
		# passes clear of the head's middle.
		var lens := _camera.get_camera_transform().origin
		var head := _bone(&"Head") + Vector3.UP * 0.08
		var line := (points["muzzle"] as Vector3) - lens
		var nearest := (
			lens + line * clampf((head - lens).dot(line) / line.length_squared(), 0.0, 1.0)
		)
		(
			assert_float(nearest.distance_to(head))
			. override_failure_message(
				(
					"looking %.0f: the muzzle is %.0f mm from the head's middle"
					% [look, nearest.distance_to(head) * 1e3]
				)
			)
			. is_greater(BESIDE_HEAD)
		)


func test_the_lens_stays_over_the_floor_at_the_prone_look_up_limit() -> void:
	await _lie_down()
	await _aim()
	# The stick held up as far as it goes.
	_rig.orbit(Vector2(0.0, -180.0))
	await InputSim.ticks(get_tree(), 40)
	assert_float(_rig.pitch).is_equal_approx(-_player.prone_tuning.look_up_limit, 0.01)
	var floor_y := _player.global_position.y
	assert_float(_camera.get_camera_transform().origin.y).is_greater(floor_y + LENS_FLOOR)
