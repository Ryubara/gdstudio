## Close-ups of the rifle clips (kit #1082), one picture a pose: a mannequin holding the rifle the
## way the loadout builds it (`RifleStage`), the standing legs under it, a rifle clip on the upper
## body at a share of its length, and the hold told what the game tells it while that clip plays
## (how far the rifle is up, the view's pitch, the shot's kick, the reload's share). Three views at
## once: from the character's right, from above and from the player's camera behind the right
## shoulder. Both mannequins.
##
## Run it with a window through the kit; it writes `<model>_<clip>_<share>.png` into the folder
## `CLOSEUPS_OUT` names and quits:
## `CLOSEUPS_OUT=<folder> gds godot -- --path game res://tools/capture/rifle_clip_closeups.tscn`
## For each pose it prints `CLOSEUP` with how far each hand's bone is from its place on the rifle
## and the skin of each hand against it (`HandContact`). It lives in tools/, which the export
## leaves out, and nothing in the game refers to it.
extends Node3D

const LIBRARY := "res://assets/animation/rifle/rifle_clips.glb"
const UPPER := &"spine_01"
## Each clip: how far the rifle is up, the view's pitch, whether its share is the reload's, and
## the shares pictured.
const POSES: Dictionary[StringName, Array] = {
	&"Rifle_Idle": [0.0, 0.0, false, [0.0, 0.4]],
	&"Rifle_Aim_Neutral": [1.0, 0.0, false, [0.0]],
	&"Rifle_Aim_Up": [1.0, 45.0, false, [0.0]],
	&"Rifle_Aim_Down": [1.0, -45.0, false, [0.0]],
	&"Rifle_Shoot": [1.0, 0.0, false, [0.0, 0.0834, 0.25, 0.4167]],
	&"Rifle_Reload": [0.0, 0.0, true, [0.12, 0.2, 0.3, 0.42, 0.56, 0.62, 0.76, 0.88]],
}
## The views: the name, where the camera is, what it looks at and which way is up, in the
## model's space (it faces +Z, its left is +X).
const VIEWS: Array[Array] = [
	["from the right", Vector3(-2.3, 1.38, 0.22), Vector3(0.0, 1.34, 0.22), Vector3.UP],
	["from above", Vector3(0.0, 3.5, 0.25), Vector3(0.0, 1.3, 0.24), Vector3.BACK],
	["the player's camera", Vector3(-0.6, 1.8, -1.9), Vector3(-0.12, 1.4, 0.5), Vector3.UP],
]
## How fast the shot's clip plays against its own speed, and the hold's kick's seconds.
const SHOOT_SPEED := 1.6

var _title: Label


func _ready() -> void:
	var out := OS.get_environment("CLOSEUPS_OUT")
	if out.is_empty():
		printerr("rifle_clip_closeups: name the folder for the pictures in CLOSEUPS_OUT")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	_light()
	_views()
	var library := load(LIBRARY) as AnimationLibrary
	for model: String in HoldStage.MODELS:
		var stage := RifleStage.make_rifle(self, model)
		for clip_name in POSES:
			var clip := library.get_animation(clip_name)
			for share: float in POSES[clip_name][3]:
				_pose(stage, clip_name, clip, share)
				await stage.settle()
				_title.text = "%s, %s at %.2f" % [model, clip_name, share]
				_report(stage, _title.text)
				for frame in 3:
					await RenderingServer.frame_post_draw
				var path := out.path_join(
					"%s_%s_%03d.png" % [model, clip_name, roundi(share * 100)]
				)
				get_viewport().get_texture().get_image().save_png(path)
		stage.free()
	get_tree().quit()


func _pose(stage: RifleStage, clip_name: StringName, clip: Animation, share: float) -> void:
	var held := stage.hold as TwoHandHold
	var state: Array = POSES[clip_name]
	held.posed_aim = state[0]
	held.posed_pitch = state[1]
	held.posed_reload = share if state[2] else -1.0
	# The kick is whole on the tick of the shot and gone `kick_recover_time` of real time later.
	var kick := 0.0
	if clip_name == &"Rifle_Shoot" and share > 0.0:
		var since := share * clip.length / SHOOT_SPEED - 1.0 / 30.0 / SHOOT_SPEED
		kick = clampf(1.0 - since / held.kick_recover_time, 0.0, 1.0)
	# The hold is posed whole here, with its own stepping off: it would let the kick go again.
	held.set_process(false)
	held.set(&"_kick", kick)
	held.set(&"_raised", float(state[0]))
	var kept := stage.hold
	stage.hold = null
	stage.pose(CharacterClips.IDLE, 0.0)
	stage.hold = kept
	var start := stage.skeleton.find_bone(UPPER)
	for track in clip.get_track_count():
		if clip.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := stage.skeleton.find_bone(
			String(clip.track_get_path(track).get_concatenated_subnames())
		)
		var cursor := bone
		while cursor >= 0 and cursor != start:
			cursor = stage.skeleton.get_bone_parent(cursor)
		if cursor >= 0:
			stage.skeleton.set_bone_pose_rotation(
				bone, clip.rotation_track_interpolate(track, share * clip.length)
			)
	held.refresh()


func _report(stage: RifleStage, tag: String) -> void:
	var line := (
		"CLOSEUP %s | r %.1f mm | l %.1f mm"
		% [tag, stage.hand_gap("r") * 1e3, stage.hand_gap("l") * 1e3]
	)
	for side: String in ["r", "l"]:
		var deepest := 0.0
		var parts := stage.contact.measure(side)
		for part: String in parts:
			deepest = maxf(deepest, -parts[part].distance)
		line += " | %s in %.1f mm" % [side, deepest * 1e3]
	print(line)


func _light() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.86, 0.89, 0.93)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.environment.ambient_light_energy = 0.7
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 150.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)


func _views() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override(&"separation", 2)
	layer.add_child(row)
	for view in VIEWS:
		var container := SubViewportContainer.new()
		container.stretch = true
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_child(container)
		var port := SubViewport.new()
		port.world_3d = get_viewport().world_3d
		port.msaa_3d = Viewport.MSAA_4X
		container.add_child(port)
		var camera := Camera3D.new()
		camera.fov = 32.0
		port.add_child(camera)
		camera.look_at_from_position(view[1], view[2], view[3])
		var label := Label.new()
		label.text = view[0]
		label.position = Vector2(12.0, 44.0)
		label.add_theme_color_override(&"font_color", Color.BLACK)
		container.add_child(label)
	_title = Label.new()
	_title.position = Vector2(12.0, 8.0)
	_title.add_theme_font_size_override(&"font_size", 24)
	_title.add_theme_color_override(&"font_color", Color.BLACK)
	layer.add_child(_title)
