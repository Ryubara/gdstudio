## Films gdstudio #1339 from the game's own camera, driven by the actions a player presses: four
## dead grunts lie in a row across the open floor, the player sprints through them, turns, runs
## back into them and stops among them. The capsule never meets a ragdoll bone, so the body keeps
## its speed and stance; the legs push the limbs aside (`CorpseNudge`). `NUDGE_OFF=1` films it
## with the nudge off (the template before #1339), for a before and after. Every physics frame it
## prints the part, the ground speed, the body state and the bones inside the capsule on a line
## starting `CORPSETOUR`.
##
## `gds capture frames --project game --scene res://tools/capture/corpse_tour.tscn --seconds 9
## --fps 30 --name corpses`. It lives in tools/, which the export leaves out.
extends Node

const CHARACTER := "res://gameplay/ai/ai_character.tscn"
## An open spot of the sample map, looking north (-Z) with room ahead.
const SPOT := Vector3(4.0, 0.0, 18.0)
## Where the dead lie: a row along the way the player runs.
const DEAD: Array[Vector3] = [
	Vector3(4.0, 0.0, 14.0),
	Vector3(4.2, 0.0, 13.1),
	Vector3(3.9, 0.0, 12.2),
	Vector3(4.1, 0.0, 11.3),
]
## The parts: a title, seconds, the actions held through it and the camera's yaw.
const PARTS: Array[Array] = [
	["The dead settle", 2.0, [], 0.0],
	["Sprint through the dead", 1.2, [&"move_forward", &"sprint"], 0.0],
	["Turn round", 0.6, [], 180.0],
	["Run back into them", 0.5, [&"move_forward"], 180.0],
	["Stand among them", 2.5, [], 180.0],
]

var _part := -1
var _clock := 0.0
var _label: Label
var _dead: Array[AiCharacter] = []

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera
@onready var _animation: CharacterAnimation = $Main/PlayerRig/Player/Animation


func _ready() -> void:
	for spawner in get_tree().get_nodes_in_group(&"ai_spawner"):
		spawner.set(&"enabled", false)
	var population := get_node_or_null(^"Main/World/AISection/Population")
	if population != null:
		for spawner in population.get_children():
			spawner.set(&"enabled", false)
	var nudge := _player.get_node(^"CorpseNudge") as CorpseNudge
	nudge.enabled = OS.get_environment("NUDGE_OFF") != "1"
	_player.teleport(SPOT, 0.0)
	_rig.yaw = 0.0
	_rig.pitch = 18.0
	for spot in DEAD:
		var grunt := (load(CHARACTER) as PackedScene).instantiate() as AiCharacter
		grunt.position = spot
		$Main.add_child(grunt)
		_dead.append(grunt)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for grunt in _dead:
		grunt.die()
	_build_label()
	_next()


func _physics_process(delta: float) -> void:
	if _part < 0 or _part >= PARTS.size():
		return
	_clock += delta
	var part: Array = PARTS[_part]
	var inside := _inside()
	_label.text = (
		"%s%s\nspeed %.2f m/s   %s   bones in the capsule %d"
		% [
			part[0],
			"  (nudge off)" if OS.get_environment("NUDGE_OFF") == "1" else "",
			_player.ground_speed(),
			_animation.body_state(),
			inside,
		]
	)
	print(
		"CORPSETOUR ",
		_part,
		" ",
		snappedf(_clock, 0.01),
		" ",
		snappedf(_player.ground_speed(), 0.01),
		" ",
		_animation.body_state(),
		" ",
		inside
	)
	if _clock >= part[1]:
		_next()


# The dead's bone centres inside the player's capsule now.
func _inside() -> int:
	var capsule := (_player.get_node(^"%Body") as CollisionShape3D).shape as CapsuleShape3D
	var low := _player.global_position + Vector3.UP * capsule.radius
	var high := _player.global_position + Vector3.UP * (capsule.height - capsule.radius)
	var count := 0
	for grunt in _dead:
		for entry: Dictionary in CharacterRagdoll.BODIES:
			var bone := grunt.ragdoll_body.body(entry.bone)
			if bone == null:
				continue
			var at := bone.global_position
			if (
				at.distance_to(Geometry3D.get_closest_point_to_segment(at, low, high))
				< capsule.radius
			):
				count += 1
	return count


func _next() -> void:
	if _part >= 0:
		for action: StringName in PARTS[_part][2]:
			Input.action_release(action)
	_part += 1
	_clock = 0.0
	if _part >= PARTS.size():
		_finish()
		return
	_rig.yaw = PARTS[_part][3]
	for action: StringName in PARTS[_part][2]:
		Input.action_press(action)


func _build_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	_label = Label.new()
	_label.position = Vector2(24.0, 24.0)
	_label.add_theme_font_size_override(&"font_size", 24)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 6)
	layer.add_child(_label)
	add_child(layer)


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits.
func _finish() -> void:
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _frame_count in 8:
		await get_tree().process_frame
	get_tree().quit()
