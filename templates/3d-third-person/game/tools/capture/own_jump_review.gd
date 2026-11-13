## Films the jump with each variant of GDStudio's own jump clips (kit #1161), on the template's
## map, from the game's own camera and driven by the same input each time: the real player stands
## and jumps, jumps again seen from its side, then runs and jumps. A turn per variant (`A`, `B`,
## `C`: the take-off, the fall and the soft landing of that letter, read from the review files,
## which the game does not import), then one with the library's clips they replace.
##
## Record it with Movie Maker through the kit:
## `gds capture frames --project game --seconds 37 --fps 30
## --scene res://tools/capture/own_jump_review.tscn`
## `OWN_ONLY=<letter>` films that one variant, `OWN_ONLY=Shipped` the clips the game ships and
## `OWN_ONLY=Library` the library's: nine seconds each, short enough for a GIF.
## `OWN_AHEAD=<metres>` starts each turn that far ahead of the spawn point (default 6: the spawn
## pad ends 4.6 m ahead, and a body that runs off it falls).
## `OWN_BEFORE=<a folder on this machine>` reads an older build's review files from that folder
## (`jump_start.glb`, `jump_fall.glb`, `land_soft.glb`) for a turn named `Before`, which plays
## their A: `OWN_ONLY=Before` films it alone, to set beside `OWN_ONLY=A` (kit #1369's arms).
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

const REVIEW := "res://assets/animation/own/review/%s.glb"
## The exports of `CharacterAnimation` a turn sets, with the review file and the clip of each.
const SLOTS := {
	&"jump_clip": ["jump_start", "Jump_Start"],
	&"air_clip": ["jump_fall", "Jump_Fall"],
	&"land_clip": ["land_soft", "Land_Soft"],
}
## A turn, in seconds: its length, the presses of the jump button and how long each is held,
## the time the camera is at the player's side, and the time the player runs forward.
const TURN := 9.0
const JUMPS: Array[float] = [0.8, 2.6, 6.0]
const HELD := 0.35
const SIDE := Vector2(2.0, 4.3)
const RUN := Vector2(5.1, 6.9)

var _turns: Array[String] = ["A", "B", "C", "Library"]
var _shipped := {}
var _ahead := 6.0
var _way := Vector3.ZERO
var _start := Vector3.ZERO
var _label: Label
var _clock := 0.0
var _turn := -1

@onready var _rig: PlayerRig = $Main/PlayerRig


func _ready() -> void:
	var animation: CharacterAnimation = _rig.player.get_node("Animation")
	var clips: AnimationPlayer = _rig.player.get_node("AnimationPlayer")
	var before := OS.get_environment("OWN_BEFORE")
	for slot: StringName in SLOTS:
		_shipped[slot] = animation.get(slot)
		var type: String = SLOTS[slot][0]
		clips.add_animation_library(StringName("review_" + type), _read(REVIEW % type))
		if before != "":
			clips.add_animation_library(
				StringName("before_" + type), _read(before.path_join(type + ".glb"))
			)
	var only := OS.get_environment("OWN_ONLY")
	if only != "":
		_turns = [only]
	var ahead := OS.get_environment("OWN_AHEAD")
	_ahead = ahead.to_float() if ahead != "" else _ahead
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(40, 30)
	_label.add_theme_font_size_override(&"font_size", 34)
	layer.add_child(_label)


func _physics_process(delta: float) -> void:
	_clock += delta
	var turn := int(_clock / TURN)
	if turn >= _turns.size():
		_finish()
		return
	if turn != _turn:
		_turn = turn
		_begin(_turns[turn])
	var at := fmod(_clock, TURN)
	var jumping := false
	for press in JUMPS:
		jumping = jumping or (at >= press and at < press + HELD)
	_hold(&"jump", jumping)
	_hold(&"move_forward", at >= RUN.x and at < RUN.y)
	_face(90.0 if at >= SIDE.x and at < SIDE.y else 0.0)


# A turn starts on one place, facing one way, with one variant's clips in the three exports.
func _begin(letter: String) -> void:
	if _way == Vector3.ZERO:
		var way := -_rig.camera_rig.camera.global_basis.z
		_way = Vector3(way.x, 0.0, way.z).normalized()
		_start = _rig.player.global_position + _way * _ahead
	_rig.player.teleport(_start, atan2(_way.x, _way.z))
	var animation: CharacterAnimation = _rig.player.get_node("Animation")
	var named: PackedStringArray = []
	for slot: StringName in SLOTS:
		var clip: StringName = _shipped[slot]
		if letter == "Library":
			clip = CharacterClips.stand_in(clip)
		elif letter == "Before":
			clip = StringName("before_%s/%s_A" % [SLOTS[slot][0], SLOTS[slot][1]])
		elif letter != "Shipped":
			clip = StringName("review_%s/%s_%s" % [SLOTS[slot][0], SLOTS[slot][1], letter])
		animation.set(slot, clip)
		named.append(String(clip).get_slice("/", 1))
	var what := "the library's" if letter == "Library" else "ours"
	what = "before (kit #1369)" if letter == "Before" else what
	_label.text = "%s: %s" % [what, ", ".join(named)]


func _hold(action: StringName, down: bool) -> void:
	if down and not Input.is_action_pressed(action):
		Input.action_press(action)
	elif not down and Input.is_action_pressed(action):
		Input.action_release(action)


# Reads a review file, which the game does not import: its clips as a library, a `_Loop` clip
# looping under its name without the suffix, as the importer makes them.
func _read(path: String) -> AnimationLibrary:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(ProjectSettings.globalize_path(path), state)
	assert(error == OK, "cannot read the review file %s" % path)
	var scene := document.generate_scene(state, 30.0)
	var source: AnimationPlayer = scene.find_children("*", "AnimationPlayer", true, false)[0]
	var library := AnimationLibrary.new()
	for clip in source.get_animation_list():
		var animation: Animation = source.get_animation(clip).duplicate()
		var short := String(clip).trim_suffix("_Loop")
		if short != String(clip):
			animation.loop_mode = Animation.LOOP_LINEAR
		library.add_animation(StringName(short), animation)
	scene.free()
	return library


# Turns the camera to a heading (degrees, 0 looks along the way the player faces at the start).
func _face(yaw: float) -> void:
	var camera := _rig.camera_rig
	var by_yaw := clampf(wrapf(yaw - camera.yaw, -180.0, 180.0), -6.0, 6.0)
	camera.orbit(Vector2(-by_yaw, clampf(8.0 - camera.pitch, -2.0, 2.0)))


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits
# (a voice still playing at exit is reported as a leak).
func _finish() -> void:
	set_physics_process(false)
	Input.action_release(&"move_forward")
	Input.action_release(&"jump")
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()
