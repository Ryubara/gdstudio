## Plays the variants of one of GDStudio's own clip types for review (kit #1154), on the template's
## map. The variants come from the review file (`assets/animation/own/review/<type>.glb`, which
## the game does not import: it is read here as a glTF file) and the last body plays the library
## clip the type replaces.
##
## Two parts:
## 1. **Side by side.** A body per variant in a row where the player spawns, each under its name,
##    from the game camera's side of them and its height, pulled back to hold them all: five
##    seconds seen from behind, as the player sees a character, then five from the front.
## 2. **In the game.** The real player with each variant in turn as its clip, from the game's own
##    camera, from the spawn point and driven by the same input each time: it stands, walks
##    forward, stops and stands, and the camera then comes round to its front.
##
## Record it with Movie Maker through the kit:
## `gds capture frames --project game --seconds 48 --fps 30
## --scene res://tools/capture/own_clips_review.tscn`
## `OWN_TYPE=<type>` picks the clip type (default `idle`) and `OWN_SLOT=<export>` the
## `CharacterAnimation` export the variants are played through (default `idle_clip`).
## `OWN_ONLY=<clip>` (`Idle_A`, or `Library`) films part 2 for that one clip and nothing else:
## nine seconds, short enough for a GIF. `OWN_ONLY=Shipped` films the clip the game ships in the
## slot (`gds/Crouch_Walk`), which is not always a variant's bytes: a clip that is carried like
## another is built on the variant picked for that one.
## `OWN_CROUCH=1` holds the crouch button through part 2, for the crouch clips (gdstudio #1160).
## `OWN_SLOT=none` is for a clip type the tree has no export for yet (the stance changes, until
## gdstudio #1158): only part 1 is filmed, with no library body, and a clip that plays once is
## played again every two seconds. `OWN_FROM=<clip>` (`gds/Idle`) holds each body on that clip's
## first pose between two plays, so a stance change is seen leaving the pose it joins.
## `OWN_PLAYER=<clip>` (`gds/Crouch_To_Stand`) films a shipped clip the tree does not play yet on
## the real player, from the game's own camera and nothing else: the tree is off, the body rests
## on `OWN_FROM`'s first pose, plays the clip and goes on into `OWN_INTO` (`gds/Idle`), every
## three seconds, five seconds from behind and five from the front.
## A gait is filmed moving (kit #1155): `OWN_HOLD=<action>` is held with `move_forward` (`walk`
## for the walk, `sprint` for the sprint, nothing for the jog) and `OWN_MOVE=<seconds>` is how
## long it moves for (default 1.5; the walk wants 4; a run reaches the far wall, so the jog
## takes 2.2 and the sprint 1.4 from 5 m ahead), so the loop is seen over the ground at the
## game's speed, with its start and its stop either side. `OWN_AHEAD=<metres>` starts each turn
## that far ahead of the spawn point: the spawn pad ends 4.6 m ahead, and a body that steps off
## it plays its fall, which is not the clip under review.
## `OWN_BODY=male` puts the enemies' body in the row of part 1 (default `female`, the player's:
## `CharacterBodies.BY_NAME`); part 2 is always the player.
## `OWN_BEFORE=<a review file's path on this machine>` adds an older build's variants to the row
## as `before/<clip>`, and `OWN_ROW=<clip>,<clip>` keeps only the named clips in the row, in that
## order (`before/Walk_B,Walk_B,Library`): a change to a clip beside what it was and the library's.
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

const REVIEW := "res://assets/animation/own/review/%s.glb"
## Metres between two bodies of the row, and where the row's camera stands from its middle (the
## bodies face +Z; the game's camera looks at a character from behind and above).
const SPACING := 1.1
const ROW_CAMERA := Vector3(0.5, 2.0, -4.4)
const ROW_SECONDS := 5.0
## Part 2, per variant: seconds standing, walking, standing again, and seen from the front.
const STAND := 3.0
const WALK := 1.5
const SETTLE := 2.0
const FRONT := 2.5
## `OWN_PLAYER`: seconds between two plays, and the rest on the pose the clip leaves.
const PLAYER_EVERY := 3.0
const PLAYER_REST := 0.8

var _clips: Array[StringName] = []
var _library: AnimationLibrary
var _slot := &"idle_clip"
var _hold := &""
var _move := WALK
var _ahead := 0.0
var _way := Vector3.ZERO
var _start := Vector3.ZERO
var _row: Node3D
var _row_camera: Camera3D
var _body := CharacterBodies.FEMALE
var _label: Label
var _clock := 0.0
var _part := 0
var _turn := -1
var _crouch := false
var _row_players: Array[AnimationPlayer] = []
var _from := &""
var _replayed := 0.0
var _shown := &""
var _into := &""

@onready var _rig: PlayerRig = $Main/PlayerRig


func _ready() -> void:
	var type := OS.get_environment("OWN_TYPE")
	var slot := OS.get_environment("OWN_SLOT")
	_slot = StringName(slot) if slot != "" else _slot
	_hold = StringName(OS.get_environment("OWN_HOLD"))
	var move := OS.get_environment("OWN_MOVE")
	_move = move.to_float() if move != "" else _move
	_ahead = OS.get_environment("OWN_AHEAD").to_float()
	_body = CharacterBodies.BY_NAME.get(OS.get_environment("OWN_BODY"), _body)
	_library = _read_review(REVIEW % (type if type != "" else "idle"))
	for clip in _library.get_animation_list():
		_clips.append(StringName("review/" + clip))
	_clips.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	_crouch = OS.get_environment("OWN_CROUCH") != ""
	_from = StringName(OS.get_environment("OWN_FROM"))
	if _slot != &"none":
		var replaced: StringName = _rig.player.get_node("Animation").get(_slot)
		_clips.append(CharacterClips.stand_in(replaced))
	_rig.player.get_node("AnimationPlayer").add_animation_library(&"review", _library)
	_pick_row(OS.get_environment("OWN_BEFORE"), OS.get_environment("OWN_ROW"))
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(40, 30)
	_label.add_theme_font_size_override(&"font_size", 34)
	layer.add_child(_label)
	var only := OS.get_environment("OWN_ONLY")
	_shown = StringName(OS.get_environment("OWN_PLAYER"))
	_into = StringName(OS.get_environment("OWN_INTO"))
	if _shown != &"":
		(_rig.player.get_node("AnimationTree") as AnimationTree).active = false
		_label.text = "shipped %s, from the game's camera" % _shown
		_replayed = -PLAYER_EVERY
		_part = 2
	elif only != "":
		var wanted := _clips[-1] if only == "Library" else StringName("review/" + only)
		if only == "Shipped":
			wanted = _rig.player.get_node("Animation").get(_slot)
			_clips.append(wanted)
		assert(_clips.has(wanted), "no clip %s in the review file" % only)
		_clips = [wanted]
		_part = 1
	else:
		_build_row.call_deferred()


func _physics_process(delta: float) -> void:
	_clock += delta
	if _part == 0:
		_film_row()
	elif _part == 1:
		_film_player()
	else:
		_film_shipped()


# Part 1: the row, from behind and then from the front.
func _film_row() -> void:
	if _row == null:
		return
	var front := _clock >= ROW_SECONDS
	var from := ROW_CAMERA * (Vector3(1, 1, -1) if front else Vector3.ONE)
	_row_camera.global_position = _row.global_transform * from
	_row_camera.look_at(_row.global_transform * Vector3(0, 0.95, 0))
	_label.text = (
		"side by side, from %s" % ["the front" if front else "behind, as the game sees them"]
	)
	_replay_row()
	if _clock >= 2.0 * ROW_SECONDS:
		if _slot == &"none":
			_finish()
			return
		_row_players.clear()
		_row.queue_free()
		_row = null
		_rig.player.visible = true
		_rig.camera_rig.camera.make_current()
		_part = 1
		_clock = 0.0


# A clip that plays once is played again every two seconds, after a rest on the pose it leaves.
func _replay_row() -> void:
	if _clock - _replayed < 2.0:
		return
	_replayed = _clock
	for i in _row_players.size():
		var clip := _clips[i]
		var player := _row_players[i]
		if player.get_animation(clip).loop_mode != Animation.LOOP_NONE:
			continue
		if _from != &"":
			player.play(_from)
			player.seek(0.0, true)
			player.pause()
			_play_later(player, clip)
		else:
			player.play(clip)
			player.seek(0.0, true)


func _play_later(player: AnimationPlayer, clip: StringName) -> void:
	await get_tree().create_timer(0.5, false, true).timeout
	if is_instance_valid(player):
		player.play(clip)


# Part 2: the real player, one variant at a time, the same input for each.
func _film_player() -> void:
	var length := STAND + _move + SETTLE + FRONT
	var turn := int(_clock / length)
	if turn >= _clips.size():
		_finish()
		return
	if turn != _turn:
		_turn = turn
		# Every turn starts on one place, facing one way, read once: `respawn()` picks a spawn
		# point and a spot on it at random, and later turns begin with the camera in front.
		if _way == Vector3.ZERO:
			var way := -_rig.camera_rig.camera.global_basis.z
			_way = Vector3(way.x, 0.0, way.z).normalized()
			_start = _rig.player.global_position + _way * _ahead
		if turn > 0 or _ahead > 0.0:
			_rig.player.teleport(_start, atan2(_way.x, _way.z))
		_rig.player.get_node("Animation").set(_slot, _clips[turn])
		_label.text = _name_of(_clips[turn])
	if _crouch:
		Input.action_press(&"crouch")
	var at := fmod(_clock, length)
	var moving := at >= STAND and at < STAND + _move
	for action: StringName in [&"move_forward", _hold]:
		if action == &"":
			continue
		if moving:
			Input.action_press(action)
		else:
			Input.action_release(action)
	_face(180.0 if at >= STAND + _move + SETTLE else 0.0)


# `OWN_PLAYER`: the shipped clip on the real player with the tree off, from the game's camera.
func _film_shipped() -> void:
	_face(180.0 if _clock >= ROW_SECONDS else 0.0)
	if _clock >= 2.0 * ROW_SECONDS:
		_finish()
		return
	if _clock - _replayed < PLAYER_EVERY:
		return
	_replayed = _clock
	var player: AnimationPlayer = _rig.player.get_node("AnimationPlayer")
	if _from != &"":
		player.play(_from)
		player.seek(0.0, true)
		player.pause()
	await get_tree().create_timer(PLAYER_REST, false, true).timeout
	player.play(_shown)
	if _into != &"":
		player.queue(_into)


func _build_row() -> void:
	_rig.player.visible = false
	_row = Node3D.new()
	add_child(_row)
	_row.global_transform = _rig.player.global_transform
	for i in _clips.size():
		var body: Node3D = (load(_body) as PackedScene).instantiate()
		_row.add_child(body)
		body.position = Vector3((i - 0.5 * (_clips.size() - 1)) * -SPACING, 0, 0)
		var player := AnimationPlayer.new()
		_row.add_child(player)
		player.root_node = player.get_path_to(body)
		var source: AnimationPlayer = _rig.player.get_node("AnimationPlayer")
		for library in source.get_animation_library_list():
			player.add_animation_library(library, source.get_animation_library(library))
		player.play(_clips[i])
		_row_players.append(player)
		var name_plate := Label3D.new()
		name_plate.text = _name_of(_clips[i])
		name_plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		var short := name_plate.text.length() <= 12
		name_plate.font_size = 26 if not short else (48 if _clips.size() > 3 else 34)
		name_plate.pixel_size = 0.004
		name_plate.no_depth_test = true
		name_plate.position = body.position + Vector3(0, 2.0, 0)
		_row.add_child(name_plate)
	_row_camera = Camera3D.new()
	_row_camera.fov = _rig.camera_rig.field_of_view
	add_child(_row_camera)
	_row_camera.make_current()
	_clock = 0.0


# Adds an older review file's clips as `before/<clip>` and keeps the row to the clips asked for.
func _pick_row(before: String, row: String) -> void:
	if before != "":
		var old := _read_review(before)
		_rig.player.get_node("AnimationPlayer").add_animation_library(&"before", old)
		for clip in old.get_animation_list():
			_clips.append(StringName("before/" + clip))
	if row == "":
		return
	var library := _clips[-1] if before == "" else _clips[_library.get_animation_list().size()]
	var picked: Array[StringName] = []
	for wanted in row.split(","):
		var clip := StringName(wanted if wanted.begins_with("before/") else "review/" + wanted)
		clip = library if wanted == "Library" else clip
		assert(_clips.has(clip), "no clip %s for the row" % wanted)
		picked.append(clip)
	_clips = picked


func _name_of(clip: StringName) -> String:
	var text := String(clip)
	if text.begins_with("before/"):
		return "before: %s" % text.trim_prefix("before/")
	if text.begins_with("review/"):
		return text.trim_prefix("review/")
	return ("shipped %s" if text.begins_with("gds/") else "library %s") % text


# Reads a clip file the game does not import: the clips of a glb as a library, a `_Loop` clip
# looping under its name without the suffix, as the importer makes them.
func _read_review(path: String) -> AnimationLibrary:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(ProjectSettings.globalize_path(path), state)
	assert(error == OK, "cannot read %s" % path)
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
	Input.action_release(&"crouch")
	if _hold != &"":
		Input.action_release(_hold)
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()
