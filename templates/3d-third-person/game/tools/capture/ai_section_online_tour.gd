## The AI section's population online, for a clip of a client's screen (gdstudio #1234): Ada joins a
## game server and walks into the AI section; the server's spawners wake for her body there and
## spawn the population (3 grunts, 2 shooters, 2 allies, 3 civilians), and her screen draws every
## one as a puppet (enemies in the male mannequin, friendlies in the female) while they fight her,
## each other and flee; from 5 s she shoots the nearest grunt. The server and the client run in this
## process over a real socket (`tests/fixtures/online_rig.gd`), each with a map of its own; Ada's
## client runs no AI.
##
## `gds capture frames --project game --scene res://tools/capture/ai_section_online_tour.tscn
## --seconds 14 --fps 10`. It lives in tools/, which the export leaves out.
extends Node

const VIEW := Vector2i(1280, 720)
const FONT_SIZE := 28
## The section's origin in the world (`world.tscn`), and Ada's spot in it: 12 m east of the
## spawners, in the open, looking west at the guard lane.
const SECTION := Vector3(-25.0, 0.0, -9.0)
const ADA_AT := Vector3(-5.0, 0.3, -1.0)
const FACING_WEST := -PI / 2.0
const CAMERA_YAW := 90.0
const CAMERA_PITCH := 8.0
const CHEST := 1.15
## Seconds before Ada shoots the nearest grunt, and her shots' spacing.
const SHOOT_AFTER := 5.0
const SHOT_TICKS := 12
const SHOTS := 12

var _rig: OnlineRig
var _ada: NetClient
var _grunts: AiSpawner
var _aim := Callable()
var _presses: Array[int] = []
var _label: Label


func _ready() -> void:
	_rig = OnlineRig.new(false)
	_rig.view_size = VIEW
	add_child(_rig)
	_rig.start()
	_grunts = _rig.server.get_node("World/AISection/Population/Grunts") as AiSpawner
	_ada = await _rig.join("Ada", 600)
	# A clip of the section's fight, not of how long she lasts in it.
	Health.of(_rig.server_body(_ada)).invulnerable = true
	var spot := SECTION + ADA_AT
	_rig.server_body(_ada).teleport(spot, FACING_WEST)
	_ada.player.teleport(spot, FACING_WEST)
	var camera_rig := (_ada.player.get_parent() as PlayerRig).camera_rig
	camera_rig.yaw = CAMERA_YAW
	camera_rig.pitch = CAMERA_PITCH
	_rig.controllers[0].plan = _plan
	# Her screen fills the window.
	var picture := TextureRect.new()
	picture.texture = _rig.views[0].get_texture()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(picture)
	var window := get_viewport().get_visible_rect().size
	_add_label("Ada's screen, online: the AI section runs on the server", 12)
	_label = _add_label("", window.y - FONT_SIZE - 24)
	await _rig.wait(roundi(SHOOT_AFTER * NetLimits.TICK_RATE))
	var now: int = _rig.controllers[0].ticks
	for shot in SHOTS:
		_presses.append(now + 10 + shot * SHOT_TICKS)
	_aim = _nearest_grunt_chest


func _process(_delta: float) -> void:
	if _ada == null or not _ada.is_seated() or _label == null:
		return
	var dead := 0
	for character: AiCharacter in _rig.server.ai.characters().values():
		var lying := is_instance_valid(character) and character.is_inside_tree()
		dead += 1 if lying and character.is_dead() else 0
	var drawn_dead := 0
	for id in _ada.ai_replica.ids():
		drawn_dead += 1 if _ada.ai_replica.puppet_of(id).is_dead() else 0
	_label.text = (
		"AI on the server: %d (%d down)   puppets on this screen: %d (%d down)   AI here: 0"
		% [_rig.server.ai.rows().size(), dead, _ada.ai_replica.count(), drawn_dead]
	)


# Where Ada's screen draws the nearest living grunt's chest, or a point ahead with none.
func _nearest_grunt_chest() -> Vector3:
	var body := _ada.player
	var best: Character = null
	for grunt in _grunts.alive:
		var puppet := _ada.ai_replica.puppet_of(int(grunt.get_meta(NetHits.AI_META, -1)))
		if puppet == null or puppet.is_dead() or not puppet.visible:
			continue
		var distance := puppet.global_position.distance_to(body.global_position)
		if best == null or distance < best.global_position.distance_to(body.global_position):
			best = puppet
	if best == null:
		return body.global_position + Vector3(-10.0, CHEST, 0.0)
	return best.global_position + Vector3.UP * CHEST


# Ada's command: she stands; once she shoots, she aims at the grunt from her eye and presses on
# the planned ticks.
func _plan(tick: int) -> PlayerCommand:
	var command := PlayerCommand.new()
	var body := _ada.player
	command.yaw = body.view_yaw
	if not _aim.is_valid():
		return command
	var eye := body.global_position + Vector3.UP * body.tuning.camera_height
	var angles := CommandCodec.direction_angles((_aim.call() as Vector3) - eye)
	command.yaw = angles.x
	command.pitch = angles.y
	command.aim = true
	command.has_shot = true
	command.origin = eye
	command.shot_yaw = angles.x
	command.shot_pitch = angles.y
	command.fire_pressed = _presses.has(tick)
	return command


func _add_label(text: String, top: float) -> Label:
	var label := Label.new()
	label.text = text
	label.position = Vector2(16, top)
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 6)
	add_child(label)
	return label
