## A crowd of AI arriving on a client at once, for a clip (gdstudio #1208): Bo stands where he
## spawned looking at 40 characters the server holds out of his interest; at one second the
## interest radius grows to the whole map, so one block brings all 40, as a join does. Bo's
## `AiReplica` makes and shows their puppets a few a frame, the nearest first; the label counts
## the puppets made and the most made and shown in one frame. The server and Bo run in this
## process over a real socket (`tests/fixtures/online_rig.gd`).
##
## `gds capture frames --project game --scene res://tools/capture/ai_join_tour.tscn --seconds 3
## --fps 60`, then `gds capture clip <folder> --gif --slow 2`. It lives in tools/, which the export
## leaves out.
extends Node

const CROWD := 40
const VIEW := Vector2i(1280, 720)
## The crowd's rows ahead of Bo where he spawns (north, -z, the way his camera looks at yaw 0):
## the nearest 4 m away.
const CROWD_NEAR := 4.0
const SPACING := 1.6
const COLUMNS := 8
## Physics steps before the crowd comes into Bo's interest.
const ARRIVE_AFTER := 60

var _rig: OnlineRig
var _bo: NetClient
var _label: Label
var _rates: AiTierRates
var _last_count := 0
var _most_made := 0
var _most_shown := 0
var _last_shown := 0


func _ready() -> void:
	_rig = OnlineRig.new(false)
	_rig.view_size = VIEW
	add_child(_rig)
	_rig.start()
	_rates = AiTierRates.new()
	_rates.interest_radius = 0.5
	_rig.server.ai.rates = _rates
	_bo = await _rig.join("Bo", 600)
	var at := _rig.server_body(_bo).global_position
	var map := AiNetStage.server_map(_rig.server)
	for index in CROWD:
		var spot := Vector3(
			at.x + (index % COLUMNS - (COLUMNS - 1) / 2.0) * SPACING,
			at.y,
			at.z - CROWD_NEAR - (index / COLUMNS) * SPACING
		)
		map.add_child(AiNetStage.walker(spot))
	var rig := _bo.player.get_parent() as PlayerRig
	# The camera's yaw turns its look from -z: 0 looks north, at the crowd.
	rig.camera_rig.yaw = 0.0
	rig.camera_rig.pitch = 12.0
	var picture := TextureRect.new()
	picture.texture = _rig.views[0].get_texture()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(picture)
	_label = Label.new()
	_label.position = Vector2(12, 8)
	_label.add_theme_font_size_override(&"font_size", 30)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 4)
	add_child(_label)
	await _rig.wait(ARRIVE_AFTER)
	_rates.interest_radius = 1000.0


func _physics_process(_delta: float) -> void:
	if _bo == null or _label == null:
		return
	var replica := _bo.ai_replica
	var made := replica.count() - _last_count
	_last_count = replica.count()
	_most_made = maxi(_most_made, made)
	var shown := 0
	for id in replica.ids():
		shown += 1 if replica.puppet_of(id).visible else 0
	_most_shown = maxi(_most_shown, shown - _last_shown)
	_last_shown = shown
	_label.text = (
		"Bo's screen: puppets made %d / %d, shown %d   most in one frame: made %d, shown %d"
		% [replica.count(), CROWD, shown, _most_made, _most_shown]
	)
