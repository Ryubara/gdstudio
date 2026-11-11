## A ragdoll pushed along by the map's moving block, seen from the side, for a clip at a high frame
## rate (gdstudio #1126): the player stands in the block's path just ahead of it as it sets off
## along its travel, goes limp, and the block shoves the body along. The camera looks down across
## the push, so a body drawn at the last tick shows as a step every two or three frames while the
## block glides.
##
## Record it at a frame rate over the 60 ticks and slow the clip down to see the steps:
## `gds capture frames --project game --scene res://tools/capture/ragdoll_push.tscn --fps 144
## --seconds 4`, then encode the frames at 24 a second (ffmpeg `-framerate 24`): six times slower.
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## Ticks the body stands in the block's path before it goes limp.
const STAND_TICKS := 5

var _stood := -1

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera
@onready var _mover: MovingPlatform = $Main/World/PathingSection/Obstacles/MoverA


func _physics_process(_delta: float) -> void:
	if _stood < 0:
		# Moving, with most of its travel ahead: stand just ahead of it, facing across its way.
		var ride := _mover.ride_at(_mover.placed_tick)
		var ahead := _mover.travel.normalized() * ride.direction
		var left := (
			ride.distance if ride.direction < 0.0 else _mover.travel.length() - ride.distance
		)
		if ride.running and ride.wait <= 0.0 and left > 6.0:
			_player.teleport(
				_mover.global_position + Vector3(0.0, -1.0, 0.0) + ahead * 1.3, PI / 2.0
			)
			_rig.yaw = -90.0
			_rig.pitch = 35.0
			_stood = 0
		return
	_stood += 1
	if _stood == STAND_TICKS:
		_player.die()
