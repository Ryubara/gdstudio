extends Node3D
## Crowd benchmark. Run (after a one-time `--import`):
##   godot --path sandbox/crowds --fixed-fps 60 -- --count=40 --techs=repath,lod --warmup=300 --frames=600
## Techniques (comma list): avoid_off, repath, tune, lod, vis, bones, noeyelid, phys30, shadows, all, movie.
## Prints one `RESULT` line and quits (unless `movie`, which just keeps running for Movie Maker).

const ZOMBIE_MODEL := preload("res://assets/zombie.glb")
const SEED := 42
const FLOOR_HALF := 50.0
const SPAWN_MIN := 8.0
const SPAWN_MAX := 26.0
const TARGET_RADIUS := 12.0
const TARGET_SPEED := 2.5
const REPATH_INTERVAL := 0.25
const VIS_RANGE := 32.0
const CAMERA_OFFSET := Vector3(0.0, 11.0, 10.0)
const OBSTACLES := [
	[Vector3(-18, 1, -4), Vector3(4, 2, 10)],
	[Vector3(20, 1, 6), Vector3(10, 2, 3)],
	[Vector3(2, 1, -22), Vector3(12, 2, 3)],
	[Vector3(-6, 1, 24), Vector3(3, 2, 12)],
	[Vector3(30, 1, -20), Vector3(6, 2, 6)],
	[Vector3(-32, 1, 20), Vector3(6, 2, 6)],
]
const STRIP_BONES := ["Tongue", "Eyelid", "Pinky", "Middle", "Index", "Thumb", "PoleTarget"]

var count := 40
var techs: PackedStringArray = []
var warmup := 300
var frames := 600

var _target: Node3D
var _camera: Camera3D
var _zombies: Array[Zombie] = []
var _lod: CrowdLod
var _frame := 0
var _last_us := 0
var _dts: PackedFloat64Array = []
var _sum_draw := 0.0
var _sum_prims := 0.0
var _angle := 0.0
var _running := false


func _ready() -> void:
	_parse_args()
	_expand_all()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	seed(SEED)
	if has("phys30"):
		Engine.physics_ticks_per_second = 30
	_build_world()
	await _bake_navmesh()
	_prepare_animations()
	_spawn()
	_running = true
	_last_us = Time.get_ticks_usec()


func has(t: String) -> bool:
	return techs.has(t)


func _args() -> PackedStringArray:
	if OS.has_feature("web"):  # the page URL carries them: index.html?count=40&techs=all
		var query := String(JavaScriptBridge.eval("window.location.search")).trim_prefix("?")
		return PackedStringArray(Array(query.split("&", false)).map(func(a: String) -> String: return "--" + a))
	return OS.get_cmdline_user_args()


func _parse_args() -> void:
	for a in _args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		var v := kv[1] if kv.size() > 1 else ""
		match kv[0]:
			"count": count = int(v)
			"techs": techs = v.split(",", false)
			"warmup": warmup = int(v)
			"frames": frames = int(v)


func _expand_all() -> void:
	if has("all"):
		for t in ["repath", "tune", "lod", "vis", "bones", "noeyelid", "phys30"]:
			if not has(t):
				techs.append(t)


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.1, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.7)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	sun.shadow_enabled = has("shadows")
	add_child(sun)

	var floor_body := _box(Vector3(0, -0.5, 0), Vector3(FLOOR_HALF * 2.0, 1.0, FLOOR_HALF * 2.0), Color(0.22, 0.26, 0.22))
	floor_body.name = "Floor"
	for o in OBSTACLES:
		_box(o[0], o[1], Color(0.4, 0.38, 0.36))

	_target = Node3D.new()
	_target.name = "Target"
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.4
	cap.height = 1.8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.55, 1.0)
	cap.material = mat
	mi.mesh = cap
	mi.position.y = 0.9
	_target.add_child(mi)
	add_child(_target)
	_target.position = Vector3(TARGET_RADIUS, 0.0, 0.0)

	_camera = Camera3D.new()
	_camera.fov = 60.0
	_camera.far = 120.0
	add_child(_camera)
	_camera.current = true
	_follow_camera()


func _box(pos: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	add_child(body)
	return body


func _bake_navmesh() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, self)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	var region := NavigationRegion3D.new()
	region.navigation_mesh = nm
	add_child(region)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _prepare_animations() -> void:
	var probe: Node = ZOMBIE_MODEL.instantiate()
	var player: AnimationPlayer = probe.find_child("AnimationPlayer", true, false)
	for clip in ["Walk", "Run"]:
		player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	if has("bones"):
		for clip in ["Walk", "Run", "Punch"]:
			var anim := player.get_animation(clip)
			for i in range(anim.get_track_count() - 1, -1, -1):
				var bone := String(anim.track_get_path(i).get_concatenated_subnames())
				for s in STRIP_BONES:
					if bone.begins_with(s):
						anim.remove_track(i)
						break
	probe.free()


func _spawn() -> void:
	if has("lod"):
		_lod = CrowdLod.new()
		_lod.camera = _camera
		add_child(_lod)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for i in count:
		var ang := rng.randf() * TAU
		var rad := rng.randf_range(SPAWN_MIN, SPAWN_MAX)
		var z := Zombie.new()
		z.position = Vector3(cos(ang) * rad, 0.05, sin(ang) * rad)
		var interval := REPATH_INTERVAL if has("repath") else 0.0
		add_child(z)
		z.setup(ZOMBIE_MODEL, _target, {
			"speed": rng.randf_range(1.6, 4.0),
			"repath_interval": interval,
			"repath_phase": rng.randf() * interval,
			"attack_phase": rng.randf() * 1.2,
			"avoidance": not has("avoid_off"),
			"avoid_tune": has("tune"),
			"no_eyelid": has("noeyelid"),
			"vis_range": VIS_RANGE if has("vis") else 0.0,
		})
		if has("bones"):
			for n in z.find_children("*", "BoneAttachment3D", true, false):
				n.queue_free()
		_zombies.append(z)
		if _lod:
			_lod.add_zombie(z)


func _physics_process(delta: float) -> void:
	_angle += TARGET_SPEED / TARGET_RADIUS * delta
	_target.position = Vector3(cos(_angle), 0.0, sin(_angle)) * TARGET_RADIUS


func _process(_delta: float) -> void:
	_follow_camera()
	if not _running or has("movie"):
		return
	var now := Time.get_ticks_usec()
	var dt := (now - _last_us) / 1000.0
	_last_us = now
	_frame += 1
	if _frame <= warmup:
		return
	_dts.append(dt)
	_sum_draw += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_sum_prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	if _dts.size() >= frames:
		_report()
		if not OS.has_feature("web"):
			get_tree().quit()
		_running = false


func _follow_camera() -> void:
	_camera.position = _target.position + CAMERA_OFFSET
	_camera.look_at(_target.position + Vector3(0, 0.5, 0))


func _report() -> void:
	var sorted := _dts.duplicate()
	sorted.sort()
	var n := float(sorted.size())
	var mean := 0.0
	for d in sorted:
		mean += d
	mean /= n
	var line := "RESULT count=%d techs=%s mean_ms=%.2f p95_ms=%.2f max_ms=%.2f draws=%d tris=%d display=%s" % [
		count, ",".join(techs) if techs.size() else "none", mean, sorted[int(n * 0.95)], sorted[-1],
		int(_sum_draw / n), int(_sum_prims / n),
		DisplayServer.get_name(),
	]
	print(line)
	_show(line)


func _show(text: String) -> void:
	## On screen too, so a browser run can be read without the console.
	var label := Label.new()
	label.text = text
	label.position = Vector2(8, 8)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	var layer := CanvasLayer.new()
	layer.add_child(label)
	add_child(layer)
