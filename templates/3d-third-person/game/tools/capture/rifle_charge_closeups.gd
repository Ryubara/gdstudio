## Close-ups of the left hand on the rifle's charging handle (kit #1266): a body holding the rifle
## the way the loadout builds it (`RifleStage`), the rifle's reload clip on the upper body at a
## share of the reload over the standing idle, and the hold told that share. Four views at once,
## three from cameras that ride the rifle round the handle (from the rifle's left, from above,
## from the front and the left, low) and the player's camera behind the right shoulder; the
## shares are the reach, the grip, the pull's end and the release (`SHARES`), on both of the
## template's bodies.
##
## Run it with a window through the kit; it writes `charge_<model>_<share>.png` into the folder
## `CLOSEUPS_OUT` names and quits:
## `CLOSEUPS_OUT=<folder> gds godot -- --path game res://tools/capture/rifle_charge_closeups.tscn`
## (`CLOSEUPS_SHARES=0.7,0.8` for other shares). For each pose it prints `CHARGE` with how far the
## left hand's bone is from its place and its skin against the rifle (`HandContact`, the bolt
## where it is). It lives in tools/, which the export leaves out.
extends Node3D

const LIBRARY := "res://assets/animation/rifle/rifle_clips.glb"
const DATA := "res://assets/animation/rifle/rifle_clips.json"
## The empty magazine's reload: only it has the pull (kit #1508).
const CLIP := &"Rifle_Reload_Empty"
const UPPER := &"spine_01"
## The reach, the grip, the pull's end, the release and back on the hand guard.
const SHARES: Array[float] = [0.74, 0.8, 0.86, 0.88]
## The views riding the rifle: the name, where the camera is from the handle and which way is up,
## in the rifle's space (the muzzle along -X, up +Y, its left +Z).
const RIFLE_VIEWS: Array[Array] = [
	["from the rifle's left", Vector3(0.0, 0.04, 0.42), Vector3.UP],
	["from above", Vector3(0.03, 0.42, 0.06), Vector3.LEFT],
	["from the front and the left, low", Vector3(-0.3, -0.12, 0.28), Vector3.UP],
]
## The player's camera: behind the right shoulder, from the handle in the model's space (+Z its
## front, +X its left), looking at it.
const PLAYER_VIEW := ["the player's camera", Vector3(-0.35, 0.45, -1.1)]
## The handle's middle, in the rifle's space (the latch's tab), which the cameras look at.
const HANDLE := Vector3(0.058, 0.165, 0.03)

var _title: Label
var _cameras: Array[Camera3D] = []
var _base_time := 0.0


func _ready() -> void:
	var out := OS.get_environment("CLOSEUPS_OUT")
	if out.is_empty():
		printerr("rifle_charge_closeups: name the folder for the pictures in CLOSEUPS_OUT")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var shares := SHARES.duplicate()
	if not OS.get_environment("CLOSEUPS_SHARES").is_empty():
		shares.clear()
		for word in OS.get_environment("CLOSEUPS_SHARES").split(","):
			shares.append(float(word))
	_light()
	_views()
	var clip := (load(LIBRARY) as AnimationLibrary).get_animation(CLIP)
	_base_time = JSON.parse_string(FileAccess.get_file_as_string(DATA)).base.seconds
	for model: String in HoldStage.MODELS:
		var stage := RifleStage.make_rifle(self, model)
		for share: float in shares:
			_pose(stage, clip, share)
			await stage.settle()
			_aim(stage)
			_title.text = "%s, the reload at %.2f" % [model, share]
			_report(stage, _title.text)
			for frame in 3:
				await RenderingServer.frame_post_draw
			var path := out.path_join("charge_%s_%03d.png" % [model, roundi(share * 100)])
			get_viewport().get_texture().get_image().save_png(path)
		stage.free()
	get_tree().quit()


func _pose(stage: RifleStage, clip: Animation, share: float) -> void:
	var held := stage.hold as TwoHandHold
	held.posed_aim = 0.0
	held.posed_pitch = 0.0
	held.posed_reload = share
	held.set_process(false)
	var kept := stage.hold
	stage.hold = null
	stage.pose(CharacterClips.IDLE, _base_time)
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


# Puts the cameras that ride the rifle where it is now.
func _aim(stage: RifleStage) -> void:
	var gun := stage.rifle.global_transform.orthonormalized()
	var at := gun * HANDLE
	for index in RIFLE_VIEWS.size():
		var view: Array = RIFLE_VIEWS[index]
		_cameras[index].global_position = at + gun.basis * (view[1] as Vector3)
		_cameras[index].look_at(at, gun.basis * (view[2] as Vector3))
	var model := stage.slot.global_transform.orthonormalized()
	_cameras[-1].global_position = at + model.basis * (PLAYER_VIEW[1] as Vector3)
	_cameras[-1].look_at(at, Vector3.UP)


func _report(stage: RifleStage, tag: String) -> void:
	# The bolt moves: the rifle's triangles are read again where it is now.
	stage.contact.set_weapon(stage.rifle.get_node(^"Near") as Node3D)
	var parts := stage.contact.measure("l")
	print(
		(
			"CHARGE %s | l %.1f mm | %s"
			% [
				tag,
				stage.hand_gap("l") * 1e3,
				HandContact.summary(parts, RifleStage.RIFLE_CHARGE_CONTACTS)
			]
		)
	)


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
	var grid := GridContainer.new()
	grid.columns = 2
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid.add_theme_constant_override(&"h_separation", 2)
	grid.add_theme_constant_override(&"v_separation", 2)
	layer.add_child(grid)
	for view: Array in RIFLE_VIEWS + [PLAYER_VIEW]:
		var container := SubViewportContainer.new()
		container.stretch = true
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		grid.add_child(container)
		var port := SubViewport.new()
		port.world_3d = get_viewport().world_3d
		port.msaa_3d = Viewport.MSAA_4X
		container.add_child(port)
		var camera := Camera3D.new()
		camera.fov = 32.0
		camera.near = 0.02
		port.add_child(camera)
		_cameras.append(camera)
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
