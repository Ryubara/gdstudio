## Plays the prone and crawl clips (`assets/animation/prone/prone.glb`, kit #1009) on a body of
## the template, on a floor of 0.25 m squares: the library's crouch idle, down to prone, the prone
## idle, a crawl at the speed the clip was made for, the prone idle again and back up to the
## crouch. It plays the round four times: from the right side, from the front quarter, from
## behind and above, where the game's camera sits, and close over the arms from straight above
## (the head at the top), where the forearms' angle and the hands passing each other are read.
## While it crawls the body moves forward at
## `CRAWL_SPEED`, so a planted elbow or foot that slid would be seen moving over its square.
##
## Record it with Movie Maker through the kit:
## `gds capture frames --project game --seconds 39 --fps 30
## --scene res://tools/capture/prone_clips_tour.tscn`
## (`MODEL=male` films the template's male body, `MODEL=quaternius_female` or `quaternius_male`
## a Quaternius mannequin: `study_body.gd`; `PRONE_SHOTS=<folder>` also saves one still of each
## clip from the side, the front and the top; `PRONE_FISTS=<folder>` saves one sheet of the
## forearms and fists instead: the crawl at five moments of its cycle and the prone idle, from the
## game camera's place and close from the side, the front and above, and the legs from the side;
## `PRONE_CLIPS=<res path>` plays another clip file, for a Before).
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node3D

const STUDY_BODY := preload("res://tools/capture/study_body.gd")
const UAL1 := "res://assets/animation/universal/ual1.glb"
const OWN := "res://assets/animation/own/locomotion.glb"
const PRONE := "res://assets/animation/prone/prone.glb"
## Metres a second the crawl clip covers with its elbows and feet planted (the clip's README).
const CRAWL_SPEED := 0.618
## Seconds the crawl takes to reach its speed and to stop, and the clips to blend.
const BLEND := 0.25
## The round: a clip, its seconds and whether the body travels.
const STEPS: Array[Dictionary] = [
	{"clip": &"gds/Crouch_Idle", "seconds": 0.6},
	{"clip": &"prone/Crouch_To_Prone", "seconds": 0.9},
	{"clip": &"prone/Prone_Idle", "seconds": 1.7},
	{"clip": &"prone/Crawl_Fwd", "seconds": 3.7333, "travel": true, "blend": BLEND},
	{"clip": &"prone/Prone_Idle", "seconds": 1.0, "blend": BLEND},
	{"clip": &"prone/Prone_To_Crouch", "seconds": 1.0, "blend": 0.1},
	{"clip": &"gds/Crouch_Idle", "seconds": 0.6},
]
## Where each pass's camera stands from the body (the body faces +Z), and how wide it sees.
const VIEWS: Array[Dictionary] = [
	{"name": "side", "from": Vector3(-3.3, 0.7, 0.0), "at": Vector3(0, 0.4, 0), "fov": 34.0},
	{
		"name": "front quarter",
		"from": Vector3(-2.6, 1.5, 3.2),
		"at": Vector3(0, 0.3, 0),
		"fov": 38.0
	},
	{
		"name": "game camera",
		"from": Vector3(0.55, 2.0, -3.9),
		"at": Vector3(0, 0.5, 0.6),
		"fov": 60.0
	},
	{
		"name": "arms from above",
		"from": Vector3(0.0, 2.7, 0.69),
		"at": Vector3(0, 0, 0.7),
		"fov": 34.0
	},
]

var _holder: Node3D
var _player: AnimationPlayer
var _camera: Camera3D
var _label: Label
var _pass := 0
var _step := -1
var _left := 0.0
var _speed := 0.0


func _ready() -> void:
	_stage()
	_holder = Node3D.new()
	add_child(_holder)
	var model: Node3D = (load(STUDY_BODY.path()) as PackedScene).instantiate()
	_holder.add_child(model)
	_player = AnimationPlayer.new()
	_holder.add_child(_player)
	_player.root_node = _player.get_path_to(model)
	_player.add_animation_library(&"ual1", load(UAL1))
	_player.add_animation_library(&"gds", load(OWN))
	var clips := OS.get_environment("PRONE_CLIPS")
	_player.add_animation_library(&"prone", load(clips if clips != "" else PRONE))
	_camera = Camera3D.new()
	add_child(_camera)
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(40, 30)
	_label.add_theme_font_size_override(&"font_size", 34)
	layer.add_child(_label)
	var shots := OS.get_environment("PRONE_SHOTS")
	var fists := OS.get_environment("PRONE_FISTS")
	if fists != "":
		_fists.call_deferred(fists, STUDY_BODY.chosen())
	elif shots != "":
		_stills.call_deferred(shots)
	else:
		_next()


func _physics_process(delta: float) -> void:
	if _step < 0:
		return
	var travel: bool = STEPS[_step].get("travel", false) and _left > BLEND
	_speed = move_toward(_speed, CRAWL_SPEED if travel else 0.0, CRAWL_SPEED / BLEND * delta)
	_holder.position.z += _speed * delta
	_aim(VIEWS[_pass])
	_left -= delta
	if _left <= 0.0:
		_next()


func _next() -> void:
	_step += 1
	if _step >= STEPS.size():
		_step = 0
		_pass += 1
		_holder.position = Vector3.ZERO
		if _pass >= VIEWS.size():
			_step = -1
			get_tree().quit()
			return
	var step := STEPS[_step]
	_left = step.seconds
	_player.play(step.clip, step.get("blend", 0.0))
	_label.text = "%s   (%s, %s)" % [String(step.clip), VIEWS[_pass].name, STUDY_BODY.chosen()]
	_aim(VIEWS[_pass])


func _aim(view: Dictionary) -> void:
	_camera.fov = view.fov
	_camera.position = _holder.position + view.from
	_camera.look_at(_holder.position + view.at)


# One still of each of the four clips at its middle, from the side, the front and the top.
func _stills(folder: String) -> void:
	var shots := [
		{"name": "side", "from": Vector3(-4.0, 0.5, 0.0), "at": Vector3(0, 0.4, 0), "fov": 34.0},
		{"name": "front", "from": Vector3(0.0, 0.7, 4.4), "at": Vector3(0, 0.4, 0), "fov": 34.0},
		{"name": "top", "from": Vector3(0.01, 4.6, 0.0), "at": Vector3(0, 0, 0), "fov": 34.0},
	]
	for clip: StringName in [&"Prone_Idle", &"Crawl_Fwd", &"Crouch_To_Prone", &"Prone_To_Crouch"]:
		var animation := _player.get_animation(StringName("prone/" + clip))
		_player.play(StringName("prone/" + clip))
		_player.seek(animation.length * 0.5, true)
		_player.pause()
		for shot: Dictionary in shots:
			_label.text = "%s at %.2f s   (%s)" % [clip, animation.length * 0.5, shot.name]
			_aim(shot)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			image.save_png(folder.path_join("%s_%s.png" % [clip, shot.name]))
	get_tree().quit()


# The forearms and fists as one sheet, a row a view and a column a moment: the crawl at five
# moments of its cycle (the right arm plants at 0 %, the left at 50 %) and the prone idle; the
# last row is the legs from the side at the floor's height, the knees and feet on it.
func _fists(folder: String, model: String) -> void:
	var views := [
		{
			"name": "game camera, closer",
			"from": VIEWS[2].from,
			"at": Vector3(0, 0.2, 0.5),
			"fov": 16.0
		},
		{
			"name": "side",
			"from": Vector3(-1.7, 0.22, 0.86),
			"at": Vector3(0, 0.14, 0.86),
			"fov": 26.0
		},
		{"name": "front", "from": Vector3(0.0, 0.4, 2.5), "at": Vector3(0, 0.12, 0.8), "fov": 19.0},
		{"name": "above", "from": Vector3(0.01, 1.7, 0.98), "at": Vector3(0, 0, 0.98), "fov": 30.0},
		{
			"name": "legs, side",
			"from": Vector3(-2.2, 0.16, -0.45),
			"at": Vector3(0, 0.1, -0.45),
			"fov": 30.0
		},
	]
	var moments := [
		[&"prone/Crawl_Fwd", 0.0],
		[&"prone/Crawl_Fwd", 0.2],
		[&"prone/Crawl_Fwd", 0.4],
		[&"prone/Crawl_Fwd", 0.6],
		[&"prone/Crawl_Fwd", 0.8],
		[&"prone/Prone_Idle", 0.0],
	]
	var tile := Vector2i(640, 360)
	var sheet := Image.create(
		tile.x * moments.size(), tile.y * views.size(), false, Image.FORMAT_RGB8
	)
	_label.add_theme_font_size_override(&"font_size", 64)
	for column in moments.size():
		var clip: StringName = moments[column][0]
		_player.play(clip)
		_player.seek(_player.get_animation(clip).length * moments[column][1], true)
		_player.pause()
		for row in views.size():
			var view: Dictionary = views[row]
			_label.text = (
				"%s %d %%  (%s, %s)"
				% [
					String(clip).get_slice("/", 1),
					roundi(moments[column][1] * 100.0),
					view.name,
					model
				]
			)
			_aim(view)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			image.convert(Image.FORMAT_RGB8)
			image.resize(tile.x, tile.y, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(image, Rect2i(Vector2i.ZERO, tile), Vector2i(column, row) * tile)
	sheet.save_png(folder.path_join("prone_fists_%s.png" % model))
	get_tree().quit()


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
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	# a floor of 0.25 m squares: a two by two pixel image, repeated
	var image := Image.create(2, 2, false, Image.FORMAT_RGB8)
	for x in 2:
		for y in 2:
			image.set_pixel(
				x, y, Color(0.5, 0.52, 0.55) if (x + y) % 2 == 0 else Color(0.4, 0.42, 0.45)
			)
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.uv1_scale = Vector3(40, 40, 1)
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.material_override = material
	add_child(ground)
