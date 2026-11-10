## Close-ups of the hands on the pistol through the reload and the other pistol clips, from the
## side, from above and from behind the shoulder (the player's camera), two frames a pose and view
## (Movie Maker writes a frame before the pose of its `_process` shows, so take the second):
## the character is the game's `player.tscn`, its tree off and the clip seeked on its
## `AnimationPlayer`, so each frame is exactly the clip at that time. For the weapons page's hand
## rules (`docs/tools/blender/weapons.md#hands-on-the-weapon`): look at every frame full size.
##
## `gds capture frames --project game --scene res://tools/capture/reload_closeups.tscn
## --seconds 3 --fps 10` (`CLOSEUP_MODEL=male` for the male mannequin). It prints a `POSE` line a
## frame (the clip, its time and the view). It lives in tools/, which the export leaves out.
extends Node3D

## Each pose: the clip and the share of its length.
const POSES: Array = [
	[CharacterClips.PISTOL_IDLE, 0.0],
	[CharacterClips.PISTOL_AIM, 0.0],
	[CharacterClips.PISTOL_RELOAD, 0.1],
	[CharacterClips.PISTOL_RELOAD, 0.3],
	[CharacterClips.PISTOL_RELOAD, 0.5],
	[CharacterClips.PISTOL_RELOAD, 0.7],
	[CharacterClips.PISTOL_RELOAD, 0.9],
]
## The views: where the camera is from the right hand, in the character's space (+Z its front).
const VIEWS: Dictionary = {
	"side": Vector3(-0.45, 0.05, 0.05),
	"top": Vector3(0.0, 0.5, 0.05),
	"player": Vector3(-0.3, 0.25, -0.6),
}

var _frame := -1
var _player: Player
var _camera: Camera3D
var _hand := -1


func _ready() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.82, 0.86, 0.9)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	add_child(environment)
	_player = (load("res://gameplay/player/player.tscn") as PackedScene).instantiate() as Player
	_player.start_at_spawn = false
	add_child(_player)
	_player.set_physics_process(false)
	if OS.get_environment("CLOSEUP_MODEL") == "male":
		var slot := _player.model
		var old := slot.rig()
		slot.remove_child(old)
		old.free()
		var male := load("res://assets/characters/mannequin/mannequin_male.glb") as PackedScene
		slot.add_child(male.instantiate())
	_camera = Camera3D.new()
	_camera.fov = 35.0
	add_child(_camera)
	_camera.make_current()


func _process(_delta: float) -> void:
	_frame += 1
	var count := POSES.size() * VIEWS.size()
	if _frame >= count * 2:
		get_tree().quit()
		return
	var shot := _frame / 2
	var animation := _player.get_node("Animation") as CharacterAnimation
	animation.tree.active = false
	var pose: Array = POSES[shot / VIEWS.size()]
	var view: String = VIEWS.keys()[shot % VIEWS.size()]
	var player := animation.animation_player
	player.play(pose[0])
	player.seek(player.current_animation_length * float(pose[1]), true)
	player.pause()
	var skeleton := _player.model.skeleton()
	skeleton.force_update_all_bone_transforms()
	if _hand < 0:
		_hand = skeleton.find_bone(&"hand_r")
	var hand := skeleton.global_transform * skeleton.get_bone_global_pose(_hand)
	var model_basis := _player.model.global_basis
	_camera.global_position = hand.origin + model_basis * VIEWS[view]
	var up := Vector3.UP if view != "top" else model_basis.z
	_camera.look_at(hand.origin + model_basis * Vector3(0.0, 0.0, 0.08), up)
	print("POSE %d %s %.2f %s" % [_frame, pose[0], pose[1], view])
