## The vault study (kit #1010): plays `Vault_Low` and `Vault_High` from
## `assets/animation/vault/vault.glb` on the mannequin over each clip's reference box, with a
## sprint in, `Vault_Land` and a sprint out, from four views (a camera that follows behind the
## left shoulder as the game's does, the side, the front and the top, then four close views:
## `arm` on the hand that carries the body over, `landing` on the foot coming down, `free_arm`
## behind the right shoulder, on the arm that lets go, `legs` from past the box on the right,
## on the legs coming over the top). The body is moved forward
## at the speed `vault_clips.json` gives for the clip, the way the game moves it; the clips are
## sought frame by frame with no blending, so a join that does not fit shows.
##
## Run headless, it prints one `VAULT` line a clip: how far the planted hand moves in the world
## while it is on the box, its height over the top, the lowest foot and how near the right hand
## comes to the box. Record it with Movie Maker through the kit:
## `gds capture frames --project game --scene res://tools/capture/vault_study.tscn --seconds 22
## --fps 24` (`MODEL=male` films the male mannequin, `VIEWS=side,top` only those views,
## `SLOW=0.5` half speed, `LOW_HEIGHT=0.5` and `HIGH_HEIGHT=1.3` another box height, with the
## body lifted by the difference while a hand is on the top: the simplest warp).
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node3D

const VAULT := "res://assets/animation/vault/vault.glb"
const UAL1 := "res://assets/animation/universal/ual1.glb"
const CLIPS := "res://assets/animation/vault/vault_clips.json"
const SPRINT := &"ual1/Sprint"
const LAND := "Vault_Land"
## The sprint's own ground speed, to play it at the speed the body moves.
const SPRINT_SPEED := 6.5
## Seconds of sprint before and after each vault.
const RUN_IN := 0.5
const RUN_OUT := 11.0 / 24.0
const BOX_WIDTH := 3.0
const ALL_VIEWS: Array[String] = [
	"game", "side", "front", "top", "arm", "landing", "free_arm", "legs"
]

var _clips := {}
var _fps := 24
var _plan: Array[Dictionary] = []
var _clock := 0.0
var _slow := 1.0
var _model: Node3D
var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _camera: Camera3D
var _box: MeshInstance3D
var _label: Label
var _plan_clip := ""


func _ready() -> void:
	var file: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CLIPS))
	_clips = file.clips
	_fps = int(file.fps)
	_stage()
	var male := OS.get_environment("MODEL") == "male"
	var path := (
		"res://assets/characters/mannequin/mannequin_%s.glb" % ["male" if male else "female"]
	)
	_model = (load(path) as PackedScene).instantiate()
	add_child(_model)
	_skeleton = _model.find_children("*", "Skeleton3D", true, false)[0]
	_player = AnimationPlayer.new()
	add_child(_player)
	_player.root_node = _player.get_path_to(_model)
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_player.add_animation_library(&"ual1", load(UAL1))
	_player.add_animation_library(&"vault", load(VAULT))
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
		_report("male" if male else "female")
		get_tree().quit()
		return
	var views := ALL_VIEWS
	if OS.get_environment("VIEWS") != "":
		views.assign(OS.get_environment("VIEWS").split(","))
	if OS.get_environment("SLOW") != "":
		_slow = OS.get_environment("SLOW").to_float()
	for view in views:
		for clip: String in _clips:
			if clip != LAND:
				_plan.append({"view": view, "clip": clip})
	_process(0.0)


func _process(delta: float) -> void:
	if _plan.is_empty():
		return
	var index := 0
	var local := _clock
	while index < _plan.size() and local >= _length(_plan[index].clip):
		local -= _length(_plan[index].clip)
		index += 1
	if index >= _plan.size():
		set_process(false)
		get_tree().quit()
		return
	var step: Dictionary = _plan[index]
	_plan_clip = step.clip
	var phase := pose(step.clip, local - RUN_IN)
	_look(step.view, _clips[step.clip])
	_label.text = "%s   %s view   %+.2f s   %s" % [step.clip, step.view, local - RUN_IN, phase]
	_clock += delta * _slow


func _length(clip: String) -> float:
	return RUN_IN + _clips[clip].length + _clips[LAND].length + RUN_OUT


## Puts the model in the pose and at the place of `time` seconds after the vault clip starts
## (negative during the sprint in), over the clip's box, and says which part of the vault it is.
func pose(clip: String, time: float) -> String:
	var spec: Dictionary = _clips[clip]
	var land: Dictionary = _clips[LAND]
	var speed: float = spec.speed
	var ahead: float = spec.root_start + speed * minf(time, spec.length)
	var phase := "sprint in"
	var cycle := _player.get_animation(SPRINT).length
	var height := _height(clip)
	_set_box(height, spec.obstacle.depth)
	if time < 0.0:
		_seek(SPRINT, fposmod(time * speed / SPRINT_SPEED, cycle))
	elif time < spec.length:
		_seek(StringName("vault/" + clip), time)
		phase = _phase(spec.events, time)
	elif time < spec.length + land.length:
		var after: float = time - spec.length
		_seek(StringName("vault/" + LAND), after)
		ahead += land.speed * after
		phase = "landing step"
	else:
		var after: float = time - spec.length - land.length
		_seek(SPRINT, fposmod(after * land.speed / SPRINT_SPEED, cycle))
		ahead += land.speed * (land.length + after)
		phase = "sprint out"
	var lift: float = (height - spec.obstacle.height) * _raised(spec.events, time)
	_model.position = Vector3(0.0, lift, ahead)
	return phase


## The height of the box under a clip: its reference height, or `LOW_HEIGHT` / `HIGH_HEIGHT`.
func _height(clip: String) -> float:
	var asked := OS.get_environment("LOW_HEIGHT" if clip == "Vault_Low" else "HIGH_HEIGHT")
	return asked.to_float() if asked != "" else float(_clips[clip].obstacle.height)


## How much of the difference to another height the body is lifted by: none on the ground, all
## of it while a hand is on the top, none again at the landing (the simplest warp of the clip).
func _raised(events: Dictionary, time: float) -> float:
	var from: float = minf(events.takeoff, events.hand_plant - 0.125)
	var up := smoothstep(from, events.hand_plant, time)
	return up * (1.0 - smoothstep(events.hand_release, events.land, time))


func _phase(events: Dictionary, time: float) -> String:
	if time < events.takeoff:
		return "run-in step"
	if time < events.hand_plant:
		return "off the ground"
	if time <= events.hand_release:
		return "hand on top"
	return "over, coming down"


func _seek(clip: StringName, time: float) -> void:
	if _player.assigned_animation != clip:
		_player.play(clip)
	_player.seek(time, true)
	_player.advance(0.0)


func _set_box(height: float, depth: float) -> void:
	(_box.mesh as BoxMesh).size = Vector3(BOX_WIDTH, height, depth)
	_box.position = Vector3(0.0, height * 0.5, depth * 0.5)


func _look(view: String, spec: Dictionary) -> void:
	var middle := Vector3(0.0, 1.0, spec.obstacle.depth * 0.5)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	match view:
		"side":
			_camera.size = 3.4
			_camera.look_at_from_position(
				middle + Vector3(8, 0.3, 0.4), middle + Vector3(0, 0.3, 0.4)
			)
		"front":
			_camera.size = 3.2
			_camera.look_at_from_position(middle + Vector3(0, 0.3, 9), middle + Vector3(0, 0.3, 0))
		"arm":
			var hand := Vector3(spec.hand_place.left, _height(_plan_clip), spec.hand_place.forward)
			_camera.size = 2.0
			_camera.look_at_from_position(
				hand + Vector3(8.0, 0.9, 1.6), hand + Vector3(0.0, 0.35, 0.15)
			)
		"landing":
			var down := Vector3(0.0, 0.8, float(spec.root_at.land) + 0.2)
			_camera.size = 2.3
			_camera.look_at_from_position(down + Vector3(8, 0.2, 0), down)
		"free_arm":
			var shoulder := _bone("upperarm_r")
			_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			_camera.fov = 40.0
			_camera.look_at_from_position(
				shoulder + Vector3(-1.3, 0.5, -2.0), shoulder + Vector3(-0.2, -0.1, 0.1)
			)
		"legs":
			var hips := _bone("pelvis")
			_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			_camera.fov = 40.0
			_camera.look_at_from_position(
				hips + Vector3(-1.9, 0.7, 2.6), hips + Vector3(-0.3, -0.05, 0.0)
			)
		"top":
			_camera.size = 3.6
			_camera.look_at_from_position(
				Vector3(0, 9, middle.z + 0.4), Vector3(0, 0, middle.z + 0.4), Vector3.LEFT
			)
		_:
			_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			_camera.fov = 55.0
			var body := _model.position
			_camera.look_at_from_position(
				body + Vector3(1.5, 1.9, -3.3), body + Vector3(0, 1.0, 0.5)
			)


func _bone(bone: String) -> Vector3:
	var index := _skeleton.find_bone(bone)
	return (_skeleton.global_transform * _skeleton.get_bone_global_pose(index)).origin


# Prints, for each vault, what the build checks in Blender, measured on the pose Godot plays.
func _report(model: String) -> void:
	for clip: String in _clips:
		if clip == LAND:
			continue
		var spec: Dictionary = _clips[clip]
		var top := _height(clip)
		var low := Vector3(-BOX_WIDTH * 0.5, 0, 0)
		var high := Vector3(BOX_WIDTH * 0.5, top, spec.obstacle.depth)
		var planted: Array[Vector3] = []
		var lowest := 9.0
		var right_gap := 9.0
		for frame in int(spec.frames) + 1:
			var time: float = minf(frame / float(_fps), spec.length - 0.0001)
			pose(clip, time)
			for bone: String in ["foot_l", "foot_r", "ball_l", "ball_r"]:
				lowest = minf(lowest, _bone(bone).y)
			var right := _bone("hand_r")
			right_gap = minf(right_gap, right.distance_to(right.clamp(low, high)))
			if time >= spec.events.hand_plant - 0.001 and time <= spec.events.hand_release + 0.001:
				planted.append(_bone("hand_l"))
		var drift := 0.0
		var over := Vector2(9.0, -9.0)
		for place in planted:
			drift = maxf(drift, place.distance_to(planted[0]))
			over = Vector2(minf(over.x, place.y - top), maxf(over.y, place.y - top))
		print(
			(
				"VAULT %s %s: the left wrist moves %.1f mm while planted, "
				% [model, clip, drift * 1e3]
			),
			"%.1f to %.1f mm over the top; " % [over.x * 1e3, over.y * 1e3],
			(
				"lowest foot bone %.1f mm; the right wrist stays %.2f m off the box"
				% [lowest * 1e3, right_gap]
			)
		)


func _stage() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.36, 0.39, 0.44)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.environment.ambient_light_energy = 0.7
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 150, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	ground.mesh = plane
	ground.material_override = load("res://assets/materials/prototype/prototype_floor.tres")
	add_child(ground)
	_box = MeshInstance3D.new()
	_box.mesh = BoxMesh.new()
	_box.material_override = load("res://assets/materials/prototype/prototype_orange.tres")
	add_child(_box)
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(32, 24)
	_label.add_theme_font_size_override("font_size", 36)
	layer.add_child(_label)
