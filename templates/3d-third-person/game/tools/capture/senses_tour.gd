## Films what an AI character perceives, from the player's own camera, with the senses' debug
## view on (the cone on the ground, the near and hearing rings, a line to each belief, the
## awareness bars above the head) and the overlay's situation: a grunt stands still while the
## player walks up to it three times, from the front (seen far off, Suspicious, then Alert), from
## the side (outside the cone: noticed only at arm's reach or by its steps) and from behind
## (heard, then felt at arm's reach). The noise board draws each footstep's ring.
##
## Record it with Movie Maker through the kit:
## `gds capture frames --project game --scene res://tools/capture/senses_tour.tscn --seconds 25`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

const CHARACTER := "res://gameplay/ai/ai_character.tscn"
## Where the grunt stands (the open east side of the map's AI section); it faces +Z.
const GRUNT_AT := Vector3(-29.0, 0.0, -11.0)
## Each pass: where the player starts, where it stops, and the second it starts.
const PASSES: Array[Array] = [
	[Vector3(-29.0, 0.0, 4.0), Vector3(-29.0, 0.0, -9.4), 0.0],
	[Vector3(-36.0, 0.0, -11.0), Vector3(-30.4, 0.0, -11.0), 8.0],
	[Vector3(-29.0, 0.0, -23.0), Vector3(-29.0, 0.0, -12.4), 16.0],
]
const END := 25.0
## The share of a run the player walks at.
const WALK := 0.5
## Camera pitch, in degrees, while filming.
const PITCH := 18.0

var _clock := 0.0
var _pass := -1
var _grunt: AiCharacter
var _walker := Walker.new()

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


## Walks its character to `goal` at `strength` of a run, then stands.
class Walker:
	extends CharacterController
	var goal := Vector3.ZERO
	var strength := 1.0

	func sample() -> PlayerCommand:
		var command := _command
		command.clear()
		var body := get_parent() as Node3D
		var way := goal - body.global_position
		way.y = 0.0
		if way.length() > 0.15:
			command.set_from_world(way.normalized(), way.normalized(), strength)
		return command


func _ready() -> void:
	_player.add_child(_walker)
	_player.controller = _walker
	_walker.strength = WALK
	var board := get_tree().get_first_node_in_group(AiNoise.GROUP) as AiNoise
	if board != null:
		board.show_noises = true


func _physics_process(delta: float) -> void:
	_clock += delta
	var next := _pass + 1
	if next < PASSES.size() and _clock >= PASSES[next][2]:
		_start_pass(next)
	_face()
	if _clock >= END:
		_finish()


func _start_pass(index: int) -> void:
	_pass = index
	if _grunt != null:
		_grunt.queue_free()
	_grunt = (load(CHARACTER) as PackedScene).instantiate() as AiCharacter
	_grunt.debug = true
	_player.get_parent().add_child(_grunt)
	_grunt.teleport(GRUNT_AT, 0.0)
	(_grunt.senses as AiSenses).show_view = true
	var from: Vector3 = PASSES[index][0]
	var to: Vector3 = PASSES[index][1]
	_player.teleport(from, atan2(to.x - from.x, to.z - from.z))
	_walker.goal = to


func _finish() -> void:
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()


# Holds the camera behind the player along its walk, a few degrees a frame.
func _face() -> void:
	if _pass < 0:
		return
	var from: Vector3 = PASSES[_pass][0]
	var to: Vector3 = PASSES[_pass][1]
	var way := to - from
	var wanted := rad_to_deg(atan2(-way.x, -way.z))
	var by_yaw := clampf(wrapf(wanted - _rig.yaw, -180.0, 180.0), -8.0, 8.0)
	var by_pitch := clampf(PITCH - _rig.pitch, -2.0, 2.0)
	_rig.orbit(Vector2(-by_yaw, by_pitch))
