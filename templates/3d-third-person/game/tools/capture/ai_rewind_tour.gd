## Lag compensation for shots on the AI, for a clip of two screens side by side (gdstudio #1198):
## the left half is the game server's own world, seen from where Ada's camera is, the right half
## Ada's screen, 150 ms away each way. A guard runs to and fro across the lane; Ada fires at the
## guard her screen draws, leading it by the round's flight. Three shots with the rewind off: the
## server has the guard about a metre further on and the rounds pass behind it. Three with the
## rewind on: each is met where Ada's screen drew the guard (a ghost capsule on the server's half
## for a second) and hits. The pistol's spread is off for the clip. The server and both clients
## run in this process over a real socket (`tests/fixtures/online_rig.gd`), each with a map of its
## own. Record it at 60 frames a second (studio/capture.md: an online rig at fewer is not the game).
##
## `gds capture frames --project game --scene res://tools/capture/ai_rewind_tour.tscn --seconds
## 15 --fps 60`. It lives in tools/, which the export leaves out.
extends Node

const VIEW := Vector2i(960, 540)
const DELAY := 0.15
## Ada on the open ground west of the push cubes, facing north; the guard's lane 6 m in front.
const ADA_AT := Vector3(-9.0, 0.3, 19.0)
const BO_AT := Vector3(-5.0, 0.3, 19.0)
const LANE_WEST := Vector3(-12.0, 0.3, 13.0)
const FACING_NORTH := PI
const CHEST := 1.2
const ROUND_SPEED := 45.0
## Ticks of one run across the lane (about 6 m), then it turns back.
const PASS_TICKS := 90
## Ticks after a turn that Ada's screen is in the middle of the run (the turn reaches it some
## 16 ticks late), where each shot is pressed; one shot a run, after a run to get up to speed.
const MID_PASS := 61
## Shots in each half.
const SHOTS := 3
## Seconds a ghost capsule stays where the server met a shot.
const GHOST_SECONDS := 1.0

var _rig: OnlineRig
var _ada: NetClient
var _guard: AiCharacter
var _server_camera: Camera3D
var _aim := Callable()
var _presses: Array[int] = []
var _label: Label
var _ghost: Node3D
var _ghost_left := 0.0
var _hits := [0, 0]
var _fired := [0, 0]
# The half of the last shot the server fired (its hit counts there).
var _shot_half := 0
var _walked := 0


func _ready() -> void:
	_rig = OnlineRig.new(false)
	_rig.view_size = VIEW
	_rig.delay = DELAY
	add_child(_rig)
	_rig.start()
	_rig.server.ai_rewind_seconds = 0.0
	_ada = await _rig.join("Ada", 600)
	var bo := await _rig.join("Bo", 600)
	_put(_ada, ADA_AT, FACING_NORTH)
	_put(bo, BO_AT, FACING_NORTH)
	var rig := _ada.player.get_parent() as PlayerRig
	rig.camera_rig.yaw = 0.0
	rig.camera_rig.pitch = -5.0
	_guard = AiNetStage.walker(LANE_WEST, Vector3.RIGHT, 1.0)
	_rig.server.get_node("World").add_child(_guard)
	Health.of(_guard).max_value = 100000.0
	Health.of(_guard).value = 100000.0
	Health.of(_guard).damaged.connect(
		func(_a: float, _h: HitRecord) -> void: _hits[_shot_half] += 1
	)
	_rig.server_body(_ada).weapon.fired.connect(_on_server_fired)
	# No spread (the pistol's definition is one resource in this process, the server's and Ada's):
	# each round goes where she aims, so a miss is the server's judgement, not the spread's.
	_rig.server_body(_ada).weapon.definition.spread = 0.0
	_rig.controllers[0].plan = _plan
	_server_camera = Camera3D.new()
	_server_camera.current = true
	_rig.server_view.add_child(_server_camera)
	_ghost = _make_ghost()
	_rig.server.get_node("World").add_child(_ghost)
	_show(_rig.server_view, 0, "The server's world")
	_show(_rig.views[0], 1, "Ada's screen, 150 ms away each way")
	_label = Label.new()
	_label.position = Vector2(12, VIEW.y - 40)
	_label.add_theme_font_size_override(&"font_size", 22)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 5)
	add_child(_label)
	# The server's world draws from now on: its probes too, at once.
	await _rig.settle(_rig.server_view)
	var id := int(_guard.get_meta(NetHits.AI_META, -1))
	while _ada.ai_replica.puppet_of(id) == null:
		await get_tree().physics_frame
		id = int(_guard.get_meta(NetHits.AI_META, -1))
	var puppet := _ada.ai_replica.puppet_of(id)
	_aim = func() -> Vector3:
		var chest := puppet.global_position + Vector3.UP * CHEST
		var flight := _ada.player.global_position.distance_to(chest) / ROUND_SPEED
		return chest + puppet.velocity * flight
	# Runs counted from here: the guard turns every `PASS_TICKS`.
	_walked = 0
	var now: int = _rig.controllers[0].ticks
	for shot in SHOTS * 2:
		_presses.append(now + (shot + 1) * PASS_TICKS + MID_PASS)
	# The rewind goes on halfway through the run after the last shot of the first half, early
	# enough for the history to hold the next shot's view.
	await _rig.wait(SHOTS * PASS_TICKS + MID_PASS + PASS_TICKS / 2)
	_rig.server.ai_rewind_seconds = 0.6


func _physics_process(delta: float) -> void:
	if _guard == null or not is_instance_valid(_guard):
		return
	# To and fro across the lane, a run every `PASS_TICKS`.
	_walked += 1
	if _walked % PASS_TICKS == 0:
		var way := (_guard.controller as AiController).walk_direction
		AiNetStage.walk(_guard, -way, 1.0)
	_ghost_left -= delta
	_ghost.visible = _ghost_left > 0.0


func _process(_delta: float) -> void:
	if _ada == null or not _ada.is_seated() or _server_camera == null:
		return
	var camera := _ada.get_viewport().get_camera_3d()
	if camera != null:
		_server_camera.global_transform = camera.global_transform
		_server_camera.fov = camera.fov
	var on := _rig.server.ai_rewind_seconds > 0.0
	_label.text = (
		"Rewind off: %d of %d shots hit     Rewind on: %d of %d hit     (now %s)"
		% [_hits[0], _fired[0], _hits[1], _fired[1], "on" if on else "off"]
	)


# Which half a shot or hit counts in: 1 once the rewind is on.
func _half() -> int:
	return 1 if _rig.server.ai_rewind_seconds > 0.0 else 0


# The server's body fired (inside its step, while its weapon holds the command's rewind): the
# ghost goes where the shot meets the guard.
func _on_server_fired(_projectile: Projectile) -> void:
	_shot_half = _half()
	_fired[_shot_half] += 1
	var weapon := _rig.server_body(_ada).weapon
	if weapon.rewind == null:
		return
	var shot := weapon.rewind.for_shot(weapon.last_origin, weapon.last_heading, 30.0)
	var tick := shot.tick_of(_guard)
	if tick < 0:
		return
	var id := int(_guard.get_meta(NetHits.AI_META, -1))
	_ghost.global_position = _rig.server.ai_history.position_at(id, tick)
	_ghost_left = GHOST_SECONDS


# A see-through capsule standing on its feet point, the size of a character's.
func _make_ghost() -> Node3D:
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.34
	capsule.height = 1.8
	var paint := StandardMaterial3D.new()
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.albedo_color = Color(0.3, 0.9, 1.0, 0.4)
	capsule.material = paint
	var shape := MeshInstance3D.new()
	shape.mesh = capsule
	shape.position.y = capsule.height / 2.0
	var ghost := Node3D.new()
	ghost.add_child(shape)
	ghost.visible = false
	return ghost


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


func _put(client: NetClient, spot: Vector3, heading: float) -> void:
	_rig.server_body(client).teleport(spot, heading)
	client.player.teleport(spot, heading)


func _show(view: SubViewport, column: int, title: String) -> void:
	var picture := TextureRect.new()
	picture.texture = view.get_texture()
	picture.position = Vector2(column * VIEW.x, 0)
	picture.size = Vector2(VIEW)
	add_child(picture)
	var label := Label.new()
	label.text = title
	label.position = Vector2(column * VIEW.x + 12, 8)
	label.add_theme_font_size_override(&"font_size", 20)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 4)
	add_child(label)
