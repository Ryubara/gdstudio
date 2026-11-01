extends Node
## Builds the night scene for one setup, renders it in a SubViewport of a chosen size, measures frame
## time over a fixed number of frames, optionally saves a screenshot, prints one RESULT line, quits.
##
## Run: godot --path sandbox/compat-lighting -- --setup=omni8+glow --w=1920 --h=1080 --shot=out.png
## Flags: --setup=tok+tok (default base), --w, --h (render size), --warmup, --frames, --shot=path,
## --sway (slow camera drift, for movies), --keep (do not quit).

const CAMERA_POS := Vector3(0.0, 2.0, 17.0)
const CAMERA_TARGET := Vector3(0.0, 3.2, -26.0)
const NIGHT_BACKGROUND := Color(0.012, 0.016, 0.035)
const NIGHT_AMBIENT := Color(0.05, 0.06, 0.11)

var _setup_name := "base"
var _size := Vector2i(1920, 1080)
var _warmup := 120
var _frames := 300
var _shot_path := ""
var _sway := false
var _keep := false

var _viewport: SubViewport
var _camera: Camera3D
var _deltas: PackedFloat64Array = []
var _gpu_ms: PackedFloat64Array = []
var _cpu_ms: PackedFloat64Array = []
var _frame := 0
var _last_usec := 0
var _finishing := false


func _ready() -> void:
	_parse_args()
	var setup := Setups.new(_setup_name.split("+"))
	_viewport = SubViewport.new()
	_viewport.size = _size
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var world := NightScene.build(setup.ground_tiles(), setup.uses_lightmap())
	_viewport.add_child(world)
	_camera = Camera3D.new()
	_camera.fov = 70.0
	_camera.position = CAMERA_POS
	_viewport.add_child(_camera)
	_camera.look_at(CAMERA_TARGET)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = NIGHT_BACKGROUND
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = NIGHT_AMBIENT
	env.ambient_light_energy = 1.0
	_camera.environment = env
	setup.apply(world, _camera, env, _viewport)

	var view := TextureRect.new()
	view.texture = _viewport.get_texture()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	var canvas := CanvasLayer.new()
	canvas.add_child(view)
	add_child(canvas)

	RenderingServer.viewport_set_measure_render_time(_viewport.get_viewport_rid(), true)
	_last_usec = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	if _finishing:
		return
	var now := Time.get_ticks_usec()
	_frame += 1
	if _sway:
		var t := float(_frame) / 60.0
		_camera.position = CAMERA_POS + Vector3(sin(t * 0.5) * 6.0, sin(t * 0.3) * 0.4, 0.0)
		_camera.look_at(CAMERA_TARGET)
	if _frame > _warmup:
		_deltas.append((now - _last_usec) / 1000.0)
		var rid := _viewport.get_viewport_rid()
		_gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		_cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
	_last_usec = now
	if _frame >= _warmup + _frames and not _keep:
		_finishing = true
		_finish.call_deferred()


func _finish() -> void:
	await RenderingServer.frame_post_draw
	if _shot_path != "":
		_viewport.get_texture().get_image().save_png(_shot_path)
	var result := {
		"setup": _setup_name,
		"size": "%dx%d" % [_size.x, _size.y],
		"frame_ms_mean": _mean(_deltas),
		"frame_ms_p95": _percentile(_deltas, 0.95),
		"frame_ms_max": snappedf(_max(_deltas), 0.001),
		"gpu_ms_mean": _mean(_gpu_ms),
		"cpu_render_ms_mean": _mean(_cpu_ms),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"vram_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"adapter": RenderingServer.get_video_adapter_name(),
	}
	print("RESULT ", JSON.stringify(result))
	get_tree().quit()


func _mean(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	return snappedf(total / values.size(), 0.001)


func _percentile(values: PackedFloat64Array, fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return snappedf(sorted[int(floor((sorted.size() - 1) * fraction))], 0.001)


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		var value := pair[1] if pair.size() > 1 else ""
		match pair[0]:
			"setup": _setup_name = value
			"w": _size.x = int(value)
			"h": _size.y = int(value)
			"warmup": _warmup = int(value)
			"frames": _frames = int(value)
			"shot": _shot_path = value
			"sway": _sway = true
			"keep": _keep = true


func _max(values: PackedFloat64Array) -> float:
	var best := 0.0
	for v in values:
		best = maxf(best, v)
	return best
