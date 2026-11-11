## Films the near-hit shake (gdstudio #1068) from the game camera: the character stands on the open
## ground, and rounds from an unseen shooter high up behind the camera land on the floor in front
## of it and beside it (3.6 to 4 m from the camera), then one lands 20 m away, past the preset's
## radius. The rounds are the template's own `Projectile`, so the level's `Impacts` plays each hit
## and the rig's `NearHitShake` shakes the view from it, as in play. A label shows the view's turn;
## a `SHAKE` line each physics frame prints the time and the turn in degrees (pitch, yaw, roll) and
## a `HIT` line each hit's distance from the camera, its point and the camera's.
##
## `gds capture frames --project game --scene res://tools/capture/near_hit_tour.tscn --seconds 6`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

const PROJECTILE := preload("res://gameplay/projectile/projectile.tscn")
## Where the character stands, facing south toward the ledge.
const STAND := Vector3(6.0, 0.0, 15.0)
## Where the unseen shooter fires from: high up behind the camera, off to the right.
const SHOOTER := Vector3(8.0, 7.0, 19.0)
## The rounds: when (seconds) and where each lands (and, for the far one, where it comes from).
const SHOTS: Array[Dictionary] = [
	{"at": 1.5, "lands": Vector3(7.3, 0.0, 13.6)},
	{"at": 2.3, "lands": Vector3(4.6, 0.0, 14.0)},
	{"at": 3.1, "lands": Vector3(6.6, 0.0, 13.2)},
	{"at": 4.2, "lands": Vector3(6.0, 0.0, -3.5), "from": Vector3(6.0, 5.0, -8.0)},
]
const SPEED := 90.0

var _clock := 0.0
var _next := 0
var _label: Label

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	_player.teleport(STAND, 0.0)
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(24.0, 24.0)
	_label.add_theme_font_size_override(&"font_size", 22)
	layer.add_child(_label)
	Impacts.find(_rig).impact_made.connect(_on_impact)


func _physics_process(delta: float) -> void:
	_clock += delta
	if _next < SHOTS.size() and _clock >= float(SHOTS[_next]["at"]):
		_fire(SHOTS[_next]["lands"], SHOTS[_next].get("from", SHOOTER))
		_next += 1
	var turn := _rig.current_shake()
	print("SHAKE %.2f %.3f %.3f %.3f" % [_clock, turn.x, turn.y, turn.z])
	_label.text = "near-hit shake %.3f deg" % turn.length()
	if _clock > 5.5:
		set_physics_process(false)
		_finish()


func _fire(lands: Vector3, from: Vector3) -> void:
	var round_node := PROJECTILE.instantiate() as Projectile
	$Main.add_child(round_node)
	round_node.launch(from, lands - from, SPEED)


func _on_impact(
	_surface: ImpactSurface, _collider: Object, point: Vector3, _normal: Vector3
) -> void:
	var camera := _rig.get_viewport().get_camera_3d()
	print(
		(
			"HIT %.2f %.2f m at %s from %s"
			% [_clock, camera.global_position.distance_to(point), point, camera.global_position]
		)
	)


func _finish() -> void:
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()
